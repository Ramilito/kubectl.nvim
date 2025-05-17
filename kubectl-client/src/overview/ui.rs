use super::nodes::NodeStat;
use ratatui::{
    prelude::*,
    style::palette::tailwind,
    widgets::{Block, Borders, Gauge, Padding},
};

pub fn draw(f: &mut Frame, stats: &[NodeStat], area: Rect) {
    // outer frame --------------------------------------------------
    let frame = Block::default()
        .title(" Overview (live) ")
        .borders(Borders::ALL)
        .border_style(
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        );
    f.render_widget(frame, area);

    let inner_x = area.x + 1;
    let inner_w = area.width.saturating_sub(2) / 2;
    let mut y = area.y + 1;

    for ns in stats {
        // block height: 1 (title) + 2 + 2 = 5
        let node_rect = Rect {
            x: inner_x,
            y,
            width: inner_w,
            height: 4,
        };
        let rows = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(1), // title
                Constraint::Length(1), // CPU gauge
                Constraint::Length(1), // MEM gauge
            ])
            .split(node_rect);

        // --- title -------------------------------------------------
        let title = Line::from(ns.name.clone()).centered();
        let title_block = Block::default()
            .borders(Borders::NONE)
            .title(title)
            .fg(tailwind::BLUE.c400);
        f.render_widget(title_block, rows[0]);

        // helper for both gauges
        let make_gauge = |label: &str, pct: u16, color: Color| {
            Gauge::default()
                .block(
                    Block::default()
                        .borders(Borders::NONE)
                        .padding(Padding::horizontal(1)),
                )
                .gauge_style(Style::default().fg(color).bg(tailwind::GRAY.c800))
                .label(format!("{}: {}", label, pct))
                .use_unicode(true)
                .percent(pct)
        };

        // --- CPU gauge --------------------------------------------
        let cpu_gauge = make_gauge(
            "CPU",
            ns.cpu_pct.clamp(0.0, 100.0).round() as u16,
            tailwind::GREEN.c500,
        );
        f.render_widget(cpu_gauge, rows[1]);

        // --- Memory gauge -----------------------------------------
        let mem_gauge = make_gauge(
            "MEM",
            ns.mem_pct.clamp(0.0, 100.0).round() as u16,
            tailwind::EMERALD.c400,
        );
        f.render_widget(mem_gauge, rows[2]);

        y += 5; // 5 lines just drawn + 1 blank row spacing
    }
}
