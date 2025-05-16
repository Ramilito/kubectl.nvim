use ratatui::{
    prelude::*,
    widgets::{Block, Borders, Paragraph},
};

use super::nodes::NodeStat;

/// Renders the “node usage” table full-screen in `f`.
pub fn draw_nodes(f: &mut Frame, stats: &[NodeStat]) {
    let size = f.area();

    // outer frame
    let frame = Block::default()
        .title(" Node usage (live) ")
        .borders(Borders::ALL)
        .border_style(
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        );
    f.render_widget(frame, size);

    let inner_w = size.width.saturating_sub(2);
    for (i, ns) in stats.iter().enumerate() {
        let row = Rect {
            x: size.x + 1,
            y: size.y + 1 + i as u16,
            width: inner_w,
            height: 1,
        };
        let text = format!("{}  CPU:{}  MEM:{}", ns.name, ns.cpu, ns.memory);
        f.render_widget(Paragraph::new(text), row);
    }
}
