use ratatui::{
    prelude::*,
    widgets::{Block, Borders, Paragraph},
};

use super::nodes::NodeStat;

pub fn draw(f: &mut Frame, stats: &[NodeStat], area: Rect) {
    let frame = Block::default()
        .title(" Node usage (live) ")
        .borders(Borders::ALL)
        .border_style(
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        );
    f.render_widget(frame, area);

    let inner_w = area.width.saturating_sub(2);
    for (i, ns) in stats.iter().enumerate() {
        let row = Rect {
            x: area.x + 1,
            y: area.y + 1 + i as u16,
            width: inner_w,
            height: 1,
        };
        let text = format!("{}  CPU:{}  MEM:{}", ns.name, ns.cpu_pct, ns.mem_pct);
        f.render_widget(Paragraph::new(text), row);
    }
}
