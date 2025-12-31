//! UI Session management and Lua FFI bindings.
//!
//! Handles the communication channel between Neovim and the Rust UI
//! and the main UI event loop.
//!
//! `BufferSession` provides native Neovim buffer rendering via NeovimBackend,
//! outputting structured data (lines + extmarks) that can be applied to a
//! regular Neovim buffer using `nvim_buf_set_lines` and `nvim_buf_set_extmark`.

use crate::streaming::BidirectionalSession;
use crate::{metrics::take_metrics_dirty, RUNTIME};
use mlua::{prelude::*, UserData, UserDataMethods};
use ratatui::{backend::Backend, layout::Rect, Frame, Terminal, TerminalOptions, Viewport};
use std::sync::atomic::{AtomicU16, Ordering};
use std::sync::Arc;
use tokio::time::{self, Duration};

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
    /// Bidirectional communication channel.
    session: BidirectionalSession<Vec<u8>, RenderFrame>,
    /// Current buffer width.
    cols: Arc<AtomicU16>,
    /// Current buffer height.
    rows: Arc<AtomicU16>,
}

impl BufferSession {
    /// Creates a new buffer-based UI session with the specified view.
    ///
    /// # Arguments
    /// * `view_name` - Name of the view to display ("top", "overview", or "drift")
    /// * `view_args` - Optional arguments for the view (e.g., path for drift view)
    pub fn new(view_name: String, view_args: Option<String>) -> LuaResult<Self> {
        let cols = Arc::new(AtomicU16::new(80));
        let rows = Arc::new(AtomicU16::new(24));

        let mut session = BidirectionalSession::<Vec<u8>, RenderFrame>::new();

        // Take the input receiver before spawning the task
        let input_receiver = session
            .take_input_receiver()
            .ok_or_else(|| LuaError::runtime("Failed to take input receiver"))?;

        // Spawn UI task on the Tokio runtime
        let rt = RUNTIME.get_or_init(|| tokio::runtime::Runtime::new().unwrap());
        let task_handle = session.task_handle();
        let output_sender = session.output_sender();
        let ui_cols = cols.clone();
        let ui_rows = rows.clone();

        rt.spawn(run_buffer_ui(
            view_name,
            view_args,
            input_receiver,
            output_sender,
            task_handle,
            ui_cols,
            ui_rows,
        ));

        Ok(Self {
            session,
            cols,
            rows,
        })
    }

    /// Reads a rendered frame from the UI (non-blocking).
    fn read_frame(&self) -> Option<RenderFrame> {
        self.session.try_recv_output().ok().flatten()
    }

    /// Sends input to the UI.
    fn write(&self, s: &str) {
        let _ = self.session.send_input(s.as_bytes().to_vec());
    }

    /// Returns whether the session is still open.
    fn is_open(&self) -> bool {
        self.session.is_open()
    }

    /// Updates the buffer dimensions.
    fn resize(&self, w: u16, h: u16) {
        self.cols.store(w, Ordering::Release);
        self.rows.store(h, Ordering::Release);
    }

    /// Closes the session.
    fn close(&self) {
        self.session.close();
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
            let _ = this.session.send_input(msg.into_bytes());
            Ok(())
        });
    }
}

/// Resizes terminal if dimensions changed, returns true if resized.
fn maybe_resize(
    term: &mut Terminal<NeovimBackend>,
    view: &dyn View,
    cols: &AtomicU16,
    rows: &AtomicU16,
) -> bool {
    let new_w = cols.load(Ordering::Acquire);
    let base_h = rows.load(Ordering::Acquire);
    let new_h = view.content_height().unwrap_or(base_h).max(base_h);
    let current = term.backend().size().unwrap_or_default();

    if new_w != current.width || new_h != current.height {
        term.backend_mut().resize(new_w, new_h);
        let _ = term.resize(Rect::new(0, 0, new_w, new_h));
        true
    } else {
        false
    }
}

/// Main UI event loop for buffer-based rendering.
async fn run_buffer_ui(
    view_name: String,
    view_args: Option<String>,
    mut input_receiver: tokio::sync::mpsc::UnboundedReceiver<Vec<u8>>,
    output_sender: tokio::sync::mpsc::UnboundedSender<RenderFrame>,
    task_handle: crate::streaming::TaskHandle,
    cols: Arc<AtomicU16>,
    rows: Arc<AtomicU16>,
) {
    // Task guard ensures session is marked inactive when this task exits
    let _guard = task_handle.guard();

    time::sleep(Duration::from_millis(50)).await;

    let mut view = make_view(&view_name, view_args.as_deref());
    let initial_w = cols.load(Ordering::Acquire);
    let initial_h = view
        .content_height()
        .unwrap_or_else(|| rows.load(Ordering::Acquire))
        .max(rows.load(Ordering::Acquire));

    let mut term = Terminal::with_options(
        NeovimBackend::new(initial_w, initial_h, output_sender.clone()),
        TerminalOptions {
            viewport: Viewport::Fixed(Rect::new(0, 0, initial_w, initial_h)),
        },
    )
    .expect("terminal");

    term.clear().ok();
    draw_buffer(&mut term, &mut *view);

    let mut tick = time::interval(Duration::from_millis(2_000));

    loop {
        tokio::select! {
            msg = input_receiver.recv() => {
                match msg {
                    Some(bytes) => {
                        let needs_redraw = match parse_message(&bytes) {
                            Some(ParsedMessage::Event(ev)) => {
                                if is_quit_event(&ev) {
                                    break;
                                }
                                view.on_event(&ev)
                            }
                            Some(ParsedMessage::CursorLine(line)) => view.set_cursor_line(line),
                            Some(ParsedMessage::SetPath(path)) => view.set_path(path),
                            None => false,
                        };

                        if needs_redraw {
                            maybe_resize(&mut term, &*view, &cols, &rows);
                            draw_buffer(&mut term, &mut *view);
                        }
                    }
                    None => {
                        break;
                    }
                }
            }

            _ = tick.tick() => {
                if !task_handle.is_active() || !take_metrics_dirty() {
                    continue;
                }
                // Signal view that metrics have been updated
                view.on_metrics_update();
                maybe_resize(&mut term, &*view, &cols, &rows);
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
