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
use ratatui::{backend::CrosstermBackend, layout::Rect, Terminal};
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

static STOP: AtomicBool = AtomicBool::new(false);

/// The screens the dashboard can show.
#[derive(Clone, Copy)]
enum ActiveView {
    Overview,
    Top,
}

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

    let active_view = match view_name.to_ascii_lowercase().as_str() {
        "overview" | "overview_ui" => ActiveView::Overview,
        "top" | "top_ui" => ActiveView::Top,
        other => {
            return Err(LuaError::RuntimeError(format!(
                "unknown dashboard view: {other}"
            )))
        }
    };

    /* 1 ▸ open the PTY slave Neovim created for the float */
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .open(&pty_path)
        .map_err(|e| LuaError::ExternalError(Arc::new(e)))?;

    /* 2 ▸ live collector running in background */
    let stats: SharedStats = Arc::new(Mutex::new(Vec::new()));
    let client = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("client poisoned".into()))?
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("client not initialised".into()))?
        .clone();
    spawn_node_collector(stats.clone(), client);

    /*── redirect stdout/stderr to PTY ─────────────────────────────*/
    unsafe {
        let fd: RawFd = file.as_raw_fd();
        dup2(fd, STDOUT_FILENO);
        dup2(fd, STDERR_FILENO);
    }

    STOP.store(false, Ordering::SeqCst);

    /*──────────────────── UI thread ───────────────────────────────*/
    thread::spawn(move || {
        /* terminal bootstrap */
        let (w, h) = pty_size(&file).unwrap_or((80, 24));
        let backend = CrosstermBackend::new(file);
        let mut term = Terminal::new(backend).unwrap();
        term.resize(Rect::new(0, 0, w, h)).unwrap();
        enable_raw_mode().ok();

        /* one state object per screen */
        let mut overview_state = OverviewState::default();
        let mut top_state = ScrollViewState::default();

        let mut tick_ms: u64 = 200;
        let mut last_tick = Instant::now();

        'ui: while !STOP.load(Ordering::Relaxed) {
            /*── handle input (non-blocking) ──────────────────*/
            if event::poll(Duration::from_millis(0)).unwrap() {
                match event::read().unwrap() {
                    Event::Key(k) => match k.code {
                        KeyCode::Down | KeyCode::Char('j') => match active_view {
                            ActiveView::Overview => overview_state.scroll_down(),
                            ActiveView::Top => top_state.scroll_down(),
                        },
                        KeyCode::Up | KeyCode::Char('k') => match active_view {
                            ActiveView::Overview => overview_state.scroll_up(),
                            ActiveView::Top => top_state.scroll_up(),
                        },
                        KeyCode::PageDown => match active_view {
                            ActiveView::Overview => overview_state.scroll_page_down(),
                            ActiveView::Top => top_state.scroll_page_down(),
                        },
                        KeyCode::PageUp => match active_view {
                            ActiveView::Overview => overview_state.scroll_page_up(),
                            ActiveView::Top => top_state.scroll_page_up(),
                        },

                        KeyCode::Tab if matches!(active_view, ActiveView::Overview) => {
                            overview_state.focus_next()
                        }
                        KeyCode::BackTab if matches!(active_view, ActiveView::Overview) => {
                            overview_state.focus_prev()
                        }

                        KeyCode::Char('+') | KeyCode::Char('=') if tick_ms > 50 => tick_ms -= 50,
                        KeyCode::Char('-') | KeyCode::Char('_') if tick_ms < 1000 => tick_ms += 50,

                        /* quit */
                        KeyCode::Char('q') => break 'ui,
                        _ => {}
                    },

                    /* mouse wheel */
                    Event::Mouse(m) => match m.kind {
                        MouseEventKind::ScrollDown => match active_view {
                            ActiveView::Overview => overview_state.scroll_down(),
                            ActiveView::Top => top_state.scroll_down(),
                        },
                        MouseEventKind::ScrollUp => match active_view {
                            ActiveView::Overview => overview_state.scroll_up(),
                            ActiveView::Top => top_state.scroll_up(),
                        },
                        _ => {}
                    },

                    /* resize */
                    Event::Resize(_, _) => {
                        term.autoresize().ok();
                    }
                    _ => {}
                }
            }

            /* ── periodic redraw ────────────────────────────────────────── */
            if last_tick.elapsed() >= Duration::from_millis(tick_ms) {
                let snapshot = stats.lock().unwrap().clone();
                term.draw(|f| {
                    let rect = f.area();
                    match active_view {
                        ActiveView::Overview => {
                            overview_ui::draw(f, &snapshot, rect, &mut overview_state)
                        }
                        ActiveView::Top => top_ui::draw(f, &snapshot, rect, &mut top_state),
                    }
                })
                .ok();
                last_tick = Instant::now();
            }
        }

        /*── cleanup ──────────────────────────────────────────*/
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
