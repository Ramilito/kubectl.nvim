//! top_view.rs ─ Nodes tab (gauges) + Pods tab (3-row sparklines + header)

use ratatui::{
    layout::{Constraint, Layout, Margin, Rect},
    prelude::*,
    style::palette::tailwind,
    text::Line,
    widgets::{Block, Borders, Gauge, Padding, Paragraph, Sparkline, Tabs},
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
const GRAPH_H: u16 = 3; // graph rows (with label overlay)
const ROW_H: u16 = GRAPH_H + 1; // +1 blank spacer row
const MAX_TITLE_WIDTH: u16 = 100;
const OVERSCAN_ROWS: u16 = 2;

/* ---------------------------------------------------------------------- */
/*  VIEW STATE + key handling                                             */
/* ---------------------------------------------------------------------- */

#[derive(PartialEq, Eq, Default)]
pub enum InputMode {
    #[default]
    Normal,
    Filtering,
}

#[derive(Default)]
pub struct TopViewState {
    selected_tab: usize,
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
            self.node_scroll.scroll_down()
        } else {
            self.pod_scroll.scroll_down()
        }
    }
    pub fn scroll_up(&mut self) {
        if self.selected_tab == 0 {
            self.node_scroll.scroll_up()
        } else {
            self.pod_scroll.scroll_up()
        }
    }
    pub fn scroll_page_down(&mut self) {
        if self.selected_tab == 0 {
            self.node_scroll.scroll_page_down()
        } else {
            self.pod_scroll.scroll_page_down()
        }
    }
    pub fn scroll_page_up(&mut self) {
        if self.selected_tab == 0 {
            self.node_scroll.scroll_page_up()
        } else {
            self.pod_scroll.scroll_page_up()
        }
    }

    /* filter keys -------------------------------------------------------- */
    pub fn handle_key(&mut self, key: KeyEvent) {
        match self.input_mode {
            InputMode::Normal => {
                if let KeyCode::Char('/') = key.code {
                    self.input_mode = InputMode::Filtering
                }
            }
            InputMode::Filtering => match key.code {
                KeyCode::Esc => {
                    self.filter.clear();
                    self.input_mode = InputMode::Normal;
                }
                KeyCode::Enter => self.input_mode = InputMode::Normal,
                KeyCode::Backspace => {
                    self.filter.pop();
                }
                KeyCode::Char(c)
                    if key.modifiers.is_empty() || key.modifiers == KeyModifiers::SHIFT =>
                {
                    self.filter.push(c)
                }
                _ => {}
            },
        }
    }
}

/* ---------------------------------------------------------------------- */
/*  HELPERS                                                               */
/* ---------------------------------------------------------------------- */

fn slice_to_width(data: &[u64], max_w: u16) -> &[u64] {
    let w = max_w as usize;
    if data.len() <= w {
        data
    } else {
        &data[..w]
    }
}

fn visible_rows(offset_px: u16, row_h: u16, view_h: u16, overscan: u16) -> (usize, usize) {
    let first = offset_px / row_h;
    let visible = (view_h / row_h) + 1;
    let start = first.saturating_sub(overscan);
    let end = first + visible + overscan;
    (start as usize, (end - start) as usize)
}

/* ---------------------------------------------------------------------- */
/*  DRAW ENTRY-POINT                                                      */
/* ---------------------------------------------------------------------- */

