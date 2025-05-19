use std::{
    fs::OpenOptions,
    io::Result as IoResult,
    os::fd::{AsRawFd, RawFd},
    ptr,
    sync::{Arc, Mutex, OnceLock},
    time::{Duration, Instant},
};

use crossterm::{
    cursor,
    event::{self, Event, KeyCode, MouseEventKind},
    queue,
    terminal::{disable_raw_mode, enable_raw_mode, Clear, ClearType},
};
use kube::{config::KubeConfigOptions, Client, Config};
use libc::{
    _exit, dup2, fork, ioctl, kill, pid_t, waitpid, winsize, SIGKILL, SIGTERM, STDERR_FILENO,
    STDIN_FILENO, STDOUT_FILENO, TIOCGWINSZ, WNOHANG,
};
use mlua::{prelude::*, Lua};
use ratatui::{backend::CrosstermBackend, layout::Rect, prelude::*, Terminal};
use tokio::runtime::Runtime;

use crate::{
    metrics::nodes::{spawn_node_collector, NodeStat, SharedNodeStats},
    ui::{
        overview_ui::{self, OverviewState},
        top_ui::{self, TopViewState},
    },
    ACTIVE_CONTEXT,
};

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

macro_rules! scroll_nav {
    ($state:expr, $key:expr) => {{
        match $key {
            KeyCode::Down | KeyCode::Char('j') => {
                $state.scroll_down();
                true
            }
            KeyCode::Up | KeyCode::Char('k') => {
                $state.scroll_up();
                true
            }
            KeyCode::PageDown => {
                $state.scroll_page_down();
                true
            }
            KeyCode::PageUp => {
                $state.scroll_page_up();
                true
            }
            _ => false,
        }
    }};
}

// ——————————————————————————————————  View trait & concrete views  ——————————————————————————————————
trait View {
    fn on_event(&mut self, ev: &Event) -> bool;
    fn draw(&mut self, f: &mut Frame, area: Rect, nodes: &[NodeStat]);
}

struct OverviewView {
    state: OverviewState,
}
impl OverviewView {
    fn new() -> Self {
        Self {
            state: OverviewState::default(),
        }
    }
}
impl View for OverviewView {
    fn on_event(&mut self, ev: &Event) -> bool {
        match ev {
            Event::Key(k) => match k.code {
                KeyCode::Tab => {
                    self.state.focus_next();
                    true
                }
                KeyCode::BackTab => {
                    self.state.focus_prev();
                    true
                }
                other => scroll_nav!(self.state, other),
            },
            Event::Mouse(m) => match m.kind {
                MouseEventKind::ScrollDown => {
                    self.state.scroll_down();
                    true
                }
                MouseEventKind::ScrollUp => {
                    self.state.scroll_up();
                    true
                }
                _ => false,
            },
            _ => false,
        }
    }

    fn draw(&mut self, f: &mut Frame, area: Rect, nodes: &[NodeStat]) {
        overview_ui::draw(f, nodes, area, &mut self.state);
    }
}

struct TopView {
    state: TopViewState,
}
impl TopView {
    fn new() -> Self {
        Self {
            state: TopViewState::default(),
        }
    }
}
impl View for TopView {
    fn on_event(&mut self, ev: &Event) -> bool {
        match ev {
            Event::Key(k) => match k.code {
                KeyCode::Tab => {
                    self.state.next_tab();
                    true
                }
                other => scroll_nav!(self.state, other),
            },
            Event::Mouse(m) => match m.kind {
                MouseEventKind::ScrollDown => {
                    self.state.scroll_down();
                    true
                }
                MouseEventKind::ScrollUp => {
                    self.state.scroll_up();
                    true
                }
                _ => false,
            },
            _ => false,
        }
    }

    fn draw(&mut self, f: &mut Frame, area: Rect, nodes: &[NodeStat]) {
        top_ui::draw(f, area, &mut self.state, nodes);
    }
}

// ——————————————————————————————————  Global child‑PID slot  ——————————————————————————————————
static CHILD_PID: OnceLock<Mutex<Option<pid_t>>> = OnceLock::new();
static TAIL_PID: OnceLock<Mutex<Option<pid_t>>> = OnceLock::new();
fn tail_slot() -> &'static Mutex<Option<pid_t>> {
    TAIL_PID.get_or_init(|| Mutex::new(None))
}
fn pid_slot() -> &'static Mutex<Option<pid_t>> {
    CHILD_PID.get_or_init(|| Mutex::new(None))
}

