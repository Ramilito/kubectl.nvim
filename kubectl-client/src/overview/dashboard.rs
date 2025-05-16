use std::{
    fs::File,
    os::unix::io::{FromRawFd, IntoRawFd, RawFd},
    sync::{Arc, Mutex},
    thread,
    time::Duration,
};

use mlua::{prelude::*, Lua};
use nix::pty::openpty;
use ratatui::{backend::CrosstermBackend, Terminal};

use crate::CLIENT_INSTANCE;

use super::{
    nodes::{spawn_node_collector, SharedStats},
    ui::draw,
};

#[tracing::instrument]
pub fn start_dashboard(_lua: &Lua, (w, _h): (u16, u16)) -> LuaResult<i32> {
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

        loop {
            let snapshot = stats.lock().unwrap().clone();
            let _ = term.draw(|f| draw(f, &snapshot));
            thread::sleep(Duration::from_millis(200));
        }
    });

    Ok(master_fd) // Lua pumps this FD into nvim_chan_send
}
