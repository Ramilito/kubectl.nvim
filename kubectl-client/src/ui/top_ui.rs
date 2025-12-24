//! top_view.rs ─ Nodes tab (gauges) + Pods tab (3-row sparklines + header)

use ratatui::{
    layout::{Constraint, Layout, Margin, Rect},
    prelude::*,
    style::palette::tailwind,
    text::Line,
    widgets::{Block, Borders, Clear, Gauge, Padding, Paragraph, Sparkline, Tabs},
};
use std::collections::{BTreeMap, HashSet};
use tui_widgets::scrollview::{ScrollView, ScrollViewState};

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

use crate::{
    metrics::{nodes::NodeStat, pods::PodStat},
    node_stats, pod_stats,
};

/* ---------------------------------------------------------------------- */
/*  CONSTANTS                                                             */
/* ---------------------------------------------------------------------- */

const CARD_HEIGHT: u16 = 1; // one line per node
const GRAPH_H: u16 = 3; // graph rows (with label overlay)
const ROW_H: u16 = GRAPH_H + 1; // +1 blank spacer row
const NS_HEADER_H: u16 = 1; // namespace header row
const MAX_TITLE_WIDTH: u16 = 100;
const COL_GAP: u16 = 2; // gap between CPU and MEM columns

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
    collapsed_namespaces: HashSet<String>,
    known_namespaces: HashSet<String>,
    /// Currently selected namespace index (for Pods tab)
    selected_ns_idx: usize,
    /// Ordered list of namespace names (updated each draw)
    ns_order: Vec<String>,
    /// Show help overlay
    show_help: bool,
}

impl TopViewState {
    /* tab helpers -------------------------------------------------------- */
    pub fn next_tab(&mut self) {
        self.selected_tab = (self.selected_tab + 1) % 2;
    }

    #[allow(dead_code)]
    pub fn prev_tab(&mut self) {
        self.selected_tab = if self.selected_tab == 0 { 1 } else { 0 };
    }

    pub fn is_pods_tab(&self) -> bool {
        self.selected_tab == 1
    }

    /* help toggle -------------------------------------------------------- */
    pub fn toggle_help(&mut self) {
        self.show_help = !self.show_help;
    }

