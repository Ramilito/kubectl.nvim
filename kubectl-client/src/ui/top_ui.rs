//! top_view.rs ─ Nodes tab (gauges) + Pods tab (sparklines)

use ratatui::{
    layout::{Constraint, Layout, Margin, Rect},
    prelude::*,
    style::palette::tailwind,
    text::Line,
    widgets::{Block, Borders, Gauge, Padding, Sparkline, Tabs},
};
use tui_widgets::scrollview::{ScrollView, ScrollViewState};

use crate::{
    metrics::{nodes::NodeStat, pods::PodStat},
    pod_stats,
};

/* ---------------------------------------------------------------------- */
/*  CONSTANTS                                                             */
/* ---------------------------------------------------------------------- */

const CARD_HEIGHT: u16 = 1; // one line per node
const ROW_H: u16 = 2; // three lines per pod row
const MAX_TITLE_WIDTH: u16 = 40;

/* ---------------------------------------------------------------------- */
/*  VIEW STATE                                                            */
/* ---------------------------------------------------------------------- */

#[derive(Default)]
pub struct TopViewState {
    selected_tab: usize, // 0 = Nodes, 1 = Pods
    node_scroll: ScrollViewState,
    pod_scroll: ScrollViewState,
}

impl TopViewState {
    /* tab helpers -------------------------------------------------------- */
    pub fn next_tab(&mut self) {
        self.selected_tab = (self.selected_tab + 1) % 2;
    }
    pub fn prev_tab(&mut self) {
        self.selected_tab = if self.selected_tab == 0 { 1 } else { 0 };
    }

    /* scrolling helpers -------------------------------------------------- */
    pub fn scroll_down(&mut self) {
        if self.selected_tab == 0 {
            self.node_scroll.scroll_down();
        } else {
            self.pod_scroll.scroll_down();
        }
    }
    pub fn scroll_up(&mut self) {
        if self.selected_tab == 0 {
            self.node_scroll.scroll_up();
        } else {
            self.pod_scroll.scroll_up();
        }
    }
    pub fn scroll_page_down(&mut self) {
        if self.selected_tab == 0 {
            self.node_scroll.scroll_page_down();
        } else {
            self.pod_scroll.scroll_page_down();
        }
    }
    pub fn scroll_page_up(&mut self) {
        if self.selected_tab == 0 {
            self.node_scroll.scroll_page_up();
        } else {
            self.pod_scroll.scroll_page_up();
        }
    }

    /* compatibility aliases --------------------------------------------- */
    pub fn focus_next(&mut self) {
        self.next_tab();
    }
    pub fn focus_prev(&mut self) {
        self.prev_tab();
    }
}

/* ---------------------------------------------------------------------- */
/*  HELPERS                                                               */
/* ---------------------------------------------------------------------- */

/// Build a coloured sparkline with a tiny title
fn make_sparkline<'a>(title: &'a str, data: &'a [u64], color: Color) -> Sparkline<'a> {
    Sparkline::default()
        .block(Block::new().borders(Borders::NONE).title(title))
        .data(data)
        .style(Style::default().fg(color))
}

/// Trim history to the available column width
fn slice_to_width<'a>(data: &'a [u64], max_w: u16) -> &'a [u64] {
    let w = max_w as usize;
    if data.len() <= w {
        data
    } else {
        &data[..w]
    }
}

/* ---------------------------------------------------------------------- */
/*  PUBLIC DRAW ENTRY-POINT                                               */
/* ---------------------------------------------------------------------- */

