use ratatui::{
    prelude::*,
    style::palette::tailwind,
    widgets::{Block, Borders, Gauge, Padding},
};
use super::nodes::NodeStat;

pub fn draw(f: &mut Frame, stats: &[NodeStat], area: Rect) {
    // outer frame --------------------------------------------------
    let frame = Block::default()
        .title(" Node usage (live) ")
        .borders(Borders::ALL)
        .border_style(
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        );
    f.render_widget(frame, area);

    let inner_x = area.x + 1;
    let inner_w = area.width.saturating_sub(2);
    let mut y   = area.y + 1;

    for ns in stats {
        // block height: 1 (title) + 2 + 2 = 5
        let node_rect = Rect { x: inner_x, y, width: inner_w, height: 5 };
        let rows = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(1), // title
                Constraint::Length(2), // CPU gauge
                Constraint::Length(2), // MEM gauge
            ])
            .split(node_rect);

        // --- title -------------------------------------------------
        let title = Line::from(ns.name.clone()).centered();
        let title_block = Block::default()
            .borders(Borders::NONE)
            .title(title)
            .fg(tailwind::BLUE.c200);
        f.render_widget(title_block, rows[0]);

        // helper for both gauges
        let make_gauge = |label: &str, pct: f64, color: Color| {
            Gauge::default()
                .block(
                    Block::default()
                        .borders(Borders::NONE)
                        .padding(Padding::horizontal(1))
                        .title(format!("{label}:")),
                )
                .gauge_style(
                    Style::default()
                        .fg(color)
                        .bg(tailwind::GRAY.c800),
                )
                .use_unicode(true)
                .percent(pct.clamp(0.0, 100.0).round() as u16)
        };

        // --- CPU gauge --------------------------------------------
        let cpu_gauge = make_gauge("CPU", ns.cpu_pct, tailwind::GREEN.c500);
        f.render_widget(cpu_gauge, rows[1]);

        // --- Memory gauge -----------------------------------------
        let mem_gauge = make_gauge("MEM", ns.mem_pct, tailwind::EMERALD.c400);
        f.render_widget(mem_gauge, rows[2]);

        y += 6; // 5 lines just drawn + 1 blank row spacing
    }
}
