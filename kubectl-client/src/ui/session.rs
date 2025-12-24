//! UI Session management and Lua FFI bindings.
//!
//! Handles the communication channel between Neovim and the Rust UI
//! and the main UI event loop.
//!
//! `BufferSession` provides native Neovim buffer rendering via NeovimBackend,
//! outputting structured data (lines + extmarks) that can be applied to a
//! regular Neovim buffer using `nvim_buf_set_lines` and `nvim_buf_set_extmark`.

use crate::RUNTIME;
use mlua::{prelude::*, UserData, UserDataMethods};
use ratatui::{
    backend::Backend,
    layout::Rect,
    Frame, Terminal, TerminalOptions, Viewport,
};
use std::sync::{
    atomic::{AtomicBool, AtomicU16, Ordering},
    Arc, Mutex,
};
use tokio::{
    sync::mpsc,
    time::{self, Duration},
};

use crate::ui::{
    events::{is_quit_event, parse_message, ParsedMessage},
    neovim_backend::{NeovimBackend, RenderFrame},
    views::{make_view, View},
};

/// UI session that renders to a native Neovim buffer.
///
/// Outputs structured data (lines + extmarks) that can be applied to a
/// regular Neovim buffer, enabling native vim motions, search, yank, etc.
pub struct BufferSession {
    /// Channel for sending input from Neovim to UI.
    tx_in: mpsc::UnboundedSender<Vec<u8>>,
    /// Channel for receiving rendered frames from UI to Neovim.
    rx_out: Mutex<mpsc::UnboundedReceiver<RenderFrame>>,
    /// Flag indicating if the session is still active.
    open: Arc<AtomicBool>,
    /// Current buffer width.
    cols: Arc<AtomicU16>,
    /// Current buffer height.
    rows: Arc<AtomicU16>,
}

impl BufferSession {
    /// Creates a new buffer-based UI session with the specified view.
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
        let (tx_out, rx_out) = mpsc::unbounded_channel::<RenderFrame>();

        // Spawn UI task on the Tokio runtime
        let rt = RUNTIME.get_or_init(|| tokio::runtime::Runtime::new().unwrap());
        let ui_open = open.clone();
        let ui_cols = cols.clone();
        let ui_rows = rows.clone();
        rt.spawn(run_buffer_ui(
            view_name, rx_in, tx_out, ui_open, ui_cols, ui_rows,
        ));

        Ok(Self {
            tx_in,
            rx_out: Mutex::new(rx_out),
            open,
            cols,
            rows,
        })
    }

    /// Reads a rendered frame from the UI (non-blocking).
    fn read_frame(&self) -> Option<RenderFrame> {
        self.rx_out.lock().unwrap().try_recv().ok()
    }

    /// Sends input to the UI.
    fn write(&self, s: &str) {
        let _ = self.tx_in.send(s.as_bytes().to_vec());
    }

    /// Returns whether the session is still open.
    fn is_open(&self) -> bool {
        self.open.load(Ordering::Acquire)
    }

    /// Updates the buffer dimensions.
    fn resize(&self, w: u16, h: u16) {
        self.cols.store(w, Ordering::Release);
        self.rows.store(h, Ordering::Release);
    }

    /// Closes the session.
    fn close(&self) {
        self.open.store(false, Ordering::Release);
    }
}

impl UserData for BufferSession {
    fn add_methods<M: UserDataMethods<Self>>(m: &mut M) {
        m.add_method("read_frame", |lua, this, ()| {
            match this.read_frame() {
                Some(frame) => {
                    // Convert RenderFrame to Lua table
                    let tbl = lua.create_table()?;

                    // Lines array
                    let lines = lua.create_table()?;
                    for (i, line) in frame.lines.iter().enumerate() {
                        lines.set(i + 1, line.as_str())?;
                    }
                    tbl.set("lines", lines)?;

                    // Marks array
                    let marks = lua.create_table()?;
                    for (i, mark) in frame.marks.iter().enumerate() {
                        let mark_tbl = lua.create_table()?;
                        mark_tbl.set("row", mark.row)?;
                        mark_tbl.set("start_col", mark.start_col)?;
                        mark_tbl.set("end_col", mark.end_col)?;
                        if let Some(ref hl) = mark.hl_group {
                            mark_tbl.set("hl_group", hl.as_str())?;
                        }
                        marks.set(i + 1, mark_tbl)?;
                    }
                    tbl.set("marks", marks)?;

                    Ok(Some(tbl))
                }
                None => Ok(None),
            }
        });

        m.add_method("write", |_, this, s: String| {
            this.write(&s);
            Ok(())
        });

        m.add_method("open", |_, this, ()| Ok(this.is_open()));

        m.add_method("resize", |_, this, (w, h): (u16, u16)| {
            this.resize(w, h);
            Ok(())
        });

        m.add_method("close", |_, this, ()| {
            this.close();
            Ok(())
        });

        // Sync cursor position from Neovim to ratatui
        m.add_method("set_cursor_line", |_, this, line: u16| {
            // Send cursor line as a special message with simple prefix
            // Using 0x00 as prefix since it won't appear in normal input
            let msg = format!("\x00CURSOR:{}\x00", line);
            let _ = this.tx_in.send(msg.into_bytes());
            Ok(())
        });
    }
}

