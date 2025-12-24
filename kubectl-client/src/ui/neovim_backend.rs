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

/// Internal buffer for tracking cell state.
struct BufferState {
    width: u16,
    height: u16,
    cells: Vec<Cell>,
}

impl BufferState {
    fn new(width: u16, height: u16) -> Self {
        let size = (width as usize) * (height as usize);
        Self {
            width,
            height,
            cells: vec![Cell::default(); size],
        }
    }

    fn resize(&mut self, width: u16, height: u16) {
        self.width = width;
        self.height = height;
        let size = (width as usize) * (height as usize);
        self.cells.resize(size, Cell::default());
        self.cells.fill(Cell::default());
    }

    fn index(&self, x: u16, y: u16) -> usize {
        (y as usize) * (self.width as usize) + (x as usize)
    }

    fn set(&mut self, x: u16, y: u16, cell: &Cell) {
        if x < self.width && y < self.height {
            let idx = self.index(x, y);
            self.cells[idx] = cell.clone();
        }
    }

    fn clear(&mut self) {
        self.cells.fill(Cell::default());
    }

    /// Convert buffer state to lines and extmarks.
    /// Trims trailing empty lines to produce minimal output.
    /// Uses byte positions for extmarks (required by Neovim).
    fn to_render_frame(&self) -> RenderFrame {
        let mut lines = Vec::with_capacity(self.height as usize);
        let mut marks = Vec::new();

        for y in 0..self.height {
            let mut line = String::with_capacity(self.width as usize);
            let mut current_hl: Option<String> = None;
            let mut hl_start_byte: u16 = 0;
            let mut current_byte: u16 = 0;
            let mut row_marks: Vec<ExtmarkData> = Vec::new();

            for x in 0..self.width {
                let idx = self.index(x, y);
                let cell = &self.cells[idx];

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
                            row: y,
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
                    row: y,
                    start_col: hl_start_byte,
                    end_col: current_byte,
                    hl_group: Some(hl.clone()),
                });
            }

            // Trim trailing spaces and get actual byte length
            let trimmed = line.trim_end().to_string();
            let line_byte_len = trimmed.len() as u16;

