//! Custom ratatui backend that renders to Neovim buffers via extmarks.
//!
//! Instead of producing ANSI escape codes, this backend produces structured
//! data (lines + highlight information) that can be applied to a native
//! Neovim buffer using `nvim_buf_set_lines` and `nvim_buf_set_extmark`.

use ratatui::{
    backend::{Backend, ClearType, WindowSize},
    buffer::Cell,
    layout::{Position, Size},
    style::{Color, Modifier},
};
use serde::Serialize;
use std::io::Result as IoResult;

use super::colors;

/// Highlight data for a single cell or range.
#[derive(Debug, Clone, Serialize)]
pub struct ExtmarkData {
    pub row: u16,
    pub start_col: u16,
    pub end_col: u16,
    pub hl_group: Option<String>,
}

/// Complete render output for a frame.
#[derive(Debug, Clone, Serialize, Default)]
pub struct RenderFrame {
    /// Lines of text content.
    pub lines: Vec<String>,
    /// Highlight/extmark data.
    pub marks: Vec<ExtmarkData>,
}


/// Convert ratatui's Buffer directly to a RenderFrame.
/// This bypasses our internal buffer and uses ratatui's complete buffer state.
pub fn buffer_to_render_frame(
    buffer: &ratatui::buffer::Buffer,
    area: ratatui::layout::Rect,
) -> RenderFrame {
    let mut lines = Vec::with_capacity(area.height as usize);
    let mut marks = Vec::new();

    for y in area.y..area.y + area.height {
        let mut line = String::with_capacity(area.width as usize);
        let mut current_hl: Option<String> = None;
        let mut hl_start_byte: u16 = 0;
        let mut current_byte: u16 = 0;
        let mut row_marks: Vec<ExtmarkData> = Vec::new();

        for x in area.x..area.x + area.width {
            let default_cell = Cell::default();
            let cell = buffer.cell((x, y)).unwrap_or(&default_cell);

            // Build line content
            let symbol = if cell.symbol().is_empty() {
                " "
            } else {
                cell.symbol()
            };
            let symbol_bytes = symbol.len() as u16;

            // Track highlight spans using byte positions
            let cell_hl = cell_to_hl_group(cell);

            if cell_hl != current_hl {
                // Close previous span
                if let Some(ref hl) = current_hl {
                    row_marks.push(ExtmarkData {
                        row: y - area.y,
                        start_col: hl_start_byte,
                        end_col: current_byte,
                        hl_group: Some(hl.clone()),
                    });
                }
                // Start new span
                current_hl = cell_hl;
                hl_start_byte = current_byte;
            }

            line.push_str(symbol);
            current_byte += symbol_bytes;
        }

        // Close final span for this line
        if let Some(ref hl) = current_hl {
            row_marks.push(ExtmarkData {
                row: y - area.y,
                start_col: hl_start_byte,
                end_col: current_byte,
                hl_group: Some(hl.clone()),
            });
        }

        // Only trim trailing spaces that have no styling
        // Find the last styled position (extmark end)
        let last_styled_pos = row_marks.iter().map(|m| m.end_col).max().unwrap_or(0);

        // Trim trailing unstyled spaces only
        let trimmed = if last_styled_pos as usize >= line.len() {
            line.clone()
        } else {
            let keep = &line[..last_styled_pos as usize];
            let rest = &line[last_styled_pos as usize..];
            format!("{}{}", keep, rest.trim_end())
        };
        let line_byte_len = trimmed.len() as u16;

        // Clamp extmarks to actual line byte length and filter empty spans
        for mut mark in row_marks {
            if mark.start_col >= line_byte_len {
                continue;
            }
            mark.end_col = mark.end_col.min(line_byte_len);
            if mark.start_col < mark.end_col {
                marks.push(mark);
            }
        }

        lines.push(trimmed);
    }

    // Trim trailing empty lines
    while lines.last().map(|s| s.is_empty()).unwrap_or(false) {
        lines.pop();
    }

    // Filter marks to only include those within content bounds
    let line_count = lines.len() as u16;
    marks.retain(|m| m.row < line_count);

    RenderFrame { lines, marks }
}

