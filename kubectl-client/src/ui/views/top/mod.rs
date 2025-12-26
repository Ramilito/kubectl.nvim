//! Top view - Nodes and Pods metrics display.
//!
//! Shows two tabs:
//! - Nodes: Gauge-based display of CPU/MEM usage per node
//! - Pods: Sparkline graphs grouped by namespace with filtering

mod state;

use crossterm::event::{Event, KeyCode};
use ratatui::{
    layout::{Alignment, Constraint, Layout, Rect},
    prelude::*,
    style::{Color, Modifier, Style},
    text::Line,
    widgets::{Block, Borders, Paragraph, Sparkline, Tabs},
    Frame,
};
use std::collections::BTreeMap;

use crate::{
    metrics::{nodes::NodeStat, pods::PodStat},
    node_stats, pod_stats,
    ui::{
        components::{draw_header, draw_help_bar, make_gauge, top_nodes_hints, top_pods_hints, GaugeStyle},
        layout::column_split,
        views::View,
    },
};

pub use state::TopViewState;

/// Height constants for layout calculations.
const CARD_HEIGHT: u16 = 1; // One line per node
const GRAPH_H: u16 = 3; // Graph rows (with label overlay)
const ROW_H: u16 = GRAPH_H + 1; // +1 blank spacer row
const NS_HEADER_H: u16 = 1; // Namespace header row

/// Height for expanded pod view.
const EXPANDED_H: u16 = 10;

/// Label width for sparkline value/delta display.
const LABEL_WIDTH: u16 = 12;

use crate::ui::colors;

/// Renders a sparkline with value label and optional delta indicator.
///
/// Layout: [sparkline graph][label area]
///         [              ][delta     ]
fn render_sparkline_with_label(
    f: &mut Frame,
    area: Rect,
    data: &[u64],
    current: u64,
    delta: Option<(u64, bool)>,
    sparkline_color: Color,
    label_color: Color,
    unit: &str,
) {
    // Sparkline (left portion)
    render_sparkline(f, Rect { width: area.width.saturating_sub(LABEL_WIDTH), ..area }, data, sparkline_color);

    // Label area (right portion)
    let label_area = Rect {
        x: area.x + area.width.saturating_sub(LABEL_WIDTH),
        y: area.y,
        width: LABEL_WIDTH.min(area.width),
        height: 1,
    };

    // Current value
    f.render_widget(
        Paragraph::new(format!("{}{}", current, unit))
            .alignment(Alignment::Right)
            .style(Style::default().fg(label_color).add_modifier(Modifier::BOLD)),
        label_area,
    );

    // Delta indicator
    if let Some((delta_val, is_up)) = delta {
        if delta_val > 0 {
            let arrow = if is_up { "↑" } else { "↓" };
            f.render_widget(
                Paragraph::new(format!("{}{}{}", arrow, delta_val, unit))
                    .alignment(Alignment::Right)
                    .style(Style::default().fg(colors::GRAY)),
                Rect { y: label_area.y + 1, ..label_area },
            );
        }
    }
}

/// Renders a basic sparkline widget.
#[inline]
fn render_sparkline(f: &mut Frame, area: Rect, data: &[u64], color: Color) {
    f.render_widget(
        Sparkline::default()
            .data(data)
            .style(Style::default().fg(color)),
        area,
    );
}

/// Pods grouped by namespace (sorted by namespace name).
type GroupedPods = BTreeMap<String, Vec<PodStat>>;

/// Top view displaying nodes and pods metrics.
pub struct TopView {
    state: TopViewState,
    /// Cached pods grouped by namespace
    grouped_pods: GroupedPods,
    /// Cached node stats
    node_cache: Vec<NodeStat>,
}

impl Default for TopView {
    fn default() -> Self {
        Self {
            state: TopViewState::default(),
            grouped_pods: BTreeMap::new(),
            node_cache: Vec::new(),
        }
    }
}

impl TopView {
    /// Refreshes caches from shared state. Called once per render cycle.
    fn refresh_caches(&mut self) {
        // Group pods by namespace
        self.grouped_pods.clear();
        if let Ok(guard) = pod_stats().lock() {
            for mut pod in guard.values().cloned() {
                pod.cpu_history.make_contiguous();
                pod.mem_history.make_contiguous();
                self.grouped_pods
                    .entry(pod.namespace.clone())
                    .or_default()
                    .push(pod);
            }
        }

        self.node_cache = node_stats()
            .lock()
            .map(|guard| guard.clone())
            .unwrap_or_default();
    }

