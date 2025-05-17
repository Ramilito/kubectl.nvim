use std::{
    fs::OpenOptions,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    thread,
    time::{Duration, Instant},
};

use crossterm::{
    event::{self, Event, KeyCode},
    terminal::{disable_raw_mode, enable_raw_mode},
};
use mlua::{prelude::*, Lua};
use ratatui::{backend::CrosstermBackend, Terminal};
use tracing::info;
use tui_widgets::scrollview::ScrollViewState;

use crate::CLIENT_INSTANCE;

use super::{
    nodes::{spawn_node_collector, SharedStats},
    ui::draw,
};

static STOP: AtomicBool = AtomicBool::new(false);

/// Start the live dashboard inside the PTY Neovim already created.
///
/// `pty_path` is a string like "/dev/pts/11", obtained in Lua via
/// `vim.api.nvim_get_chan_info(job_id).pty`.
#[tracing::instrument]
pub fn start_dashboard(_lua: &Lua, pty_path: String) -> LuaResult<()> {
    STOP.store(false, Ordering::SeqCst);

    // ── open the existing PTY slave ─────────────────────────────
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .open(&pty_path)
        .map_err(|e| LuaError::ExternalError(Arc::new(e)))?;

    // ── shared stats + node collector ──────────────────────────
    let stats: SharedStats = Arc::new(Mutex::new(Vec::new()));
    let client = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("client poisoned".into()))?
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("client not initialised".into()))?
        .clone();
    spawn_node_collector(stats.clone(), client);

    // ── Ratatui draw / event loop (runs in its own thread) ─────
    thread::spawn(move || {
        let backend = CrosstermBackend::new(file);
        let mut term = Terminal::new(backend).unwrap();
        let mut scroll_state = ScrollViewState::default();

        enable_raw_mode().ok();
        let tick_rate = Duration::from_millis(100);
        let mut last_tick = Instant::now();

        while !STOP.load(Ordering::Relaxed) {
            // ── 1 ▸ handle keyboard input (non-blocking) ──────
            if event::poll(Duration::from_millis(0)).unwrap() {
                if let Event::Key(key) = event::read().unwrap() {
                    info!("{:?}", key);
                    match key.code {
                        KeyCode::Down | KeyCode::Char('j') => scroll_state.scroll_down(),
                        KeyCode::Up | KeyCode::Char('k') => scroll_state.scroll_up(),
                        KeyCode::PageDown => scroll_state.scroll_page_down(),
                        KeyCode::PageUp => scroll_state.scroll_page_up(),
                        KeyCode::Char('q') => break,
                        _ => {}
                    }
                }
            }

            // ── 2 ▸ redraw at fixed tick rate ─────────────────
            if last_tick.elapsed() >= tick_rate {
                let snapshot = stats.lock().unwrap().clone();
                term.draw(|f| {
                    let area = f.area();
                    draw(f, &snapshot, area, &mut scroll_state);
                })
                .ok();
                last_tick = Instant::now();
            }
        }

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