/// Convert ratatui Cell style to Neovim highlight group name.
///
/// Maps common Tailwind colors to native Kubectl* highlight groups to avoid
/// Lua-side color parsing. Falls back to Ratatui_* naming for other colors.
fn cell_to_hl_group(cell: &Cell) -> Option<String> {
    let fg = cell.fg;
    let bg = cell.bg;
    let modifiers = cell.modifier;

    // Skip default/reset colors with no modifiers
    if fg == Color::Reset && bg == Color::Reset && modifiers.is_empty() {
        return None;
    }

    // Map Kubectl colors to native highlight groups.
    let base_hl = match fg {
        c if c == colors::INFO => Some("KubectlInfo"),
        c if c == colors::WARNING => Some("KubectlWarning"),
        c if c == colors::ERROR => Some("KubectlError"),
        c if c == colors::DEBUG => Some("KubectlDebug"),
        c if c == colors::HEADER => Some("KubectlHeader"),
        c if c == colors::SUCCESS => Some("KubectlSuccess"),
        c if c == colors::GRAY => Some("KubectlGray"),
        c if c == colors::PENDING => Some("KubectlPending"),
        _ => None,
    };

    // If we found a native mapping, use it (with modifiers suffix if needed)
    if let Some(hl) = base_hl {
        let mut name = hl.to_string();
        if modifiers.contains(Modifier::BOLD) {
            name.push_str("Bold");
        }
        return Some(name);
    }

    // Fall back to Ratatui_* naming convention for unmapped colors
    let fg_name = color_to_name(fg);
    let bg_name = color_to_name(bg);

    let mut name = format!("Ratatui_{}", fg_name);
    if bg != Color::Reset {
        name.push_str(&format!("_on_{}", bg_name));
    }
    if modifiers.contains(Modifier::BOLD) {
        name.push_str("_bold");
    }
    if modifiers.contains(Modifier::ITALIC) {
        name.push_str("_italic");
    }
    if modifiers.contains(Modifier::UNDERLINED) {
        name.push_str("_underline");
    }

    Some(name)
}

/// Convert ratatui Color to a short name for highlight groups.
fn color_to_name(color: Color) -> String {
    match color {
        Color::Reset => "reset".to_string(),
        Color::Black => "black".to_string(),
        Color::Red => "red".to_string(),
        Color::Green => "green".to_string(),
        Color::Yellow => "yellow".to_string(),
        Color::Blue => "blue".to_string(),
        Color::Magenta => "magenta".to_string(),
        Color::Cyan => "cyan".to_string(),
        Color::Gray => "gray".to_string(),
        Color::DarkGray => "darkgray".to_string(),
        Color::LightRed => "lightred".to_string(),
        Color::LightGreen => "lightgreen".to_string(),
        Color::LightYellow => "lightyellow".to_string(),
        Color::LightBlue => "lightblue".to_string(),
        Color::LightMagenta => "lightmagenta".to_string(),
        Color::LightCyan => "lightcyan".to_string(),
        Color::White => "white".to_string(),
        Color::Rgb(r, g, b) => format!("x{:02x}{:02x}{:02x}", r, g, b),
        Color::Indexed(i) => format!("i{}", i),
    }
}

/// Backend that renders to Neovim buffers instead of a terminal.
///
/// This backend doesn't store cell data - ratatui's Terminal maintains its own
/// buffer which we read via `buffer_to_render_frame` after each draw cycle.
pub struct NeovimBackend {
    width: u16,
    height: u16,
    cursor: Position,
    /// Channel to send rendered frames.
    frame_tx: tokio::sync::mpsc::UnboundedSender<RenderFrame>,
}

impl NeovimBackend {
    /// Creates a new NeovimBackend with the given dimensions and output channel.
    pub fn new(
        width: u16,
        height: u16,
        frame_tx: tokio::sync::mpsc::UnboundedSender<RenderFrame>,
    ) -> Self {
        Self {
            width,
            height,
            cursor: Position::new(0, 0),
            frame_tx,
        }
    }

    /// Resize the buffer dimensions.
    pub fn resize(&mut self, width: u16, height: u16) {
        self.width = width;
        self.height = height;
    }

    /// Send a pre-built frame directly to Neovim.
    pub fn send_frame_direct(&self, frame: RenderFrame) {
        let _ = self.frame_tx.send(frame);
    }
}

impl Backend for NeovimBackend {
    fn draw<'a, I>(&mut self, _content: I) -> IoResult<()>
    where
        I: Iterator<Item = (u16, u16, &'a Cell)>,
    {
        // No-op: ratatui's Terminal maintains its own buffer which we read
        // via buffer_to_render_frame() after draw() completes.
        Ok(())
    }

    fn hide_cursor(&mut self) -> IoResult<()> {
        Ok(())
    }

    fn show_cursor(&mut self) -> IoResult<()> {
        Ok(())
    }

    fn get_cursor_position(&mut self) -> IoResult<Position> {
        Ok(self.cursor)
    }

    fn set_cursor_position<P: Into<Position>>(&mut self, position: P) -> IoResult<()> {
        self.cursor = position.into();
        Ok(())
    }

    fn clear(&mut self) -> IoResult<()> {
        // No-op: Terminal manages its own buffer
        Ok(())
    }

    fn clear_region(&mut self, _clear_type: ClearType) -> IoResult<()> {
        // No-op: Terminal manages its own buffer
        Ok(())
    }

    fn size(&self) -> IoResult<Size> {
        Ok(Size::new(self.width, self.height))
    }

    fn window_size(&mut self) -> IoResult<WindowSize> {
        Ok(WindowSize {
            columns_rows: Size::new(self.width, self.height),
            pixels: Size::new(0, 0),
        })
    }

    fn flush(&mut self) -> IoResult<()> {
        // No-op: we send frames via send_frame_direct() after draw completes
        Ok(())
    }
}