// ——————————————————————————————————  Child UI loop  ——————————————————————————————————
/// Runs inside the *child* after stdio is already redirected onto the PTY.
fn ui_loop(
    mut active_view: Box<dyn View + Send>,
    file: std::fs::File,
    node_stats: SharedNodeStats,
) -> ! {
    // 1 ▸ Terminal setup ----------------------------------------------------
    const TICK_MS: u64 = 200;
    let (w, h) = pty_size(&file).unwrap_or((80, 24));
    let backend = CrosstermBackend::new(file);
    let mut term = Terminal::new(backend).expect("terminal");
    term.resize(Rect::new(0, 0, w, h)).ok();
    enable_raw_mode().ok();

    // 2 ▸ Event / draw loop -------------------------------------------------
    let mut last_tick = Instant::now();
    'ui: loop {
        // — input —
        if event::poll(Duration::from_millis(0)).unwrap() {
            let ev = event::read().unwrap();
            match &ev {
                Event::Key(k) if k.code == KeyCode::Char('q') => {
                    let maybe_tail = tail_slot().lock().unwrap().take();
                    if let Some(tail) = maybe_tail {
                        unsafe {
                            libc::kill(tail, libc::SIGINT);
                        }
                    }
                    break 'ui;
                }
                Event::Resize(_, _) => term.autoresize().ok().unwrap_or_default(),
                _ => {}
            }
            if active_view.on_event(&ev) {
                let nodes = node_stats.lock().unwrap().clone();
                term.draw(|f| {
                    let area = f.area();
                    active_view.draw(f, area, &nodes);
                })
                .ok();
                last_tick = Instant::now();
                continue;
            }
        }

        // — tick —
        if last_tick.elapsed() >= Duration::from_millis(TICK_MS) {
            let nodes = node_stats.lock().unwrap().clone();
            term.draw(|f| {
                let area = f.area();
                active_view.draw(f, area, &nodes);
            })
            .ok();
            last_tick = Instant::now();
        }
    }

    // 3 ▸ Cleanup ----------------------------------------------------------
    let backend = term.backend_mut();
    queue!(backend, Clear(ClearType::All), cursor::MoveTo(0, 0)).ok();
    disable_raw_mode().ok();
    let _ = term.show_cursor();

    unsafe { _exit(0) } // never returns
}

#[tracing::instrument]
pub fn start_dashboard(_lua: &Lua, args: (String, String, i64)) -> LuaResult<()> {
    let (pty_path, view_name, tail_pid) = args;

    *tail_slot().lock().unwrap() = Some(tail_pid as pid_t);
    // 0 ▸ If a dashboard is already running, politely stop it --------------
    if let Some(old) = pid_slot().lock().unwrap().take() {
        unsafe {
            kill(old, SIGTERM);
            for _ in 0..30 {
                if waitpid(old, ptr::null_mut(), WNOHANG) == old {
                    break;
                }
                std::thread::sleep(Duration::from_millis(5));
            }
            kill(old, SIGKILL); // force if still around
            let _ = waitpid(old, ptr::null_mut(), 0);
        }
    }

    // 1 ▸ Fork -------------------------------------------------------------
    let pid = unsafe { fork() };
    if pid < 0 {
        return Err(LuaError::ExternalError(Arc::new(
            std::io::Error::last_os_error(),
        )));
    }

    if pid == 0 {
        // ====================== CHILD PROCESS =============================
        // 1 ▸ Resolve which view to start ----------------------------------
        let active_view: Box<dyn View + Send> = match view_name.to_ascii_lowercase().as_str() {
            "overview" | "overview_ui" => Box::new(OverviewView::new()),
            "top" | "top_ui" => Box::new(TopView::new()),
            other => {
                eprintln!("unknown view: {other}");
                unsafe { _exit(1) }
            }
        };

        // 2 ▸ Open the PTY -------------------------------------------------
        let file = match OpenOptions::new().read(true).write(true).open(&pty_path) {
            Ok(f) => f,
            Err(e) => {
                eprintln!("open pty failed: {e}");
                unsafe { _exit(1) }
            }
        };
        // 3 ▸ Redirect stdio ----------------------------------------------
        unsafe {
            let fd: RawFd = file.as_raw_fd();
            dup2(fd, STDIN_FILENO);
            dup2(fd, STDOUT_FILENO);
            dup2(fd, STDERR_FILENO);
        }

        // 4 ▸ Build runtime + collectors -----------------------------------
        let rt = Runtime::new().expect("tokio runtime");
        let node_stats: SharedNodeStats = Arc::new(Mutex::new(Vec::new()));

        let opts = KubeConfigOptions {
            context: ACTIVE_CONTEXT.read().unwrap().clone(),
            cluster: None,
            user: None,
        };
        let client: Client = rt.block_on(async {
            let cfg = Config::from_kubeconfig(&opts).await.expect("kube-config");
            Client::try_from(cfg).expect("client from ACTIVE_CONTEXT")
        });
        rt.block_on(async {
            spawn_node_collector(node_stats.clone(), client.clone());
        });

        // 5 ▸ Hand over to the TUI loop (never returns) --------------------
        ui_loop(active_view, file, node_stats);
    }

    // ============= parent ============ ------------------------------------
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