pub fn draw(f: &mut Frame, area: Rect, state: &mut TopViewState, node_stats: &[NodeStat]) {
    /* snapshot ----------------------------------------------------------- */
    let pod_snapshot: Vec<PodStat> = { pod_stats().lock().unwrap().clone() };

    /* outer frame -------------------------------------------------------- */
    f.render_widget(
        Block::new()
            .title(" Top (live) ")
            .borders(Borders::ALL)
            .border_style(
                Style::default()
                    .fg(Color::Cyan)
                    .add_modifier(Modifier::BOLD),
            ),
        area,
    );

    /* layout: tabs ─ header ─ scrollable body --------------------------- */
    let inner = area.inner(Margin::new(1, 1));
    let [tabs_area, hdr_area, body_area] = Layout::vertical([
        Constraint::Length(1),
        Constraint::Length(1),
        Constraint::Min(0),
    ])
    .areas(inner);

    /* tab bar ------------------------------------------------------------ */
    let pods_title = if state.filter.is_empty() {
        Line::from("Pods")
    } else {
        Line::from(format!("Pods (filter: {})", state.filter))
    };
    let tabs = Tabs::new(vec![Line::from("Nodes"), pods_title])
        .select(state.selected_tab)
        .style(Style::default().fg(Color::White))
        .highlight_style(
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        );
    f.render_widget(tabs, tabs_area);

    /* ================================= NODES =========================== */
    if state.selected_tab == 0 {
        /* column width for NAME */
        let title_w = node_stats
            .iter()
            .map(|ns| Line::from(ns.name.clone()).width() as u16 + 1)
            .max()
            .unwrap_or(0)
            .clamp(1, MAX_TITLE_WIDTH);

        /* header row ----------------------------------------------------- */
        draw_header(f, hdr_area, title_w);

        /* scroll view ---------------------------------------------------- */
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

            let [name_col, cpu_col, mem_col] = column_split(card, title_w);

            sv.render_widget(
                Block::new()
                    .borders(Borders::NONE)
                    .padding(Padding::vertical(1))
                    .title(ns.name.clone())
                    .fg(tailwind::BLUE.c400),
                name_col,
            );
            sv.render_widget(make_gauge("CPU", ns.cpu_pct, tailwind::GREEN.c500), cpu_col);
            sv.render_widget(
                make_gauge("MEM", ns.mem_pct, tailwind::ORANGE.c400),
                mem_col,
            );
        }
        f.render_stateful_widget(sv, body_area, &mut state.node_scroll);
        return;
    }

    /* ================================= PODS ============================ */

    /* 0 ▸ filter -------------------------------------------------------- */
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

    /* 1 ▸ column widths ------------------------------------------------- */
    let title_w = filtered
        .iter()
        .map(|p| {
            let full = format!("{}/{}", p.namespace, p.name);
            Line::from(full).width() as u16 + 1
        })
        .max()
        .unwrap_or(1)
        .clamp(1, MAX_TITLE_WIDTH);

    /* header row -------------------------------------------------------- */
    draw_header(f, hdr_area, title_w);

    /* 2 ▸ virtual-window ------------------------------------------------ */
    let content_h = filtered.len() as u16 * ROW_H;
    let offset_px = state.pod_scroll.offset().y;
    let (first, count) = visible_rows(offset_px, ROW_H, body_area.height, OVERSCAN_ROWS);
    let last = (first + count).min(filtered.len());
    let slice = &filtered[first..last];

    let mut sv = ScrollView::new(Size::new(body_area.width, content_h));

    /* 3 ▸ render slice -------------------------------------------------- */
    for (idx, p) in slice.iter().enumerate() {
        let y_graph = ((first + idx) as u16) * ROW_H;
        let graph_rect = Rect {
            x: 0,
            y: y_graph,
            width: body_area.width,
            height: GRAPH_H,
        };

        let [name_col, cpu_col, mem_col] = column_split(graph_rect, title_w);

        /* name column ---------------------------------------------------- */
        sv.render_widget(
            Block::new()
                .borders(Borders::NONE)
                .title(format!("{}/{}", p.namespace, p.name))
                .fg(tailwind::BLUE.c400),
            name_col,
        );

        /* spark bars ----------------------------------------------------- */
        let cpu_data = slice_to_width(&p.cpu_history, cpu_col.width);
        let mem_data = slice_to_width(&p.mem_history, mem_col.width);
        sv.render_widget(
            Sparkline::default()
                .data(cpu_data)
                .style(Style::default().fg(tailwind::GREEN.c500)),
            cpu_col,
        );
        sv.render_widget(
            Sparkline::default()
                .data(mem_data)
                .style(Style::default().fg(tailwind::ORANGE.c400)),
            mem_col,
        );
    }

    f.render_stateful_widget(sv, body_area, &mut state.pod_scroll);
}

/* ---------------------------------------------------------------------- */
/*  SMALL UTILS                                                           */
/* ---------------------------------------------------------------------- */

fn column_split(card: Rect, name_w: u16) -> [Rect; 3] {
    Layout::horizontal([
        Constraint::Length(name_w),
        Constraint::Percentage(50),
        Constraint::Percentage(50),
    ])
    .areas(card)
}

fn draw_header(f: &mut Frame, hdr_area: Rect, name_w: u16) {
    let cols = column_split(hdr_area, name_w);
    let style = Style::default()
        .fg(tailwind::GRAY.c300)
        .add_modifier(Modifier::BOLD);
    f.render_widget(Paragraph::new("NAME").style(style), cols[0]);
    f.render_widget(
        Paragraph::new("CPU")
            .alignment(Alignment::Center)
            .style(style),
        cols[1],
    );
    f.render_widget(
        Paragraph::new("MEM")
            .alignment(Alignment::Center)
            .style(style),
        cols[2],
    );
}
