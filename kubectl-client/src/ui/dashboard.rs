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
use libc::{dup2, ioctl, winsize, STDERR_FILENO, STDOUT_FILENO, TIOCGWINSZ};
use mlua::{prelude::*, Lua};
use ratatui::{backend::CrosstermBackend, layout::Rect, prelude::*, Terminal};
use tui_widgets::scrollview::ScrollViewState;

use crate::{
    ui::{
        nodes::{spawn_node_collector, SharedStats},
        overview_ui,
        overview_ui::OverviewState,
        top_ui,
    },
    CLIENT_INSTANCE,
};

// ─────── View abstraction ────────────────────────────────────────────────────

trait View {
    /// React to an input event, returning `true` when the UI changed and needs
    /// immediate redraw.
    fn on_event(&mut self, ev: &Event) -> bool;

    /// Render the UI.
    fn draw(&mut self, f: &mut Frame, area: Rect, stats: &[crate::ui::nodes::NodeStat]);
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

    fn draw(&mut self, f: &mut Frame, area: Rect, stats: &[crate::ui::nodes::NodeStat]) {
        overview_ui::draw(f, stats, area, &mut self.state);
    }
}

struct TopView {
    state: ScrollViewState,
}
impl TopView {
    fn new() -> Self {
        Self {
            state: ScrollViewState::default(),
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

    fn draw(&mut self, f: &mut Frame, area: Rect, stats: &[crate::ui::nodes::NodeStat]) {
        top_ui::draw(f, stats, area, &mut self.state);
    }
}

// ─────── Helpers ─────────────────────────────────────────────────────────────

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

// ─────── Public API ──────────────────────────────────────────────────────────

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
    let stats: SharedStats = Arc::new(Mutex::new(Vec::new()));
    let client = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("client poisoned".into()))?
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("client not initialised".into()))?
        .clone();
    spawn_node_collector(stats.clone(), client);

    // redirect stdout/stderr --------------------------------------------------
    unsafe {
        let fd: RawFd = file.as_raw_fd();
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

        let mut tick_ms: u64 = 200;
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
                    let snapshot = stats.lock().unwrap().clone();
                    term.draw(|f| {
                        let area = f.area();
                        active_view.draw(f, area, &snapshot);
                    })
                    .ok();
                    last_tick = Instant::now();
                    continue; // skip tick redraw this iteration
                }
            }

            // periodic redraw ------------------------------------------------
            if last_tick.elapsed() >= Duration::from_millis(tick_ms) {
                let snapshot = stats.lock().unwrap().clone();
                term.draw(|f| {
                    let area = f.area();
                    active_view.draw(f, area, &snapshot);
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
