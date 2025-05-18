use std::{
    fs::OpenOptions,
    io::Result as IoResult,
    os::fd::{AsRawFd, RawFd},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    thread,
    time::{Duration, Instant},
};

use crossterm::{
    cursor,
    event::{self, Event, KeyCode, MouseEventKind},
    queue,
    terminal::{disable_raw_mode, enable_raw_mode, Clear, ClearType},
};
use libc::{dup2, ioctl, winsize, STDERR_FILENO, STDIN_FILENO, STDOUT_FILENO, TIOCGWINSZ};
use mlua::{prelude::*, Lua};
use ratatui::{backend::CrosstermBackend, layout::Rect, prelude::*, Terminal};

use crate::{
    ui::{
        nodes_state::{spawn_node_collector, NodeStat, SharedNodeStats},
        overview_ui,
        overview_ui::OverviewState,
        pods_state::{spawn_pod_collector, PodStat, SharedPodStats},
        top_ui,
        top_ui::TopViewState,
    },
    CLIENT_INSTANCE,
};

trait View {
    fn on_event(&mut self, ev: &Event) -> bool;
    fn draw(&mut self, f: &mut Frame, area: Rect, node_stats: &[NodeStat], pod_stats: &[PodStat]);
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
                KeyCode::Down | KeyCode::Char('j') => {
                    self.state.scroll_down();
                    true
                }
                KeyCode::Up | KeyCode::Char('k') => {
                    self.state.scroll_up();
                    true
                }
                KeyCode::PageDown => {
                    self.state.scroll_page_down();
                    true
                }
                KeyCode::PageUp => {
                    self.state.scroll_page_up();
                    true
                }
                KeyCode::Tab => {
                    self.state.focus_next();
                    true
                }
                KeyCode::BackTab => {
                    self.state.focus_prev();
                    true
                }
                _ => false,
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

    fn draw(&mut self, f: &mut Frame, area: Rect, node_stats: &[NodeStat], pod_stats: &[PodStat]) {
        overview_ui::draw(f, node_stats, area, &mut self.state);
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
                KeyCode::Down | KeyCode::Char('j') => {
                    self.state.scroll_down();
                    true
                }
                KeyCode::Up | KeyCode::Char('k') => {
                    self.state.scroll_up();
                    true
                }
                KeyCode::PageDown => {
                    self.state.scroll_page_down();
                    true
                }
                KeyCode::PageUp => {
                    self.state.scroll_page_up();
                    true
                }
                KeyCode::Tab => {
                    self.state.next_tab();
                    true
                }
                _ => false,
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

    fn draw(&mut self, f: &mut Frame, area: Rect, node_stats: &[NodeStat], pods_stats: &[PodStat]) {
        top_ui::draw(f, area, &mut self.state, node_stats, pods_stats);
    }
}

static STOP: AtomicBool = AtomicBool::new(false);

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

#[tracing::instrument]
pub fn start_dashboard(_lua: &Lua, args: (String, String)) -> LuaResult<()> {
    let (pty_path, view_name) = args;

    // select view -------------------------------------------------------------
    let mut active_view: Box<dyn View + Send> = match view_name.to_ascii_lowercase().as_str() {
        "overview" | "overview_ui" => Box::new(OverviewView::new()),
        "top" | "top_ui" => Box::new(TopView::new()),
        other => {
            return Err(LuaError::RuntimeError(format!(
                "unknown dashboard view: {other}"
            )))
        }
    };

    // open PTY ---------------------------------------------------------------
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .open(&pty_path)
        .map_err(|e| LuaError::ExternalError(Arc::new(e)))?;

    // live collector ---------------------------------------------------------
    let node_stats: SharedNodeStats = Arc::new(Mutex::new(Vec::new()));
    let pod_stats: SharedPodStats = Arc::new(Mutex::new(Vec::new()));

    let client = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("client poisoned".into()))?
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("client not initialised".into()))?
        .clone();

    spawn_node_collector(node_stats.clone(), client.clone());
    spawn_pod_collector(pod_stats.clone(), client.clone());

    // redirect stdout/stderr --------------------------------------------------
    unsafe {
        let fd: RawFd = file.as_raw_fd();
        dup2(fd, STDIN_FILENO);
        dup2(fd, STDOUT_FILENO);
        dup2(fd, STDERR_FILENO);
    }

    STOP.store(false, Ordering::SeqCst);

    // UI thread --------------------------------------------------------------
    thread::spawn(move || {
        // term bootstrap -----------------------------------------------------
        let (w, h) = pty_size(&file).unwrap_or((80, 24));
        let backend = CrosstermBackend::new(file);
        let mut term = Terminal::new(backend).unwrap();
        term.resize(Rect::new(0, 0, w, h)).unwrap();
        enable_raw_mode().ok();

        let tick_ms: u64 = 200;
        let mut last_tick = Instant::now();

        'ui: while !STOP.load(Ordering::Relaxed) {
            // input ----------------------------------------------------------
            if event::poll(Duration::from_millis(0)).unwrap() {
                let ev = event::read().unwrap();

                // global bindings -------------------------------------------
                match &ev {
                    Event::Key(k) if k.code == KeyCode::Char('q') => break 'ui,
                    Event::Resize(_, _) => term.autoresize().ok().unwrap_or_default(),
                    _ => {}
                }

                // delegate to the view & redraw immediately if mutated ------
                if active_view.on_event(&ev) {
                    let node_snapshot = node_stats.lock().unwrap().clone();
                    let pod_snapshot = pod_stats.lock().unwrap().clone();
                    term.draw(|f| {
                        let area = f.area();
                        active_view.draw(f, area, &node_snapshot, &pod_snapshot);
                    })
                    .ok();
                    last_tick = Instant::now();
                    continue; // skip tick redraw this iteration
                }
            }

            // periodic redraw ------------------------------------------------
            if last_tick.elapsed() >= Duration::from_millis(tick_ms) {
                let node_snapshot = node_stats.lock().unwrap().clone();
                let pod_snapshot = pod_stats.lock().unwrap().clone();
                term.draw(|f| {
                    let area = f.area();
                    active_view.draw(f, area, &node_snapshot, &pod_snapshot);
                })
                .ok();
                last_tick = Instant::now();
            }
        }

        // cleanup ------------------------------------------------------------
        let backend = term.backend_mut();
        queue!(backend, Clear(ClearType::All), cursor::MoveTo(0, 0)).ok();
        disable_raw_mode().ok();
        let _ = term.show_cursor();
    });

    Ok(())
}

#[tracing::instrument]
pub fn stop_dashboard(_lua: &Lua, _args: ()) -> LuaResult<()> {
    STOP.store(true, Ordering::SeqCst);
    Ok(())
}
