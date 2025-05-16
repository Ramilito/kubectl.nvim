use std::{
    fs::File,
    os::unix::io::{FromRawFd, IntoRawFd, RawFd},
    sync::Arc,
    thread,
    time::Duration,
};

use mlua::{prelude::*, Lua};
use nix::pty::openpty;
use ratatui::{
    backend::CrosstermBackend,
    layout::Rect,
    style::{Modifier, Style},
    widgets::{Block, Borders, Paragraph},
    Terminal,
};

/// Called from Lua: `start_dashboard_pty(width, height) -> master_fd`
pub fn start_dashboard(_lua: &Lua, (w, _h): (u16, u16)) -> LuaResult<i32> {
    // 1. open PTY (master/slave)
    let pty = openpty(None, None).map_err(|e| LuaError::ExternalError(Arc::new(e)))?;

    // take raw fds (ownership moves out of `pty`)
    let master_fd: RawFd = pty.master.into_raw_fd();
    let slave_fd: RawFd = pty.slave.into_raw_fd();

    // 2. spawn Ratatui thread on the slave side
    let inner_w = w.saturating_sub(2).max(1);
    thread::spawn(move || {
        // SAFETY: we exclusively own `slave_fd`
        let file = unsafe { File::from_raw_fd(slave_fd) };
        let backend = CrosstermBackend::new(file);
        let mut term = Terminal::new(backend).unwrap();

        let mut pos = 1u16;
        loop {
            let _ = term.draw(|f| {
                let size = f.area();

                let frame = Block::default()
                    .title(" PTY-powered dashboard ")
                    .borders(Borders::ALL)
                    .border_style(Style::default().add_modifier(Modifier::BOLD));
                f.render_widget(frame, size);

                let mut row = String::with_capacity(inner_w as usize);
                for x in 0..inner_w {
                    row.push(if x + 1 == pos { '●' } else { ' ' });
                }

                let area = Rect {
                    x: size.x + 1,
                    y: size.y + 2,
                    width: inner_w,
                    height: 1,
                };
                f.render_widget(Paragraph::new(row), area);
            });

            pos = if pos == inner_w { 1 } else { pos + 1 };
            thread::sleep(Duration::from_millis(70));
        }
    });

    // 3. return the master FD to Lua (so it can pipe bytes into nvim)
    Ok(master_fd)
}
