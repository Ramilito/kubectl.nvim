//! Top dashboard
//!
//!   Lua: start_topview("/dev/pts/43")
//!        stop_topview()
//!
//!   Host `main.rs` must call once near the top:
//!        ui::top_dashboard::maybe_run_top_child();

use std::{
    fs::OpenOptions,
    io,
    os::fd::AsRawFd,
    process::{Child, Command, Stdio},
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use crossterm::{
    cursor,
    event::{self, Event, KeyCode, MouseEventKind},
    queue,
    terminal::{disable_raw_mode, enable_raw_mode, Clear, ClearType},
};
use libc::{ioctl, winsize, TIOCGWINSZ};
use mlua::{prelude::*, Lua};
use ratatui::{backend::CrosstermBackend, layout::Rect, prelude::*, Terminal};
use tracing::info;

use crate::{
    ui::{
        nodes_state::{spawn_node_collector, NodeStat, SharedNodeStats},
        pods_state::{spawn_pod_collector, PodStat, SharedPodStats},
        top_ui,
        top_ui::TopViewState,
    },
    CLIENT_INSTANCE,
};

// ──────────────────────────────────────────────────────────────────────────
// Child process
// ──────────────────────────────────────────────────────────────────────────

fn pty_size(fd: i32) -> io::Result<(u16, u16)> {
    unsafe {
        let mut ws: winsize = std::mem::zeroed();
        if ioctl(fd, TIOCGWINSZ, &mut ws) == 0 {
            Ok((ws.ws_col, ws.ws_row))
        } else {
            Err(io::Error::last_os_error())
        }
    }
}

fn top_child_main(pty_path: &str) -> Result<(), Box<dyn std::error::Error>> {
    info!("in here, {}", pty_path);
    let pty = OpenOptions::new().read(true).write(true).open(pty_path)?;
    let fd = pty.as_raw_fd();

    let node_stats: SharedNodeStats = Default::default();
    let pod_stats: SharedPodStats = Default::default();
    if let Some(client) = CLIENT_INSTANCE.lock().ok().and_then(|c| c.clone()) {
        spawn_node_collector(node_stats.clone(), client.clone());
        spawn_pod_collector(pod_stats.clone(), client);
    }

    let (cols, rows) = pty_size(fd).unwrap_or((80, 24));
    let backend = CrosstermBackend::new(pty);
    let mut term = Terminal::new(backend)?;
    term.resize(Rect::new(0, 0, cols, rows))?;
    enable_raw_mode()?;

    let mut state = TopViewState::default();
    let tick = Duration::from_millis(200);
    let mut last = Instant::now();

    loop {
        if event::poll(Duration::from_millis(0))? {
            let ev = event::read()?;
            match ev {
                Event::Key(k) if k.code == KeyCode::Char('q') => break,
                Event::Key(k) if k.code == KeyCode::Down || k.code == KeyCode::Char('j') => {
                    state.scroll_down()
                }
                Event::Key(k) if k.code == KeyCode::Up || k.code == KeyCode::Char('k') => {
                    state.scroll_up()
                }
                Event::Key(k) if k.code == KeyCode::PageDown => state.scroll_page_down(),
                Event::Key(k) if k.code == KeyCode::PageUp => state.scroll_page_up(),
                Event::Key(k) if k.code == KeyCode::Tab => state.next_tab(),
                Event::Mouse(m) if m.kind == MouseEventKind::ScrollDown => state.scroll_down(),
                Event::Mouse(m) if m.kind == MouseEventKind::ScrollUp => state.scroll_up(),
                Event::Resize(_, _) => term.autoresize().ok().unwrap_or_default(),
                _ => {}
            }
            let ns = node_stats.lock().unwrap().clone();
            let ps = pod_stats.lock().unwrap().clone();
            term.draw(|f| top_ui::draw(f, f.area(), &mut state, &ns, &ps))?;
            last = Instant::now();
        }

        if last.elapsed() >= tick {
            let ns = node_stats.lock().unwrap().clone();
            let ps = pod_stats.lock().unwrap().clone();
            term.draw(|f| top_ui::draw(f, f.area(), &mut state, &ns, &ps))?;
            last = Instant::now();
        }
    }

    info!("here");
    queue!(
        term.backend_mut(),
        Clear(ClearType::All),
        cursor::MoveTo(0, 0)
    )?;
    let _ = term.show_cursor();
    disable_raw_mode()?;
    Ok(())
}

// ──────────────────────────────────────────────────────────────────────────
// Host-side launcher
// ──────────────────────────────────────────────────────────────────────────

static CHILD: Mutex<Option<Child>> = Mutex::new(None);

#[tracing::instrument]
pub fn start_topview(_lua: &Lua, pty_path: String) -> LuaResult<()> {
    top_child_main(&pty_path).ok();
    let mut slot = CHILD.lock().unwrap();
    if slot.is_some() {
        return Err(LuaError::RuntimeError("top view already running".into()));
    }

    let exe = std::env::current_exe().map_err(|e| LuaError::ExternalError(Arc::new(e)))?;
    let child = Command::new(exe)
        .arg("--top-child")
        .arg(&pty_path)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()
        .map_err(|e| LuaError::ExternalError(Arc::new(e)))?;

    *slot = Some(child);
    Ok(())
}

#[tracing::instrument]
pub fn stop_topview(_lua: &Lua, _: ()) -> LuaResult<()> {
    let mut slot = CHILD.lock().unwrap();
    if let Some(mut child) = slot.take() {
        let _ = child.kill();
        let _ = child.wait();
    }
    Ok(())
}
