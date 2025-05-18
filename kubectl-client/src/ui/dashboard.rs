//! dashboard.rs – fork-based TUI that recreates its own kube-client
//!                inside the child so state is preserved across restarts.

use std::{
    fs::OpenOptions,
    io::{Result as IoResult},
    os::fd::{AsRawFd, RawFd},
    ptr,
    sync::{
        Arc, Mutex, OnceLock,
    },
    time::{Duration, Instant},
};

use crossterm::{
    cursor,
    event::{self, Event, KeyCode, MouseEventKind},
    queue,
    terminal::{disable_raw_mode, enable_raw_mode, Clear, ClearType},
};
use libc::{
    _exit, close, dup2, fork, ioctl, kill, pid_t, setsid, waitpid,
    winsize, STDERR_FILENO, STDIN_FILENO, STDOUT_FILENO, TIOCGWINSZ,
    SIGTERM, SIGKILL, WNOHANG,
};
use mlua::{prelude::*, Lua};
use ratatui::{backend::CrosstermBackend, layout::Rect, prelude::*, Terminal};
use tokio::runtime::Runtime;
use tracing::info;

use crate::{
    ui::{
        nodes_state::{spawn_node_collector, NodeStat, SharedNodeStats},
        overview_ui,
        overview_ui::OverviewState,
        pods_state::{spawn_pod_collector, PodStat, SharedPodStats},
        top_ui,
        top_ui::TopViewState,
    },
};

/// ---------- View trait & two concrete views -------------------------------
trait View {
    fn on_event(&mut self, ev: &Event) -> bool;
    fn draw(&mut self, f: &mut Frame, area: Rect,
            node_stats: &[NodeStat], pod_stats: &[PodStat]);
}

struct OverviewView { state: OverviewState }
impl OverviewView { fn new() -> Self { Self { state: OverviewState::default() } } }
impl View for OverviewView {
    fn on_event(&mut self, ev: &Event) -> bool {
        match ev {
            Event::Key(k) => match k.code {
                KeyCode::Down | KeyCode::Char('j') => { self.state.scroll_down();  true }
                KeyCode::Up   | KeyCode::Char('k') => { self.state.scroll_up();    true }
                KeyCode::PageDown                  => { self.state.scroll_page_down(); true }
                KeyCode::PageUp                    => { self.state.scroll_page_up();   true }
                KeyCode::Tab                       => { self.state.focus_next();   true }
                KeyCode::BackTab                   => { self.state.focus_prev();   true }
                _ => false,
            },
            Event::Mouse(m) => match m.kind {
                MouseEventKind::ScrollDown => { self.state.scroll_down(); true }
                MouseEventKind::ScrollUp   => { self.state.scroll_up();   true }
                _ => false,
            },
            _ => false,
        }
    }
    fn draw(&mut self, f: &mut Frame, area: Rect,
            node_stats: &[NodeStat], _pod_stats: &[PodStat]) {
        overview_ui::draw(f, node_stats, area, &mut self.state);
    }
}

struct TopView { state: TopViewState }
impl TopView { fn new() -> Self { Self { state: TopViewState::default() } } }
impl View for TopView {
    fn on_event(&mut self, ev: &Event) -> bool {
        match ev {
            Event::Key(k) => match k.code {
                KeyCode::Down | KeyCode::Char('j') => { self.state.scroll_down();  true }
                KeyCode::Up   | KeyCode::Char('k') => { self.state.scroll_up();    true }
                KeyCode::PageDown                  => { self.state.scroll_page_down(); true }
                KeyCode::PageUp                    => { self.state.scroll_page_up();   true }
                KeyCode::Tab                       => { self.state.next_tab();      true }
                _ => false,
            },
            Event::Mouse(m) => match m.kind {
                MouseEventKind::ScrollDown => { self.state.scroll_down(); true }
                MouseEventKind::ScrollUp   => { self.state.scroll_up();   true }
                _ => false,
            },
            _ => false,
        }
    }
    fn draw(&mut self, f: &mut Frame, area: Rect,
            node_stats: &[NodeStat], pod_stats: &[PodStat]) {
        top_ui::draw(f, area, &mut self.state, node_stats, pod_stats);
    }
}

/// ---------- helpers --------------------------------------------------------
fn pty_size(file: &std::fs::File) -> IoResult<(u16, u16)> {
    unsafe {
        let mut ws: winsize = std::mem::zeroed();
        if ioctl(file.as_raw_fd(), TIOCGWINSZ, &mut ws) == 0 {
            Ok((ws.ws_col, ws.ws_row))
        } else {
            Err(std::io::Error::last_os_error())
        }
    }
}

/// ---------- global: PID of running dashboard ------------------------------
static CHILD_PID: OnceLock<Mutex<Option<pid_t>>> = OnceLock::new();
fn pid_slot() -> &'static Mutex<Option<pid_t>> { CHILD_PID.get_or_init(|| Mutex::new(None)) }

