use ratatui::{
    prelude::*,
    style::palette::tailwind,
    widgets::{Block, Borders, Gauge, Padding},
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
    let inner_x = area.x + 1;
    let mut y = area.y + 1;

    let col_layout = |area: Rect| {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Percentage(50), Constraint::Percentage(50)].as_ref())
            .split(area)
    };

    for ns in stats {
        let row = Rect {
            x: inner_x,
            y,
            width: inner_w,
            height: 2,
        };

        let columns = col_layout(row);

        let cpu_title_str = format!("{} | CPU", ns.name);
        let cpu_title = title_block(&cpu_title_str);
        let cpu = Gauge::default()
            .block(cpu_title)
            .gauge_style(
                Style::default()
                    .fg(tailwind::GREEN.c500)
                    .bg(tailwind::GRAY.c800),
            )
            .percent(ns.cpu_pct as u16);

        let mem_title_str = format!("{} | MEM", ns.name);
        let mem_title = title_block(&mem_title_str);

        let mem = Gauge::default()
            .block(mem_title)
            .gauge_style(
                Style::default()
                    .fg(tailwind::GREEN.c500)
                    .bg(tailwind::GRAY.c800),
            )
            .percent(ns.mem_pct as u16);

        f.render_widget(cpu, columns[0]);
        f.render_widget(mem, columns[1]);

        y += 3;
    }
}
fn title_block(title: &str) -> Block {
    let title = Line::from(title).centered();
    Block::new()
        .borders(Borders::NONE)
        .padding(Padding::horizontal(1))
        .title(title)
        .fg(tailwind::BLUE.c200)
}
