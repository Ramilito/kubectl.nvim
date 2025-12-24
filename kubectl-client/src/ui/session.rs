//! UI Session management and Lua FFI bindings.
//!
//! Handles the communication channel between Neovim and the Rust UI,
//! terminal setup, and the main UI event loop.

use crate::RUNTIME;
use crossterm::terminal::{disable_raw_mode, enable_raw_mode};
use mlua::{prelude::*, UserData, UserDataMethods};
use ratatui::{
    backend::CrosstermBackend, layout::Rect, Frame, Terminal, TerminalOptions, Viewport,
};
use std::{
    io::{Result as IoResult, Write},
    sync::{
        atomic::{AtomicBool, AtomicU16, Ordering},
        Arc, Mutex,
    },
};
use tokio::{
    sync::mpsc,
    time::{self, Duration},
};

use crate::ui::{
    events::{bytes_to_event, is_quit_event},
    views::{make_view, View},
};

/// Writer that sends terminal output to Neovim via channel.
struct NvWriter(mpsc::UnboundedSender<Vec<u8>>);

impl Write for NvWriter {
    fn write(&mut self, buf: &[u8]) -> IoResult<usize> {
        let _ = self.0.send(buf.to_vec());
        Ok(buf.len())
    }

    fn flush(&mut self) -> IoResult<()> {
        Ok(())
    }
}

/// UI session that bridges Neovim and the Rust terminal UI.
///
/// Exposed to Lua for managing the dashboard lifecycle.
pub struct Session {
    /// Channel for sending input from Neovim to UI.
    tx_in: mpsc::UnboundedSender<Vec<u8>>,
    /// Channel for receiving output from UI to Neovim.
    rx_out: Mutex<mpsc::UnboundedReceiver<Vec<u8>>>,
    /// Flag indicating if the session is still active.
    open: Arc<AtomicBool>,
    /// Current terminal width.
    cols: Arc<AtomicU16>,
    /// Current terminal height.
    rows: Arc<AtomicU16>,
}

impl Session {
    /// Creates a new UI session with the specified view.
    ///
    /// # Arguments
    /// * `view_name` - Name of the view to display ("top" or "overview")
    pub fn new(view_name: String) -> LuaResult<Self> {
        // Shared flags and dimensions
        let open = Arc::new(AtomicBool::new(true));
        let cols = Arc::new(AtomicU16::new(80));
        let rows = Arc::new(AtomicU16::new(24));

        // Communication channels
        let (tx_in, rx_in) = mpsc::unbounded_channel::<Vec<u8>>();
        let (tx_out, rx_out) = mpsc::unbounded_channel::<Vec<u8>>();

        // Spawn UI task on the Tokio runtime
        let rt = RUNTIME.get_or_init(|| tokio::runtime::Runtime::new().unwrap());
        let ui_open = open.clone();
        let ui_cols = cols.clone();
        let ui_rows = rows.clone();
        rt.spawn(run_ui(view_name, rx_in, tx_out, ui_open, ui_cols, ui_rows));

        Ok(Self {
            tx_in,
            rx_out: Mutex::new(rx_out),
            open,
            cols,
            rows,
        })
    }

    /// Reads a chunk of output from the UI (non-blocking).
    fn read_chunk(&self) -> Option<String> {
        self.rx_out
            .lock()
            .unwrap()
            .try_recv()
            .ok()
            .map(|v| String::from_utf8_lossy(&v).into_owned())
    }

    /// Sends input to the UI.
    fn write(&self, s: &str) {
        let _ = self.tx_in.send(s.as_bytes().to_vec());
    }

    /// Returns whether the session is still open.
    fn is_open(&self) -> bool {
        self.open.load(Ordering::Acquire)
    }

    /// Updates the terminal dimensions.
    fn resize(&self, w: u16, h: u16) {
        self.cols.store(w, Ordering::Release);
        self.rows.store(h, Ordering::Release);
    }
}

impl UserData for Session {
    fn add_methods<M: UserDataMethods<Self>>(m: &mut M) {
        m.add_method("read_chunk", |_, this, ()| Ok(this.read_chunk()));
        m.add_method("write", |_, this, s: String| {
            this.write(&s);
            Ok(())
        });
        m.add_method("open", |_, this, ()| Ok(this.is_open()));
        m.add_method("resize", |_, this, (w, h): (u16, u16)| {
            this.resize(w, h);
            Ok(())
        });
    }
}

/// Main UI event loop.
///
/// Handles input events, periodic redraws, and terminal resizing.
async fn run_ui(
    view_name: String,
    mut rx_in: mpsc::UnboundedReceiver<Vec<u8>>,
    tx_out: mpsc::UnboundedSender<Vec<u8>>,
    open: Arc<AtomicBool>,
    cols: Arc<AtomicU16>,
    rows: Arc<AtomicU16>,
) {
    enable_raw_mode().ok();

    let backend = CrosstermBackend::new(NvWriter(tx_out));
    let initial_w = cols.load(Ordering::Acquire);
    let initial_h = rows.load(Ordering::Acquire);

    let mut term = Terminal::with_options(
        backend,
        TerminalOptions {
            viewport: Viewport::Fixed(Rect::new(0, 0, initial_w, initial_h)),
        },
    )
    .expect("terminal");

    let mut view = make_view(&view_name);
    let mut tick = time::interval(Duration::from_millis(2_000));

    loop {
        tokio::select! {
            // Input from Neovim
            Some(bytes) = rx_in.recv() => {
                if let Some(ev) = bytes_to_event(&bytes) {
                    if is_quit_event(&ev) {
                        open.store(false, Ordering::Release);
                        break;
                    }
                    if view.on_event(&ev) {
                        draw(&mut term, &mut *view);
                    }
                }
            }

            // Periodic refresh for live data
            _ = tick.tick() => {
                draw(&mut term, &mut *view);
            }

            // Handle resize updates
            else => {
                let w = cols.load(Ordering::Acquire);
                let h = rows.load(Ordering::Acquire);
                term.resize(Rect::new(0, 0, w, h)).ok();
            }
        }
    }

    disable_raw_mode().ok();
}

/// Renders the view to the terminal.
fn draw(term: &mut Terminal<CrosstermBackend<NvWriter>>, view: &mut dyn View) {
    let _ = term.draw(|f: &mut Frame| {
        let area = f.area();
        view.draw(f, area);
    });
}
