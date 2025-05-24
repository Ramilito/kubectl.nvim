//! top_view.rs ─ Nodes tab (gauges) + Pods tab (sparklines + filter)

use ratatui::{
    layout::{Constraint, Layout, Margin, Rect},
    prelude::*,
    style::palette::tailwind,
    text::Line,
    widgets::{Block, Borders, Gauge, Padding, Sparkline, Tabs},
};
use tui_widgets::scrollview::{ScrollView, ScrollViewState};

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

use crate::{
    metrics::{nodes::NodeStat, pods::PodStat},
    pod_stats,
};

/* ---------------------------------------------------------------------- */
/*  CONSTANTS                                                             */
/* ---------------------------------------------------------------------- */

const CARD_HEIGHT: u16 = 1; // one line per node
const ROW_H: u16 = 2; // two lines per pod row
const MAX_TITLE_WIDTH: u16 = 100;
const OVERSCAN_ROWS: u16 = 2; // rows to build above/below the viewport

/* ---------------------------------------------------------------------- */
/*  VIEW STATE                                                            */
/* ---------------------------------------------------------------------- */

#[derive(PartialEq, Eq, Default)]
pub enum InputMode {
    #[default]
    Normal,
    Filtering,
}

#[derive(Default)]
pub struct TopViewState {
    selected_tab: usize, // 0 = Nodes, 1 = Pods
    node_scroll: ScrollViewState,
    pod_scroll: ScrollViewState,
    filter: String,
    pub input_mode: InputMode,
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

    /* ------------------------------------------------------------------ */
    /*  KEY HANDLER – call from your event loop                           */
    /* ------------------------------------------------------------------ */
    pub fn handle_key(&mut self, key: KeyEvent) {
        match self.input_mode {
            InputMode::Normal => match key.code {
                KeyCode::Char('/') => {
                    self.input_mode = InputMode::Filtering;
                }
                _ => {
                    // put existing key handling here (scroll, tab switch, etc.)
                }
            },
            InputMode::Filtering => match key.code {
                KeyCode::Esc => {
                    self.filter.clear();
                    self.input_mode = InputMode::Normal;
                }
                KeyCode::Enter => {
                    self.input_mode = InputMode::Normal;
                }
                KeyCode::Backspace => {
                    self.filter.pop();
                }
                KeyCode::Char(c)
                    if key.modifiers.is_empty() || key.modifiers == KeyModifiers::SHIFT =>
                {
                    self.filter.push(c);
                }
                _ => {}
            },
        }
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
fn slice_to_width(data: &[u64], max_w: u16) -> &[u64] {
    let w = max_w as usize;
    if data.len() <= w {
        data
    } else {
        &data[..w]
    }
}

/// Return (first_row, how_many) given current scroll offset and viewport
fn visible_rows(offset_px: u16, row_h: u16, view_h: u16, overscan: u16) -> (usize, usize) {
    let first = offset_px / row_h; // topmost fully-visible row
    let visible = (view_h / row_h) + 1; // +1 so we don’t truncate
    let start = first.saturating_sub(overscan); // overscan above
    let end = first + visible + overscan; // and below
    (start as usize, (end - start) as usize)
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
    let pods_tab_title = if state.filter.is_empty() {
        Line::from("Pods")
    } else {
        Line::from(format!("Pods (filter: {})", state.filter))
    };
    let tabs = Tabs::new(vec![Line::from("Nodes"), pods_tab_title])
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
        /* 0 ─ apply filter ------------------------------------------------ */
        let filtered: Vec<&PodStat> = if state.filter.is_empty() {
            pod_snapshot.iter().collect()
        } else {
            let needle = state.filter.to_lowercase();
            pod_snapshot
                .iter()
                .filter(|p| {
                    let hay = format!("{}/{}", p.namespace, p.name).to_lowercase();
                    hay.contains(&needle)
                })
                .collect()
        };

        /* 1 ─ static maths ------------------------------------------------ */
        let title_w = filtered
            .iter()
            .map(|p| {
                let full = format!("{}/{}", p.namespace, p.name);
                Line::from(full).width() as u16 + 1
            })
            .max()
            .unwrap_or(1)
            .clamp(1, MAX_TITLE_WIDTH);

        /* 2 ─ virtual-window maths --------------------------------------- */
        let content_h = filtered.len() as u16 * ROW_H;
        let offset_px = state.pod_scroll.offset(); // scroll position in px
        let (first, count) = visible_rows(offset_px.y, ROW_H, body_area.height, OVERSCAN_ROWS);
        let last = (first + count).min(filtered.len());
        let slice = &filtered[first..last];

        let mut sv = ScrollView::new(Size::new(body_area.width, content_h));

        /* 3 ─ render slice ------------------------------------------------ */
        for (idx, p) in slice.iter().enumerate() {
            // idx is 0..count in slice – convert to absolute y
            let y = ((first + idx) as u16) * ROW_H;
            let card = Rect {
                x: 0,
                y,
                width: body_area.width,
                height: ROW_H,
            };

            /* 3a ─ layout -------------------------------------------------- */
            let cols =
                Layout::horizontal([Constraint::Length(title_w), Constraint::Min(0)]).split(card);
            let name_col = cols[0];
            let rest = cols[1];
            let halves =
                Layout::horizontal([Constraint::Percentage(50), Constraint::Percentage(50)])
                    .split(rest);
            let cpu_col = halves[0];
            let mem_col = halves[1];

            /* 3b ─ widgets ------------------------------------------------- */
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
