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
    cursor, event, queue,
    terminal::{disable_raw_mode, enable_raw_mode, Clear, ClearType},
};
use libc::{dup2, ioctl, winsize, STDERR_FILENO, STDOUT_FILENO, TIOCGWINSZ};
use mlua::{prelude::*, Lua};
use ratatui::{backend::CrosstermBackend, layout::Rect, Terminal};
use tui_widgets::scrollview::ScrollViewState;

use super::{
    nodes::{spawn_node_collector, SharedStats},
    top_ui::draw,
};
use crate::CLIENT_INSTANCE;

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
pub fn start_dashboard(_lua: &Lua, pty_path: String) -> LuaResult<()> {
    STOP.store(false, Ordering::SeqCst);

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

    /* 3 ▸ UI thread */
    unsafe {
        let slave_fd: RawFd = file.as_raw_fd();
        dup2(slave_fd, STDOUT_FILENO); // crossterm::terminal::size() hits the slave
        dup2(slave_fd, STDERR_FILENO); // stderr goes to the same PTY (optional)
    }

    thread::spawn(move || {
        let (w, h) = pty_size(&file).unwrap_or((80, 24));
        let backend = CrosstermBackend::new(file);
        let mut term = Terminal::new(backend).unwrap();
        term.resize(Rect::new(0, 0, w, h)).unwrap();
        enable_raw_mode().ok();

        let mut scroll_state = ScrollViewState::default();
        let mut tick_ms: u64 = 200;
        let mut last_tick = Instant::now();

        'ui: while !STOP.load(Ordering::Relaxed) {
            /* ── non-blocking input ─────────────────────────────────────── */
            if event::poll(Duration::from_millis(0)).unwrap() {
                match event::read().unwrap() {
                    event::Event::Key(k) => match k.code {
                        /* scrolling */
                        event::KeyCode::Down | event::KeyCode::Char('j') => {
                            scroll_state.scroll_down()
                        }
                        event::KeyCode::Up | event::KeyCode::Char('k') => scroll_state.scroll_up(),
                        event::KeyCode::PageDown => scroll_state.scroll_page_down(),
                        event::KeyCode::PageUp => scroll_state.scroll_page_up(),
                        /* tick-rate */
                        event::KeyCode::Char('+') | event::KeyCode::Char('=') if tick_ms > 50 => {
                            tick_ms -= 50
                        }
                        event::KeyCode::Char('-') | event::KeyCode::Char('_') if tick_ms < 1000 => {
                            tick_ms += 50
                        }
                        /* quit */
                        event::KeyCode::Char('q') => break 'ui,
                        _ => {}
                    },
                    event::Event::Mouse(m) => match m.kind {
                        event::MouseEventKind::ScrollDown => scroll_state.scroll_down(),
                        event::MouseEventKind::ScrollUp => scroll_state.scroll_up(),
                        _ => {}
                    },
                    event::Event::Resize(_, _) => {
                        term.autoresize().ok(); // ratatui ≥ 0.26
                    }
                    _ => {}
                }
            }

            /* ── periodic redraw ────────────────────────────────────────── */
            if last_tick.elapsed() >= Duration::from_millis(tick_ms) {
                let snapshot = stats.lock().unwrap().clone();
                term.draw(|f| {
                    draw(f, &snapshot, f.area(), &mut scroll_state);
                })
                .ok();
                last_tick = Instant::now();
            }
        }

        /* ── graceful clear & restore ──────────────────────────────────── */
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
