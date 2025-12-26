//! Column header component for table-like displays.

use ratatui::{
    prelude::*,
    style::{Color, Modifier, Style},
    widgets::Paragraph,
    Frame,
};

use crate::ui::layout::column_split;

/// KubectlGray color (must match lua/kubectl/actions/highlight.lua).
const GRAY: Color = Color::Rgb(0x66, 0x66, 0x66);

/// Draws a header row with NAME, CPU, and MEM columns.
///
/// Uses the standard column_split layout for consistency with data rows.
pub fn draw_header(f: &mut Frame, area: Rect, name_width: u16) {
    let [name_col, cpu_col, _gap, mem_col] = column_split(area, name_width);

    let style = Style::default().fg(GRAY).add_modifier(Modifier::BOLD);

    f.render_widget(Paragraph::new("NAME").style(style), name_col);
    f.render_widget(
        Paragraph::new("CPU")
            .alignment(Alignment::Center)
            .style(style),
        cpu_col,
    );
    f.render_widget(
        Paragraph::new("MEM")
            .alignment(Alignment::Center)
            .style(style),
        mem_col,
    );
}