/// ---------- Lua API --------------------------------------------------------
#[tracing::instrument]
pub fn start_dashboard(_lua: &Lua, args: (String, String)) -> LuaResult<()> {
    let (pty_path, view_name) = args;

    // Kill previous child if it exists ---------------------------------------
    if let Some(old) = pid_slot().lock().unwrap().take() {
        unsafe {
            kill(old, SIGTERM);
            for _ in 0..30 {
                if waitpid(old, ptr::null_mut(), WNOHANG) == old { break }
                std::thread::sleep(Duration::from_millis(5));
            }
            kill(old, SIGKILL);
            let _ = waitpid(old, ptr::null_mut(), 0);
        }
    }

    // ---------------------------------------------------------------- fork --
    let pid = unsafe { fork() };
    if pid < 0 {
        return Err(LuaError::ExternalError(Arc::new(
            std::io::Error::last_os_error(),
        )));
    }

    if pid == 0 {
        // ======================= CHILD PROCESS ==============================
        unsafe { setsid(); }                             // own session

        // 1 ▸ Pick view ------------------------------------------------------
        let mut active_view: Box<dyn View + Send> = match view_name.to_ascii_lowercase().as_str() {
            "overview" | "overview_ui" => Box::new(OverviewView::new()),
            "top" | "top_ui"           => Box::new(TopView::new()),
            other => { eprintln!("unknown view: {other}"); unsafe { _exit(1) } }
        };

        // 2 ▸ Open PTY -------------------------------------------------------
        let file = match OpenOptions::new().read(true).write(true).open(&pty_path) {
            Ok(f)  => f,
            Err(e) => { eprintln!("open pty failed: {e}"); unsafe { _exit(1) } }
        };

        // 3 ▸ Redirect stdio -------------------------------------------------
        unsafe {
            let fd: RawFd = file.as_raw_fd();
            dup2(fd, STDIN_FILENO);
            dup2(fd, STDOUT_FILENO);
            dup2(fd, STDERR_FILENO);
        }

        // 4 ▸ Runtime + kube client -----------------------------------------
        let rt = Runtime::new().expect("tokio runtime");
        let node_stats: SharedNodeStats = Arc::new(Mutex::new(Vec::new()));
        let pod_stats : SharedPodStats  = Arc::new(Mutex::new(Vec::new()));

        // Spawn collectors inside the runtime
        rt.block_on(async {
            let client = kube::Client::try_default()
                .await
                .expect("kube config");

            spawn_node_collector(node_stats.clone(), client.clone());
            spawn_pod_collector (pod_stats .clone(), client.clone());
        });

        // 5 ▸ UI loop --------------------------------------------------------
        const TICK_MS: u64 = 200;
        let (w, h) = pty_size(&file).unwrap_or((80, 24));
        let backend = CrosstermBackend::new(file);
        let mut term = Terminal::new(backend).unwrap();
        term.resize(Rect::new(0, 0, w, h)).unwrap();
        enable_raw_mode().ok();

        let mut last_tick = Instant::now();
        'ui: loop {
            if event::poll(Duration::from_millis(0)).unwrap() {
                let ev = event::read().unwrap();
                match &ev {
                    Event::Key(k) if k.code == KeyCode::Char('q') => break 'ui,
                    Event::Resize(_, _) => term.autoresize().ok().unwrap_or_default(),
                    _ => {}
                }
                if active_view.on_event(&ev) {
                    let nodes = node_stats.lock().unwrap().clone();
                    let pods  = pod_stats .lock().unwrap().clone();
                    term.draw(|f| {
                        let area = f.area();
                        active_view.draw(f, area, &nodes, &pods);
                    }).ok();
                    last_tick = Instant::now();
                    continue;
                }
            }
            if last_tick.elapsed() >= Duration::from_millis(TICK_MS) {
                let nodes = node_stats.lock().unwrap().clone();
                let pods  = pod_stats .lock().unwrap().clone();
                term.draw(|f| {
                    let area = f.area();
                    active_view.draw(f, area, &nodes, &pods);
                }).ok();
                last_tick = Instant::now();
            }
        }

        // 6 ▸ Cleanup --------------------------------------------------------
        let backend = term.backend_mut();
        queue!(backend, Clear(ClearType::All), cursor::MoveTo(0, 0)).ok();
        disable_raw_mode().ok();
        let _ = term.show_cursor();

        unsafe { _exit(0) };
    }

    // --------------- parent: remember PID and return ------------------------
    *pid_slot().lock().unwrap() = Some(pid);
    Ok(())
}

#[tracing::instrument]
pub fn stop_dashboard(_lua: &Lua, _args: ()) -> LuaResult<()> {
    if let Some(pid) = pid_slot().lock().unwrap().take() {
        unsafe {
            kill(pid, SIGTERM);
            let _ = waitpid(pid, ptr::null_mut(), 0);
        }
    }
    Ok(())
}