    /// Finds the pod at the current cursor line and toggles its expansion.
    fn toggle_pod_at_cursor(&mut self) {
        const HEADER_OFFSET: u16 = 4; // help_bar + tabs + blank + header

        let cursor = self.state.cursor_line;
        if cursor < HEADER_OFFSET {
            return;
        }

        let body_line = cursor - HEADER_OFFSET;
        let mut y: u16 = 0;

        for (ns, ns_pods) in &self.grouped_pods {
            if body_line == y {
                return; // Cursor on namespace header
            }
            y += NS_HEADER_H;

            for p in ns_pods {
                let pod_h = if self.state.is_expanded(ns, &p.name) { EXPANDED_H } else { ROW_H };
                if body_line >= y && body_line < y + pod_h {
                    self.state.toggle_expansion(ns.clone(), p.name.clone());
                    return;
                }
                y += pod_h;
            }
            y += 1; // Separator
        }
    }
}

impl View for TopView {
    fn set_cursor_line(&mut self, line: u16) -> bool {
        self.state.set_cursor(line);
        true
    }

    fn on_event(&mut self, ev: &Event) -> bool {
        match ev {
            Event::Key(k) => match k.code {
                KeyCode::Tab => {
                    self.state.next_tab();
                    true
                }
                KeyCode::Char('K') => {
                    // K - expand/collapse pod details
                    if self.state.selected_tab == 1 {
                        self.toggle_pod_at_cursor();
                        true
                    } else {
                        false
                    }
                }
                _ => false,
            },
            Event::Mouse(_) => false,
            _ => false,
        }
    }

    fn draw(&mut self, f: &mut Frame, area: Rect) {
        self.refresh_caches();
        draw_with_data(f, area, &mut self.state, &self.grouped_pods, &self.node_cache);
    }

    fn content_height(&self) -> Option<u16> {
        const HEADER_LINES: u16 = 4; // help_bar + tabs + blank + header

        if self.state.selected_tab == 0 {
            Some(HEADER_LINES + self.node_cache.len() as u16 * CARD_HEIGHT)
        } else {
            let mut height = HEADER_LINES;
            for (ns, ns_pods) in &self.grouped_pods {
                height += NS_HEADER_H + 1; // header + separator
                for p in ns_pods {
                    height += if self.state.is_expanded(ns, &p.name) { EXPANDED_H } else { ROW_H };
                }
            }
            Some(height)
        }
    }
}

/// Main draw function for the Top view using pre-cached data.
fn draw_with_data(
    f: &mut Frame,
    area: Rect,
    state: &mut TopViewState,
    grouped_pods: &GroupedPods,
    nodes: &[NodeStat],
) {
    // Layout: help bar - tabs - blank line - header - body
    let [help_area, tabs_area, _blank_area, hdr_area, body_area] = Layout::vertical([
        Constraint::Length(1), // Help bar
        Constraint::Length(1),
        Constraint::Length(1), // Blank separator
        Constraint::Length(1),
        Constraint::Min(0),
    ])
    .areas(area);

    // Context-aware help bar
    let hints = if state.selected_tab == 0 {
        top_nodes_hints()
    } else {
        top_pods_hints()
    };
    draw_help_bar(f, help_area, &hints);

    // Tab bar
    let tabs = Tabs::new(vec![Line::from("Nodes"), Line::from("Pods")])
        .select(state.selected_tab)
        .style(Style::default().fg(Color::White))
        .highlight_style(
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        );
    f.render_widget(tabs, tabs_area);

    // Render appropriate tab content
    if state.selected_tab == 0 {
        draw_nodes_tab(f, hdr_area, body_area, nodes);
    } else {
        draw_pods_tab(f, hdr_area, body_area, grouped_pods, state);
    }
}

/// Draws the Nodes tab content.
/// Renders directly to frame - Neovim handles scrolling natively.
fn draw_nodes_tab(
    f: &mut Frame,
    hdr_area: Rect,
    body_area: Rect,
    nodes: &[NodeStat],
) {
    use crate::ui::layout::calculate_name_width;

    let title_w = calculate_name_width(nodes.iter().map(|n| n.name.as_str()), 1);

    // Header row
    draw_header(f, hdr_area, title_w);

    // Render nodes directly (no ScrollView - let Neovim handle scrolling)
    for (idx, node) in nodes.iter().enumerate() {
        let y = body_area.y + idx as u16 * CARD_HEIGHT;

        // Skip if outside visible area (frame will clip anyway)
        if y >= body_area.y + body_area.height {
            continue;
        }

        let card = Rect {
            x: body_area.x,
            y,
            width: body_area.width,
            height: CARD_HEIGHT,
        };

        let [name_col, cpu_col, _gap, mem_col] = column_split(card, title_w);

        f.render_widget(
            Block::new()
                .borders(Borders::NONE)
                .title(node.name.clone())
                .fg(colors::HEADER),
            name_col,
        );
        f.render_widget(make_gauge("CPU", node.cpu_pct, GaugeStyle::Cpu), cpu_col);
        f.render_widget(make_gauge("MEM", node.mem_pct, GaugeStyle::Memory), mem_col);
    }
}