            // Clamp extmarks to actual line byte length and filter empty spans
            for mut mark in row_marks {
                if mark.start_col >= line_byte_len {
                    continue; // Skip marks entirely beyond content
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
}

/// Convert ratatui's Buffer directly to a RenderFrame.
/// This bypasses our internal buffer and uses ratatui's complete buffer state.
pub fn buffer_to_render_frame(buffer: &ratatui::buffer::Buffer, area: ratatui::layout::Rect) -> RenderFrame {
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

        // Trim trailing spaces and get actual byte length
        let trimmed = line.trim_end().to_string();
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
fn cell_to_hl_group(cell: &Cell) -> Option<String> {
    let fg = cell.fg;
    let bg = cell.bg;
    let modifiers = cell.modifier;

    // Skip default/reset colors with no modifiers
    if fg == Color::Reset && bg == Color::Reset && modifiers.is_empty() {
        return None;
    }

    // Build highlight group name based on colors
    // Using a naming convention: Ratatui_<fg>_<bg>_<modifiers>
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
pub struct NeovimBackend {
    buffer: BufferState,
    cursor: Position,
    cursor_hidden: bool,
    /// Channel to send rendered frames.
    frame_tx: tokio::sync::mpsc::UnboundedSender<RenderFrame>,
    /// Flag to track if we're in a draw cycle.
    in_draw: bool,
}

impl NeovimBackend {
    /// Creates a new NeovimBackend with the given dimensions and output channel.
    pub fn new(
        width: u16,
        height: u16,
        frame_tx: tokio::sync::mpsc::UnboundedSender<RenderFrame>,
    ) -> Self {
        Self {
            buffer: BufferState::new(width, height),
            cursor: Position::new(0, 0),
            cursor_hidden: false,
            frame_tx,
            in_draw: false,
        }
    }

    /// Resize the internal buffer.
    pub fn resize(&mut self, width: u16, height: u16) {
        self.buffer.resize(width, height);
    }

    /// Send the current buffer state to Neovim.
    fn send_frame(&self) {
        let frame = self.buffer.to_render_frame();
        let _ = self.frame_tx.send(frame);
    }

    /// Send a pre-built frame directly to Neovim.
    pub fn send_frame_direct(&self, frame: RenderFrame) {
        let _ = self.frame_tx.send(frame);
    }
}

impl Backend for NeovimBackend {
    fn draw<'a, I>(&mut self, content: I) -> IoResult<()>
    where
        I: Iterator<Item = (u16, u16, &'a Cell)>,
    {
        // Clear buffer at start of draw cycle
        if !self.in_draw {
            self.buffer.clear();
            self.in_draw = true;
        }
        for (x, y, cell) in content {
            self.buffer.set(x, y, cell);
        }
        Ok(())
    }

    fn hide_cursor(&mut self) -> IoResult<()> {
        self.cursor_hidden = true;
        Ok(())
    }

    fn show_cursor(&mut self) -> IoResult<()> {
        self.cursor_hidden = false;
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
        self.buffer.clear();
        Ok(())
    }

    fn clear_region(&mut self, clear_type: ClearType) -> IoResult<()> {
        match clear_type {
            ClearType::All => self.buffer.clear(),
            ClearType::AfterCursor => {
                // Clear from cursor to end of screen
                let start_idx = self.buffer.index(self.cursor.x, self.cursor.y);
                for cell in self.buffer.cells[start_idx..].iter_mut() {
                    *cell = Cell::default();
                }
            }
            ClearType::BeforeCursor => {
                // Clear from start to cursor
                let end_idx = self.buffer.index(self.cursor.x, self.cursor.y);
                for cell in self.buffer.cells[..end_idx].iter_mut() {
                    *cell = Cell::default();
                }
            }
            ClearType::CurrentLine => {
                // Clear current line
                let y = self.cursor.y;
                for x in 0..self.buffer.width {
                    let idx = self.buffer.index(x, y);
                    self.buffer.cells[idx] = Cell::default();
                }
            }
            ClearType::UntilNewLine => {
                // Clear from cursor to end of line
                let y = self.cursor.y;
                for x in self.cursor.x..self.buffer.width {
                    let idx = self.buffer.index(x, y);
                    self.buffer.cells[idx] = Cell::default();
                }
            }
        }
        Ok(())
    }

    fn size(&self) -> IoResult<Size> {
        Ok(Size::new(self.buffer.width, self.buffer.height))
    }

    fn window_size(&mut self) -> IoResult<WindowSize> {
        Ok(WindowSize {
            columns_rows: Size::new(self.buffer.width, self.buffer.height),
            pixels: Size::new(0, 0), // Not applicable for buffer rendering
        })
    }

    fn flush(&mut self) -> IoResult<()> {
        // Don't send frame here - we send the full buffer after draw() completes
        // This avoids sending incomplete frames due to ratatui's diff optimization
        self.in_draw = false;
        Ok(())
    }

}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_buffer_state_basic() {
        let mut buffer = BufferState::new(10, 5);
        assert_eq!(buffer.cells.len(), 50);

        let mut cell = Cell::default();
        cell.set_char('X');
        buffer.set(5, 2, &cell);

        let idx = buffer.index(5, 2);
        assert_eq!(buffer.cells[idx].symbol(), "X");
    }

    #[test]
    fn test_color_to_name() {
        assert_eq!(color_to_name(Color::Red), "red");
        assert_eq!(color_to_name(Color::Rgb(255, 128, 64)), "xff8040");
        assert_eq!(color_to_name(Color::Indexed(42)), "i42");
    }

    #[test]
    fn test_render_frame_generation() {
        let (tx, _rx) = tokio::sync::mpsc::unbounded_channel();
        let mut backend = NeovimBackend::new(5, 2, tx);

        let mut cell = Cell::default();
        cell.set_char('H');
        backend.buffer.set(0, 0, &cell);

        cell.set_char('i');
        backend.buffer.set(1, 0, &cell);

        let frame = backend.buffer.to_render_frame();
        assert_eq!(frame.lines.len(), 2);
        assert_eq!(frame.lines[0], "Hi");
    }
}
