use super::nodes::NodeStat;
use ratatui::{
    layout::{Constraint, Layout, Margin, Rect, Size},
    prelude::*,
    style::palette::tailwind,
    widgets::{Block, Borders, Gauge, Padding},
};
use tui_widgets::scrollview::{ScrollView, ScrollViewState};

const CARD_HEIGHT: u16 = 1; // title + 2 gauges

pub fn draw(f: &mut Frame, stats: &[NodeStat], area: Rect, sv_state: &mut ScrollViewState) {
    /* ── outer frame ───────────────────────────────────────────────────── */
    let outer = Block::new()
        .title(" Overview (live) ")
        .borders(Borders::ALL)
        .border_style(
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        );
    f.render_widget(outer, area);

    /* inner area where the scroll-view lives */
    let inner = area.inner(Margin {
        vertical: 1,
        horizontal: 1,
    });

    /* build the scroll-view ------------------------------------------------ */
    let content_h = stats.len() as u16 * CARD_HEIGHT;
    let mut sv = ScrollView::new(Size::new(inner.width, content_h));

    /* helper for both gauges */
    let make_gauge = |label: &str, pct: f64, color: Color| {
        Gauge::default()
            .gauge_style(Style::default().fg(color).bg(tailwind::GRAY.c800))
            .label(format!("{label}: {}", pct.round() as u16))
            .use_unicode(true)
            .percent(pct.clamp(0.0, 100.0) as u16)
    };

    /* render every NodeStat inside the scroll-view ------------------------ */
    for (idx, ns) in stats.iter().enumerate() {
        let y = idx as u16 * CARD_HEIGHT;
        let card = Rect {
            x: 0,
            y,
            width: inner.width,
            height: CARD_HEIGHT,
        };

        let rows = Layout::horizontal([
            Constraint::Percentage(33), // title
            Constraint::Percentage(33), // CPU
            Constraint::Percentage(33), // MEM
        ])
        .split(card);

        sv.render_widget(
            Block::new()
                .borders(Borders::NONE)
                .padding(Padding::vertical(1))
                .title(Line::from(ns.name.clone()).right_aligned())
                .fg(tailwind::BLUE.c400),
            rows[0],
        );
        sv.render_widget(make_gauge("CPU", ns.cpu_pct, tailwind::GREEN.c500), rows[1]);
        sv.render_widget(
            make_gauge("MEM", ns.mem_pct, tailwind::EMERALD.c400),
            rows[2],
        );
    }

    /* paint the scroll-view & scrollbar */
    f.render_stateful_widget(sv, inner, sv_state);
}
