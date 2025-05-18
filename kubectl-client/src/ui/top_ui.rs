use ratatui::{
    layout::{Constraint, Layout, Margin, Rect},
    prelude::*,
    style::palette::tailwind,
    text::Line,
    widgets::{Block, Borders, Gauge, Padding},
};
use tui_widgets::scrollview::{ScrollView, ScrollViewState};

use super::nodes::NodeStat;

const CARD_HEIGHT: u16 = 1; // one line per card
const MAX_TITLE_WIDTH: u16 = 40; // hard cap for the first column

pub fn draw(f: &mut Frame, stats: &[NodeStat], area: Rect, sv_state: &mut ScrollViewState) {
    /* ── figure out the exact width we need for the name column ────────── */
    let title_width: u16 = stats
        .iter()
        .map(|ns| Line::from(ns.name.clone()).width() as u16 + 1) // Unicode cell-width
        .max()
        .unwrap_or(0)
        .clamp(1, MAX_TITLE_WIDTH);

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

        // layout that keeps the first column *exactly* title_width cells wide
        let cols = Layout::horizontal([
            Constraint::Length(title_width), // name column
            Constraint::Percentage(50),      // CPU gauge
            Constraint::Percentage(50),      // MEM gauge
        ])
        .split(card);

        sv.render_widget(
            Block::new()
                .borders(Borders::NONE)
                .padding(Padding::vertical(1))
                .title(ns.name.clone())
                .fg(tailwind::BLUE.c400),
            cols[0],
        );

        sv.render_widget(make_gauge("CPU", ns.cpu_pct, tailwind::GREEN.c500), cols[1]);
        sv.render_widget(
            make_gauge("MEM", ns.mem_pct, tailwind::EMERALD.c400),
            cols[2],
        );
    }

    /* paint the scroll-view & scrollbar */
    f.render_stateful_widget(sv, inner, sv_state);
}