/// Draws the Pods tab content.
fn draw_pods_tab(
    f: &mut Frame,
    hdr_area: Rect,
    body_area: Rect,
    grouped: &GroupedPods,
    state: &TopViewState,
) {
    use crate::ui::layout::calculate_name_width;

    // Calculate max name width across all pods
    let title_w = calculate_name_width(
        grouped.values().flatten().map(|p| p.name.as_str()),
        3, // +3 for indent
    );

    draw_header(f, hdr_area, title_w);

    let mut y = body_area.y;
    let separator = "─".repeat(body_area.width as usize);

    for (ns, ns_pods) in grouped {
        // Namespace header with totals
        let cpu_total: u64 = ns_pods.iter().map(|p| p.cpu_m).sum();
        let mem_total: u64 = ns_pods.iter().map(|p| p.mem_mi).sum();

        f.render_widget(
            Paragraph::new(format!("{} ({}) - CPU: {}m | MEM: {} MiB", ns, ns_pods.len(), cpu_total, mem_total))
                .style(Style::default().fg(colors::SUCCESS).add_modifier(Modifier::BOLD)),
            Rect { x: body_area.x, y, width: body_area.width, height: 1 },
        );
        y += NS_HEADER_H;

        // Pods
        for p in ns_pods {
            let expanded = state.is_expanded(ns, &p.name);
            let h = if expanded { EXPANDED_H } else { GRAPH_H };
            let rect = Rect { x: body_area.x, y, width: body_area.width, height: h };

            if expanded {
                draw_expanded_pod(f, rect, p, title_w);
            } else {
                draw_compact_pod(f, rect, p, title_w);
            }
            y += if expanded { EXPANDED_H } else { ROW_H };
        }

        // Separator
        f.render_widget(
            Paragraph::new(separator.clone()).style(Style::default().fg(Color::DarkGray)),
            Rect { x: body_area.x, y, width: body_area.width, height: 1 },
        );
        y += 1;
    }
}

/// Draws a compact (non-expanded) pod row.
fn draw_compact_pod(f: &mut Frame, area: Rect, p: &PodStat, title_w: u16) {
    let [name_col, cpu_col, _gap, mem_col] = column_split(area, title_w);

    // Name column (indented)
    f.render_widget(
        Block::new()
            .borders(Borders::NONE)
            .title(format!("  {}", p.name))
            .fg(colors::HEADER),
        name_col,
    );

    // CPU sparkline with label
    let cpu_data = history_slice(&p.cpu_history, cpu_col.width.saturating_sub(LABEL_WIDTH));
    let cpu_delta = calc_delta(p.cpu_m, &p.cpu_history);
    render_sparkline_with_label(
        f, cpu_col, cpu_data, p.cpu_m, cpu_delta,
        colors::INFO, colors::INFO, "m",
    );

    // MEM sparkline with label
    let mem_data = history_slice(&p.mem_history, mem_col.width.saturating_sub(LABEL_WIDTH));
    let mem_delta = calc_delta(p.mem_mi, &p.mem_history);
    render_sparkline_with_label(
        f, mem_col, mem_data, p.mem_mi, mem_delta,
        colors::WARNING, colors::WARNING, " MiB",
    );
}

