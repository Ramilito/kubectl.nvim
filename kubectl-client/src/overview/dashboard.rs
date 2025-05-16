use std::{
    fs::File,
    os::unix::io::{FromRawFd, IntoRawFd, RawFd},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    thread,
    time::Duration,
};

use mlua::{prelude::*, Lua};
use nix::pty::openpty;
use ratatui::{backend::CrosstermBackend, layout::Rect, Terminal};
use tracing::info;

use crate::CLIENT_INSTANCE;

use super::{
    nodes::{spawn_node_collector, SharedStats},
    ui::draw,
};

static STOP: AtomicBool = AtomicBool::new(false);

#[tracing::instrument]
pub fn start_dashboard(_lua: &Lua, (_w, _h): (u16, u16)) -> LuaResult<i32> {
    STOP.store(false, Ordering::SeqCst);
    // ── PTY ───────────────────────────────────────────────────────
    let pty = openpty(None, None).map_err(|e| LuaError::ExternalError(Arc::new(e)))?;
    let master_fd: RawFd = pty.master.into_raw_fd();
    let slave_fd: RawFd = pty.slave.into_raw_fd();

    // ── shared stats + collector ─────────────────────────────────
    let stats: SharedStats = Arc::new(Mutex::new(Vec::new()));
    let client = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("client poisoned".into()))?
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("client not initialised".into()))?
        .clone();

    spawn_node_collector(stats.clone(), client);

    // ── Ratatui draw loop on the slave side ──────────────────────
    thread::spawn(move || {
        // SAFETY: this thread owns `slave_fd`
        let file = unsafe { File::from_raw_fd(slave_fd) };
        let backend = CrosstermBackend::new(file);
        let mut term = Terminal::new(backend).unwrap();
        term.resize(Rect::new(0, 0, 10, 10));

        while !STOP.load(Ordering::Relaxed) {
            info!("looping");
            let snapshot = stats.lock().unwrap().clone();
            let _ = term.draw(|f| draw(f, &snapshot));
            thread::sleep(Duration::from_millis(1000));
        }
    });

    Ok(master_fd) // Lua pumps this FD into nvim_chan_send
}

#[tracing::instrument]
pub fn stop_dashboard(_lua: &Lua, _args: ()) -> LuaResult<()> {
    STOP.store(true, Ordering::SeqCst);
    Ok(())
}
