use std::{
    fs::OpenOptions,
    io::Write,
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
use mlua::{prelude::*, Lua};
use ratatui::{backend::CrosstermBackend, Terminal};
use tui_widgets::scrollview::ScrollViewState;

use super::{
    nodes::{spawn_node_collector, SharedStats},
    ui::draw,
};
use crate::CLIENT_INSTANCE;

static STOP: AtomicBool = AtomicBool::new(false);

/// Start the live dashboard inside the PTY Neovim already created.
#[tracing::instrument]
pub fn start_dashboard(_lua: &Lua, pty_path: String) -> LuaResult<()> {
    STOP.store(false, Ordering::SeqCst);

    // ── open Neovim’s PTY slave ─────────────────────────────────
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .open(&pty_path)
        .map_err(|e| LuaError::ExternalError(Arc::new(e)))?;

    // ── spawn background collector ──────────────────────────────
    let stats: SharedStats = Arc::new(Mutex::new(Vec::new()));
    let client = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("client poisoned".into()))?
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("client not initialised".into()))?
        .clone();
    spawn_node_collector(stats.clone(), client);

    // ── Ratatui loop in its own thread ─────────────────────────
    thread::spawn(move || {
        let backend = CrosstermBackend::new(file);
        let mut term = Terminal::new(backend).unwrap();
        let mut scroll_state = ScrollViewState::default();

        // live tick-rate (ms); 50 ≤ tick ≤ 1000
        let mut tick_ms: u64 = 100;
        let mut last_tick = Instant::now();

        enable_raw_mode().ok();

        'ui: while !STOP.load(Ordering::Relaxed) {
            if event::poll(Duration::from_millis(0)).unwrap() {
                match event::read().unwrap() {
                    Event::Key(key) => match key.code {
                        // scrolling
                        KeyCode::Down | KeyCode::Char('j') => scroll_state.scroll_down(),
                        KeyCode::Up | KeyCode::Char('k') => scroll_state.scroll_up(),
                        KeyCode::PageDown => scroll_state.scroll_page_down(),
                        KeyCode::PageUp => scroll_state.scroll_page_up(),
                        // live tick-rate
                        KeyCode::Char('+') | KeyCode::Char('=') => {
                            if tick_ms > 50 {
                                tick_ms -= 50;
                            }
                        }
                        KeyCode::Char('-') | KeyCode::Char('_') => {
                            if tick_ms < 1000 {
                                tick_ms += 50;
                            }
                        }
                        // quit
                        KeyCode::Char('q') => break 'ui,
                        _ => {}
                    },
                    Event::Mouse(m) => match m.kind {
                        MouseEventKind::ScrollDown => scroll_state.scroll_down(),
                        MouseEventKind::ScrollUp => scroll_state.scroll_up(),
                        _ => {}
                    },
                    _ => {}
                }
            }

            if last_tick.elapsed() >= Duration::from_millis(tick_ms) {
                let snapshot = stats.lock().unwrap().clone();
                term.draw(|f| {
                    let area = f.area();
                    draw(f, &snapshot, area, &mut scroll_state);
                })
                .ok();
                last_tick = Instant::now();
            }
        }

        // ── graceful clear & restore ───────────────────────────
        let mut backend = term.backend_mut();
        queue!(backend, Clear(ClearType::All), cursor::MoveTo(0, 0)).ok();
        backend.flush().ok();
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