/// Main UI event loop for buffer-based rendering.
async fn run_buffer_ui(
    view_name: String,
    mut rx_in: mpsc::UnboundedReceiver<Vec<u8>>,
    tx_out: mpsc::UnboundedSender<RenderFrame>,
    open: Arc<AtomicBool>,
    cols: Arc<AtomicU16>,
    rows: Arc<AtomicU16>,
) {
    // Wait a moment for Lua to send the correct dimensions
    time::sleep(Duration::from_millis(50)).await;

    let initial_w = cols.load(Ordering::Acquire);
    let base_h = rows.load(Ordering::Acquire);

    // Create view first so we can query content height
    let mut view = make_view(&view_name);

    // Use content height if available, otherwise use base height from Lua
    let initial_h = view.content_height().unwrap_or(base_h).max(base_h);

    let backend = NeovimBackend::new(initial_w, initial_h, tx_out.clone());

    let mut term = Terminal::with_options(
        backend,
        TerminalOptions {
            viewport: Viewport::Fixed(Rect::new(0, 0, initial_w, initial_h)),
        },
    )
    .expect("terminal");

    term.clear().ok();

    let mut tick = time::interval(Duration::from_millis(2_000));

    // Initial draw (after receiving dimensions)
    draw_buffer(&mut term, &mut *view);

    loop {
        tokio::select! {
            // Input from Neovim
            msg = rx_in.recv() => {
                match msg {
                    Some(bytes) => {
                        let needs_redraw = match parse_message(&bytes) {
                            Some(ParsedMessage::Event(ev)) => {
                                if is_quit_event(&ev) {
                                    open.store(false, Ordering::Release);
                                    break;
                                }
                                view.on_event(&ev)
                            }
                            Some(ParsedMessage::CursorLine(line)) => {
                                view.set_cursor_line(line)
                            }
                            None => false,
                        };

                        if needs_redraw {
                            // Get width from Lua, but use content height if available
                            let new_w = cols.load(Ordering::Acquire);
                            let base_h = rows.load(Ordering::Acquire);
                            let new_h = view.content_height().unwrap_or(base_h).max(base_h);
                            let current_size = term.backend().size().unwrap_or_default();

                            if new_w != current_size.width || new_h != current_size.height {
                                term.backend_mut().resize(new_w, new_h);
                                let _ = term.resize(Rect::new(0, 0, new_w, new_h));
                            }

                            draw_buffer(&mut term, &mut *view);
                        }
                    }
                    // Channel closed
                    None => {
                        open.store(false, Ordering::Release);
                        break;
                    }
                }
            }

            // Periodic refresh
            _ = tick.tick() => {
                if !open.load(Ordering::Acquire) {
                    break;
                }

                // Get width from Lua, but use content height if available
                let new_w = cols.load(Ordering::Acquire);
                let base_h = rows.load(Ordering::Acquire);
                let new_h = view.content_height().unwrap_or(base_h).max(base_h);
                let current_size = term.backend().size().unwrap_or_default();

                if new_w != current_size.width || new_h != current_size.height {
                    term.backend_mut().resize(new_w, new_h);
                    let _ = term.resize(Rect::new(0, 0, new_w, new_h));
                }

                draw_buffer(&mut term, &mut *view);
            }
        }
    }
}

/// Renders the view to the buffer backend.
fn draw_buffer(term: &mut Terminal<NeovimBackend>, view: &mut dyn View) {
    // Draw to terminal and get the completed frame with the buffer
    if let Ok(completed) = term.draw(|f: &mut Frame| {
        view.draw(f, f.area());
    }) {
        // Convert the completed buffer to our frame format and send
        let frame = crate::ui::neovim_backend::buffer_to_render_frame(
            &completed.buffer,
            completed.area,
        );
        term.backend_mut().send_frame_direct(frame);
    }
}