    pub fn is_help_visible(&self) -> bool {
        self.show_help
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

    /* namespace collapse ------------------------------------------------- */
    fn toggle_namespace(&mut self, ns: &str) {
        if self.collapsed_namespaces.contains(ns) {
            self.collapsed_namespaces.remove(ns);
        } else {
            self.collapsed_namespaces.insert(ns.to_string());
        }
    }

    pub fn is_namespace_collapsed(&self, ns: &str) -> bool {
        self.collapsed_namespaces.contains(ns)
    }

    pub fn expand_all(&mut self) {
        self.collapsed_namespaces.clear();
    }

    pub fn collapse_all(&mut self) {
        self.collapsed_namespaces = self.known_namespaces.clone();
    }

    pub fn update_known_namespaces(&mut self, namespaces: impl Iterator<Item = String>) {
        self.known_namespaces.extend(namespaces);
    }

    /* namespace selection ------------------------------------------------ */
    pub fn select_next_ns(&mut self) {
        if !self.ns_order.is_empty() {
            self.selected_ns_idx = (self.selected_ns_idx + 1).min(self.ns_order.len() - 1);
        }
    }

    pub fn select_prev_ns(&mut self) {
        self.selected_ns_idx = self.selected_ns_idx.saturating_sub(1);
    }

    pub fn toggle_selected_ns(&mut self) {
        if let Some(ns) = self.ns_order.get(self.selected_ns_idx) {
            let ns = ns.clone();
            self.toggle_namespace(&ns);
        }
    }

    pub fn selected_namespace(&self) -> Option<&str> {
        self.ns_order.get(self.selected_ns_idx).map(|s| s.as_str())
    }

    pub fn update_ns_order(&mut self, namespaces: Vec<String>) {
        // Clamp selection if list shrinks
        if !namespaces.is_empty() && self.selected_ns_idx >= namespaces.len() {
            self.selected_ns_idx = namespaces.len() - 1;
        }
        self.ns_order = namespaces;
    }
}

/* ---------------------------------------------------------------------- */
/*  HELPERS                                                               */
/* ---------------------------------------------------------------------- */

fn deque_to_vec(data: &std::collections::VecDeque<u64>, max_w: u16) -> Vec<u64> {
    let w = max_w as usize;
    data.iter().take(w).copied().collect()
}

/* ---------------------------------------------------------------------- */
/*  DRAW ENTRY-POINT                                                      */
/* ---------------------------------------------------------------------- */

pub fn draw(f: &mut Frame, area: Rect, state: &mut TopViewState) {
    /* snapshot ----------------------------------------------------------- */
    let pod_snapshot: Vec<PodStat> = pod_stats()
        .lock()
        .map(|guard| guard.values().cloned().collect())
        .unwrap_or_default();
    let node_snapshot: Vec<NodeStat> = node_stats()
        .lock()
        .map(|guard| guard.clone())
        .unwrap_or_default();

    /* outer frame -------------------------------------------------------- */
    f.render_widget(
        Block::new()
            .title(" Top (live) ")
            .title_bottom(
                Line::from(" Press ? for help ")
                    .style(Style::default().fg(tailwind::GRAY.c500))
                    .right_aligned(),
            )
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
        let title_w = node_snapshot
            .iter()
            .map(|ns| Line::from(ns.name.clone()).width() as u16 + 1)
            .max()
            .unwrap_or(0)
            .clamp(1, MAX_TITLE_WIDTH);

        /* header row ----------------------------------------------------- */
        draw_header(f, hdr_area, title_w);

        /* scroll view ---------------------------------------------------- */
        let content_h = node_snapshot.len() as u16 * CARD_HEIGHT;
        let mut sv = ScrollView::new(Size::new(body_area.width, content_h));
        let make_gauge = |label: &str, pct: f64, color: Color| {
            Gauge::default()
                .gauge_style(Style::default().fg(color).bg(tailwind::GRAY.c800))
                .label(format!("{label}: {}", pct.round() as u16))
                .use_unicode(true)
                .percent(pct.clamp(0.0, 100.0) as u16)
        };

        for (idx, ns) in node_snapshot.iter().enumerate() {
            let y = idx as u16 * CARD_HEIGHT;
            let card = Rect {
                x: 0,
                y,
                width: body_area.width,
                height: CARD_HEIGHT,
            };

            let [name_col, cpu_col, _gap, mem_col] = column_split(card, title_w);

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

    /* 1 ▸ group by namespace -------------------------------------------- */
    let mut grouped: BTreeMap<&str, Vec<&PodStat>> = BTreeMap::new();
    for p in &filtered {
        grouped.entry(p.namespace.as_str()).or_default().push(p);
    }

    /* track known namespaces for collapse_all --------------------------- */
    state.update_known_namespaces(grouped.keys().map(|s| s.to_string()));

    /* update ordered namespace list for selection ------------------------ */
    let ns_list: Vec<String> = grouped.keys().map(|s| s.to_string()).collect();
    state.update_ns_order(ns_list);

    /* 2 ▸ column widths ------------------------------------------------- */
    let title_w = filtered
        .iter()
        .map(|p| Line::from(p.name.clone()).width() as u16 + 3) // +3 for indent
        .max()
        .unwrap_or(1)
        .clamp(1, MAX_TITLE_WIDTH);

    /* header row -------------------------------------------------------- */
    draw_header(f, hdr_area, title_w);

    /* 3 ▸ calculate content height with namespace headers --------------- */
    let mut content_h: u16 = 0;
    for (ns, pods) in &grouped {
        content_h += NS_HEADER_H; // namespace header
        if !state.is_namespace_collapsed(ns) {
            content_h += pods.len() as u16 * ROW_H;
        }
    }

    let mut sv = ScrollView::new(Size::new(body_area.width, content_h));

    /* 4 ▸ render grouped pods ------------------------------------------- */
    let mut y: u16 = 0;
    let selected_ns = state.selected_namespace();

    for (_ns_idx, (ns, pods)) in grouped.iter().enumerate() {
        let is_collapsed = state.is_namespace_collapsed(ns);
        let is_selected = selected_ns == Some(*ns);
        let indicator = if is_collapsed { "▶" } else { "▼" };
        let ns_total_cpu: u64 = pods.iter().map(|p| p.cpu_m).sum();
        let ns_total_mem: u64 = pods.iter().map(|p| p.mem_mi).sum();

        /* namespace header ----------------------------------------------- */
        let ns_header_rect = Rect {
            x: 0,
            y,
            width: body_area.width,
            height: NS_HEADER_H,
        };

        let selection_indicator = if is_selected { ">" } else { " " };
        let ns_title = format!(
            "{}{} {} ({}) - CPU: {}m | MEM: {} MiB",
            selection_indicator,
            indicator,
            ns,
            pods.len(),
            ns_total_cpu,
            ns_total_mem
        );

        let ns_style = if is_selected {
            Style::default()
                .fg(tailwind::YELLOW.c400)
                .bg(tailwind::GRAY.c800)
                .add_modifier(Modifier::BOLD)
        } else {
            Style::default()
                .fg(tailwind::CYAN.c400)
                .add_modifier(Modifier::BOLD)
        };

        sv.render_widget(Paragraph::new(ns_title).style(ns_style), ns_header_rect);
        y += NS_HEADER_H;

        if is_collapsed {
            continue;
        }

        /* render pods in namespace --------------------------------------- */
        for p in pods {
            let graph_rect = Rect {
                x: 0,
                y,
                width: body_area.width,
                height: GRAPH_H,
            };

            let [name_col, cpu_col, _gap, mem_col] = column_split(graph_rect, title_w);

            /* name column (indented) ------------------------------------- */
            sv.render_widget(
                Block::new()
                    .borders(Borders::NONE)
                    .title(format!("  {}", p.name))
                    .fg(tailwind::BLUE.c400),
                name_col,
            );

            /* spark bars with current value labels ----------------------- */
            let cpu_data = deque_to_vec(&p.cpu_history, cpu_col.width.saturating_sub(8));
            let mem_data = deque_to_vec(&p.mem_history, mem_col.width.saturating_sub(10));

            // CPU sparkline with value label
            let cpu_label = format!("{}m", p.cpu_m);
            sv.render_widget(
                Sparkline::default()
                    .data(&cpu_data)
                    .style(Style::default().fg(tailwind::GREEN.c500)),
                Rect {
                    width: cpu_col.width.saturating_sub(cpu_label.len() as u16 + 1),
                    ..cpu_col
                },
            );
            sv.render_widget(
                Paragraph::new(cpu_label).alignment(Alignment::Right).style(
                    Style::default()
                        .fg(tailwind::GREEN.c300)
                        .add_modifier(Modifier::BOLD),
                ),
                cpu_col,
            );

            // MEM sparkline with value label
            let mem_label = format!("{} MiB", p.mem_mi);
            sv.render_widget(
                Sparkline::default()
                    .data(&mem_data)
                    .style(Style::default().fg(tailwind::ORANGE.c400)),
                Rect {
                    width: mem_col.width.saturating_sub(mem_label.len() as u16 + 1),
                    ..mem_col
                },
            );
            sv.render_widget(
                Paragraph::new(mem_label)
                    .alignment(Alignment::Right)
                    .style(
                        Style::default()
                            .fg(tailwind::ORANGE.c300)
                            .add_modifier(Modifier::BOLD),
                    ),
                mem_col,
            );

            y += ROW_H;
        }
    }

    f.render_stateful_widget(sv, body_area, &mut state.pod_scroll);

    /* ================================= HELP OVERLAY ==================== */
    if state.show_help {
        draw_help_overlay(f, area);
    }
}

/* ---------------------------------------------------------------------- */
/*  HELP OVERLAY                                                          */
/* ---------------------------------------------------------------------- */

fn draw_help_overlay(f: &mut Frame, area: Rect) {
    let help_lines = vec![
        Line::from(vec![
            Span::styled("Tab", Style::default().fg(tailwind::YELLOW.c400).add_modifier(Modifier::BOLD)),
            Span::raw("       Switch between Nodes/Pods tabs"),
        ]),
        Line::from(""),
        Line::from(Span::styled("── Navigation ──", Style::default().fg(tailwind::CYAN.c400))),
        Line::from(vec![
            Span::styled("j/↓", Style::default().fg(tailwind::YELLOW.c400).add_modifier(Modifier::BOLD)),
            Span::raw("       Select next namespace"),
        ]),
        Line::from(vec![
            Span::styled("k/↑", Style::default().fg(tailwind::YELLOW.c400).add_modifier(Modifier::BOLD)),
            Span::raw("       Select previous namespace"),
        ]),
        Line::from(vec![
            Span::styled("PgDn/PgUp", Style::default().fg(tailwind::YELLOW.c400).add_modifier(Modifier::BOLD)),
            Span::raw(" Scroll view"),
        ]),
        Line::from(""),
        Line::from(Span::styled("── Namespaces ──", Style::default().fg(tailwind::CYAN.c400))),
        Line::from(vec![
            Span::styled("Enter/Space", Style::default().fg(tailwind::YELLOW.c400).add_modifier(Modifier::BOLD)),
            Span::raw("  Toggle selected namespace"),
        ]),
        Line::from(vec![
            Span::styled("e", Style::default().fg(tailwind::YELLOW.c400).add_modifier(Modifier::BOLD)),
            Span::raw("         Expand all namespaces"),
        ]),
        Line::from(vec![
            Span::styled("E", Style::default().fg(tailwind::YELLOW.c400).add_modifier(Modifier::BOLD)),
            Span::raw("         Collapse all namespaces"),
        ]),
        Line::from(""),
        Line::from(Span::styled("── Other ──", Style::default().fg(tailwind::CYAN.c400))),
        Line::from(vec![
            Span::styled("/", Style::default().fg(tailwind::YELLOW.c400).add_modifier(Modifier::BOLD)),
            Span::raw("         Filter pods"),
        ]),
        Line::from(vec![
            Span::styled("?", Style::default().fg(tailwind::YELLOW.c400).add_modifier(Modifier::BOLD)),
            Span::raw("         Toggle this help"),
        ]),
        Line::from(vec![
            Span::styled("q", Style::default().fg(tailwind::YELLOW.c400).add_modifier(Modifier::BOLD)),
            Span::raw("         Quit"),
        ]),
    ];

    let popup_width = 44;
    let popup_height = help_lines.len() as u16 + 2; // +2 for borders

    let popup_area = centered_rect(popup_width, popup_height, area);

    f.render_widget(Clear, popup_area);
    f.render_widget(
        Paragraph::new(help_lines)
            .block(
                Block::new()
                    .title(" Help ")
                    .title_bottom(
                        Line::from(" Press ? to close ")
                            .style(Style::default().fg(tailwind::GRAY.c500))
                            .centered(),
                    )
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(tailwind::CYAN.c400)),
            )
            .style(Style::default().fg(tailwind::GRAY.c200)),
        popup_area,
    );
}

fn centered_rect(width: u16, height: u16, area: Rect) -> Rect {
    let x = area.x + (area.width.saturating_sub(width)) / 2;
    let y = area.y + (area.height.saturating_sub(height)) / 2;
    Rect::new(x, y, width.min(area.width), height.min(area.height))
}

/* ---------------------------------------------------------------------- */
/*  SMALL UTILS                                                           */
/* ---------------------------------------------------------------------- */

fn column_split(card: Rect, name_w: u16) -> [Rect; 4] {
    Layout::horizontal([
        Constraint::Length(name_w),
        Constraint::Percentage(50),
        Constraint::Length(COL_GAP),
        Constraint::Percentage(50),
    ])
    .areas(card)
}

fn draw_header(f: &mut Frame, hdr_area: Rect, name_w: u16) {
    let [name_col, cpu_col, _gap, mem_col] = column_split(hdr_area, name_w);
    let style = Style::default()
        .fg(tailwind::GRAY.c300)
        .add_modifier(Modifier::BOLD);
    f.render_widget(Paragraph::new("NAME").style(style), name_col);
    f.render_widget(
        Paragraph::new("CPU")
            .alignment(Alignment::Center)
            .style(style),
        cpu_col,
    );
    f.render_widget(
        Paragraph::new("MEM")
            .alignment(Alignment::Center)
            .style(style),
        mem_col,
    );
}