/// Draws an expanded pod view with larger sparklines and resource info.
fn draw_expanded_pod(f: &mut Frame, area: Rect, p: &PodStat, title_w: u16) {
    // Layout (using same row 0 as compact view to avoid shifting):
    // Row 0: ▼ pod-name    CPU: current/limit (%)    MEM: current/limit (%)
    // Rows 1-(n-1): Sparklines
    // Row n-1: Time markers (inside sparkline area)

    let [name_col, cpu_col, _gap, mem_col] = column_split(area, title_w);

    // Row 0: Pod name with expansion indicator
    f.render_widget(
        Paragraph::new(format!("▼ {}", p.name))
            .style(Style::default().fg(colors::HEADER).add_modifier(Modifier::BOLD)),
        Rect { height: 1, ..name_col },
    );

    // Row 0 (right side): Resource summary
    let cpu_summary = format_resource_summary_short(p.cpu_m, p.cpu_limit_m, "m");
    let mem_summary = format_resource_summary_short(p.mem_mi, p.mem_limit_mi, " MiB");

    let cpu_color = get_limit_color(p.cpu_m, p.cpu_limit_m);
    let mem_color = get_limit_color(p.mem_mi, p.mem_limit_mi);

    f.render_widget(
        Paragraph::new(cpu_summary).style(Style::default().fg(cpu_color)),
        Rect { x: cpu_col.x, y: area.y, width: cpu_col.width, height: 1 },
    );
    f.render_widget(
        Paragraph::new(mem_summary).style(Style::default().fg(mem_color)),
        Rect { x: mem_col.x, y: area.y, width: mem_col.width, height: 1 },
    );

    // Sparklines (rows 1 to n-2) + time markers (row n-1)
    let sparkline_y = area.y + 1;
    let sparkline_h = area.height.saturating_sub(2); // Row 0 header, last row time
    let time_y = area.y + area.height - 1;

    // Helper to render sparkline + time markers for a column
    let render_col = |f: &mut Frame, col: Rect, history: &std::collections::VecDeque<u64>, color: Color| {
        render_sparkline(
            f,
            Rect { x: col.x, y: sparkline_y, width: col.width, height: sparkline_h },
            history_slice(history, col.width),
            color,
        );
        f.render_widget(
            Paragraph::new(format_time_markers(history.len(), col.width))
                .style(Style::default().fg(Color::Gray)),
            Rect { x: col.x, y: time_y, width: col.width, height: 1 },
        );
    };

    render_col(f, cpu_col, &p.cpu_history, colors::INFO);
    render_col(f, mem_col, &p.mem_history, colors::WARNING);
}

/// Short format for resource summary: "250m/500m (50%)" or just "250m"
fn format_resource_summary_short(current: u64, limit: Option<u64>, unit: &str) -> String {
    match limit {
        Some(lim) if lim > 0 => {
            let pct = (current as f64 / lim as f64 * 100.0) as u64;
            format!("{}{}/{}{} ({}%)", current, unit, lim, unit, pct)
        }
        _ => format!("{}{}", current, unit),
    }
}

/// Returns color based on current usage vs limit percentage.
fn get_limit_color(current: u64, limit: Option<u64>) -> Color {
    match limit {
        Some(lim) if lim > 0 => {
            let pct = (current as f64 / lim as f64 * 100.0) as u64;
            if pct > 90 {
                colors::ERROR
            } else if pct > 70 {
                colors::DEBUG // yellow
            } else {
                colors::INFO
            }
        }
        _ => colors::GRAY,
    }
}

/// Formats time markers for the expanded sparkline view.
/// Shows time range from start to "now" with optional middle marker.
fn format_time_markers(data_points: usize, width: u16) -> String {
    let w = width as usize;
    if w < 10 {
        return "now".to_string();
    }

    let total_secs = data_points * 15;
    let start = if total_secs == 0 {
        "○".to_string()
    } else if total_secs < 60 {
        format!("{}s", total_secs)
    } else {
        format!("{}m", total_secs / 60)
    };

    // Calculate middle section width and fill with timeline chars
    let end = "●now";
    let mid_width = w.saturating_sub(start.len() + end.len());

    // Add middle time marker if space permits (>30 chars and >2 min of data)
    let mid = if mid_width > 10 && total_secs >= 120 {
        let half_mins = total_secs / 120;
        format!("┤{}m├", half_mins)
    } else {
        String::new()
    };

    // Build: start + padding + mid + padding + end
    let pad_total = mid_width.saturating_sub(mid.len());
    let pad_left = pad_total / 2;
    let pad_right = pad_total - pad_left;

    format!(
        "{}{}{}{}{}",
        start,
        "─".repeat(pad_left),
        mid,
        "─".repeat(pad_right),
        end
    )
}

/// Returns a slice of the history for sparkline rendering.
/// Takes the most recent `max_w` elements (oldest-first order for display).
/// Zero-copy: returns a slice directly from the contiguous VecDeque.
#[inline]
fn history_slice(data: &std::collections::VecDeque<u64>, max_w: u16) -> &[u64] {
    // VecDeque is made contiguous in refresh_caches(), so first slice has all data
    let (slice, _) = data.as_slices();
    // Take the last max_w elements (most recent data points)
    let start = slice.len().saturating_sub(max_w as usize);
    &slice[start..]
}

/// Calculate delta from previous value in history.
/// Returns (delta, is_increase) or None if not enough history.
/// History is stored oldest-first, so last element is current, second-to-last is previous.
fn calc_delta(current: u64, history: &std::collections::VecDeque<u64>) -> Option<(u64, bool)> {
    if history.len() < 2 {
        return None;
    }
    // Second-to-last element is the previous sample
    let prev = history.get(history.len() - 2)?;
    if current >= *prev {
        Some((current - *prev, true))
    } else {
        Some((*prev - current, false))
    }
}
