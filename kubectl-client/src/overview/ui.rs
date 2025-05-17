use super::nodes::NodeStat;
use ratatui::{
    layout::{Constraint, Direction, Layout, Margin, Rect, Size},
    prelude::*,
    style::palette::tailwind,
    widgets::{Block, Borders, Gauge, Padding},
};
use tui_widgets::scrollview::{ScrollView, ScrollViewState};

const CARD_HEIGHT: u16 = 5; // 4 lines of content + 1 blank spacer

pub fn draw(f: &mut Frame, stats: &[NodeStat], area: Rect, sv_state: &mut ScrollViewState) {
    // ── outer frame ─────────────────────────────────────────────
    let frame = Block::new()
        .title(" Overview (live) ")
        .borders(Borders::ALL)
        .border_style(
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        );
    f.render_widget(frame, area);

    // inner area (where we will place the scroll-view)
    let inner = area.inner(Margin {
        vertical: 1,
        horizontal: 1,
    });

    // total “document” height inside the scroll-view
    let content_h = stats.len() as u16 * CARD_HEIGHT;
    let mut sv = ScrollView::new(Size::new(inner.width, content_h));

    // helper to build both gauges
    let make_gauge = |label: &str, pct: f64, color: Color| {
        Gauge::default()
            .block(
                Block::default()
                    .borders(Borders::NONE)
                    .padding(Padding::horizontal(1)),
            )
            .gauge_style(Style::default().fg(color).bg(tailwind::GRAY.c800))
            .label(format!("{label}: {}", pct.round() as u16))
            .use_unicode(true)
            .percent(pct.clamp(0.0, 100.0) as u16)
    };

    // ── render every NodeStat at absolute positions inside sv ──
    for (idx, ns) in stats.iter().enumerate() {
        let y = idx as u16 * CARD_HEIGHT;
        let card_rect = Rect {
            x: 0,
            y,
            width: inner.width / 2,
            height: 4,
        };

        // split the card vertically: title / CPU / MEM
        let rows = Layout::vertical([
            Constraint::Length(1),
            Constraint::Length(1),
            Constraint::Length(1),
        ])
        .split(card_rect);

        // title line
        sv.render_widget(
            Block::default()
                .borders(Borders::NONE)
                .title(Line::from(ns.name.clone()).centered())
                .fg(tailwind::BLUE.c400),
            rows[0],
        );

        // CPU + MEM gauges
        sv.render_widget(make_gauge("CPU", ns.cpu_pct, tailwind::GREEN.c500), rows[1]);
        sv.render_widget(
            make_gauge("MEM", ns.mem_pct, tailwind::EMERALD.c400),
            rows[2],
        );
    }

    // finally paint the scroll-view (this also draws the scrollbar)
    f.render_stateful_widget(sv, inner, sv_state);
}
