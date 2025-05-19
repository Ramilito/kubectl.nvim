use ratatui::{
    layout::{Constraint, Layout, Margin, Rect},
    prelude::*,
    style::palette::tailwind,
    text::Line,
    widgets::{Block, Borders, Cell, Gauge, Padding, Row, Table, TableState, Tabs},
};
use tui_widgets::scrollview::{ScrollView, ScrollViewState};

use crate::{
    metrics::{
        nodes::NodeStat,
        pods::PodStat, //  ◀─ global accessor + struct
    },
    pod_stats,
};

const CARD_HEIGHT: u16 = 1; // one line per Node row
const MAX_TITLE_WIDTH: u16 = 40;
const PAGE: usize = 10;

#[derive(Default)]
pub struct TopViewState {
    selected_tab: usize, // 0 = Nodes, 1 = Pods
    node_scroll: ScrollViewState,
    pod_table: TableState,
    pod_rows: usize, // total pod rows (for scroll bounds)
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
            let next = self.pod_table.selected().unwrap_or(0).saturating_add(1);
            if next < self.pod_rows {
                self.pod_table.select(Some(next));
            }
        }
    }
    pub fn scroll_up(&mut self) {
        if self.selected_tab == 0 {
            self.node_scroll.scroll_up();
        } else if let Some(sel) = self.pod_table.selected() {
            if sel > 0 {
                self.pod_table.select(Some(sel - 1));
            }
        }
    }
    pub fn scroll_page_down(&mut self) {
        if self.selected_tab == 0 {
            self.node_scroll.scroll_page_down();
        } else {
            let next = self.pod_table.selected().unwrap_or(0).saturating_add(PAGE);
            self.pod_table
                .select(Some(next.min(self.pod_rows.saturating_sub(1))));
        }
    }
    pub fn scroll_page_up(&mut self) {
        if self.selected_tab == 0 {
            self.node_scroll.scroll_page_up();
        } else {
            let next = self.pod_table.selected().unwrap_or(0).saturating_sub(PAGE);
            self.pod_table.select(Some(next));
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

/* ───────────── public draw entry-point ───────────────────────────────── */
pub fn draw(f: &mut Frame, area: Rect, state: &mut TopViewState, node_stats: &[NodeStat]) {
    /* === NEW: take a snapshot of pods =================================== */
    let pod_snapshot: Vec<PodStat> = {
        let guard = pod_stats().lock().unwrap();
        guard.clone() // clones Vec<PodStat>; releases lock
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
    let [tabs_area, body_area] =
        Layout::vertical([Constraint::Length(1), Constraint::Min(0)]).areas(inner);

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
        /* … 100 % identical to before … */
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
        state.pod_rows = pod_snapshot.len();

        let title_w = pod_snapshot
            .iter()
            .map(|ps| {
                let full = format!("{}/{}", ps.namespace, ps.name);
                Line::from(full).width() as u16 + 1
            })
            .max()
            .unwrap_or(0)
            .clamp(1, MAX_TITLE_WIDTH);

        let header = Row::new(vec![
            Cell::from("Pod"),
            Cell::from("CPU (m)"),
            Cell::from("MEM (Mi)"),
            Cell::from("%CPU/R"),
            Cell::from("%CPU/L"),
            Cell::from("%MEM/R"),
            Cell::from("%MEM/L"),
        ])
        .style(
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        );

        let rows: Vec<Row> = pod_snapshot
            .iter()
            .map(|ps| {
                let name = format!("{}/{}", ps.namespace, ps.name);
                Row::new(vec![
                    Cell::from(name),
                    Cell::from(ps.cpu_m.to_string()),
                    Cell::from(ps.mem_mi.to_string()),
                ])
            })
            .collect();

        let widths = [
            Constraint::Length(title_w), // Pod name
            Constraint::Length(9),       // CPU (m)
            Constraint::Length(9),       // MEM (Mi)
        ];

        let table = Table::new(rows, &widths)
            .header(header)
            .column_spacing(2)
            .row_highlight_style(Style::default().bg(tailwind::BLUE.c900).fg(Color::White))
            .highlight_symbol("▶ ");

        f.render_stateful_widget(table, body_area, &mut state.pod_table);
    }
}