pub fn draw(f: &mut Frame, area: Rect, state: &mut TopViewState, node_stats: &[NodeStat]) {
    /* === snapshot of current pod stats ================================= */
    let pod_snapshot: Vec<PodStat> = {
        let guard = pod_stats().lock().unwrap();
        guard.clone()
    };

    /* outer frame -------------------------------------------------------- */
    let outer = Block::new()
        .title(" Top (live) ")
        .borders(Borders::ALL)
        .border_style(
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        );
    f.render_widget(outer, area);

    /* inner region (padding 1) ------------------------------------------ */
    let inner = area.inner(Margin {
        vertical: 1,
        horizontal: 1,
    });

    /* split: tab bar + body --------------------------------------------- */
    let chunks = Layout::vertical([Constraint::Length(1), Constraint::Min(0)]).split(inner);
    let tabs_area = chunks[0];
    let body_area = chunks[1];

    /* tab bar ------------------------------------------------------------ */
    let tabs = Tabs::new(vec![Line::from("Nodes"), Line::from("Pods")])
        .select(state.selected_tab)
        .style(Style::default().fg(Color::White))
        .highlight_style(
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        );
    f.render_widget(tabs, tabs_area);

    /* ============================== NODES ============================== */
    if state.selected_tab == 0 {
        let title_w = node_stats
            .iter()
            .map(|ns| Line::from(ns.name.clone()).width() as u16 + 1)
            .max()
            .unwrap_or(0)
            .clamp(1, MAX_TITLE_WIDTH);

        let content_h = node_stats.len() as u16 * CARD_HEIGHT;
        let mut sv = ScrollView::new(Size::new(body_area.width, content_h));

        let make_gauge = |label: &str, pct: f64, color: Color| {
            Gauge::default()
                .gauge_style(Style::default().fg(color).bg(tailwind::GRAY.c800))
                .label(format!("{label}: {}", pct.round() as u16))
                .use_unicode(true)
                .percent(pct.clamp(0.0, 100.0) as u16)
        };

        for (idx, ns) in node_stats.iter().enumerate() {
            let y = idx as u16 * CARD_HEIGHT;
            let card = Rect {
                x: 0,
                y,
                width: body_area.width,
                height: CARD_HEIGHT,
            };

            let cols = Layout::horizontal([
                Constraint::Length(title_w),
                Constraint::Percentage(50),
                Constraint::Percentage(50),
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

        f.render_stateful_widget(sv, body_area, &mut state.node_scroll);
    }
    /* =============================== PODS ============================== */
    else {
        let title_w = pod_snapshot
            .iter()
            .map(|p| {
                let full = format!("{}/{}", p.namespace, p.name);
                Line::from(full).width() as u16 + 1
            })
            .max()
            .unwrap_or(1)
            .clamp(1, MAX_TITLE_WIDTH);

        let content_h = pod_snapshot.len() as u16 * ROW_H;
        let mut sv = ScrollView::new(Size::new(body_area.width, content_h));

        for (idx, p) in pod_snapshot.iter().enumerate() {
            let y = idx as u16 * ROW_H;
            let card = Rect {
                x: 0,
                y,
                width: body_area.width,
                height: ROW_H,
            };

            /* 1 ─ split off name column + remaining area ------------------ */
            let cols =
                Layout::horizontal([Constraint::Length(title_w), Constraint::Min(0)]).split(card);
            let name_col = cols[0];
            let rest = cols[1];

            /* 2 ─ split remaining area into two halves -------------------- */
            let halves =
                Layout::horizontal([Constraint::Percentage(50), Constraint::Percentage(50)])
                    .split(rest);
            let cpu_col = halves[0];
            let mem_col = halves[1];

            /* 3 ─ render --------------------------------------------------- */
            sv.render_widget(
                Block::new()
                    .borders(Borders::NONE)
                    .title(format!("{}/{}", p.namespace, p.name))
                    .fg(tailwind::BLUE.c400),
                name_col,
            );

            sv.render_widget(
                make_sparkline(
                    "CPU",
                    slice_to_width(&p.cpu_history, cpu_col.width),
                    tailwind::GREEN.c500,
                ),
                cpu_col,
            );
            sv.render_widget(
                make_sparkline(
                    "MEM",
                    slice_to_width(&p.mem_history, mem_col.width),
                    tailwind::EMERALD.c400,
                ),
                mem_col,
            );
        }

        f.render_stateful_widget(sv, body_area, &mut state.pod_scroll);
    }
}
