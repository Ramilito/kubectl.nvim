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
    f.render_widget(
        Sparkline::default()
            .data(data)
            .style(Style::default().fg(sparkline_color)),
        Rect {
            width: area.width.saturating_sub(LABEL_WIDTH),
            ..area
        },
    );

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

/// Top view displaying nodes and pods metrics.
pub struct TopView {
    state: TopViewState,
    /// Cached pod stats to avoid cloning HashMap on every render
    pod_cache: Vec<PodStat>,
    /// Cached node stats to avoid cloning Vec on every render
    node_cache: Vec<NodeStat>,
}

impl Default for TopView {
    fn default() -> Self {
        Self {
            state: TopViewState::default(),
            pod_cache: Vec::new(),
            node_cache: Vec::new(),
        }
    }
}

impl TopView {
    /// Refreshes the cached pod and node snapshots from the shared state.
    /// Called once per render cycle to avoid repeated HashMap clones.
    /// Also makes VecDeques contiguous for zero-copy slice access during rendering.
    fn refresh_caches(&mut self) {
        self.pod_cache = pod_stats()
            .lock()
            .map(|guard| guard.values().cloned().collect())
            .unwrap_or_default();

        // Make history VecDeques contiguous for efficient slice access
        for pod in &mut self.pod_cache {
            pod.cpu_history.make_contiguous();
            pod.mem_history.make_contiguous();
        }

        self.node_cache = node_stats()
            .lock()
            .map(|guard| guard.clone())
            .unwrap_or_default();
    }

    /// Finds the pod at the current cursor line and toggles its expansion.
    fn toggle_pod_at_cursor(&mut self) {
        // Header offset: help_bar(1) + tabs(1) + blank(1) + header(1) = 4 lines
        const HEADER_OFFSET: u16 = 4;

        let cursor = self.state.cursor_line;
        if cursor < HEADER_OFFSET {
            return;
        }

        let body_line = cursor - HEADER_OFFSET;

        // Group by namespace using cached data (same as in draw)
        let mut grouped: BTreeMap<&str, Vec<&PodStat>> = BTreeMap::new();
        for p in &self.pod_cache {
            grouped.entry(p.namespace.as_str()).or_default().push(p);
        }

        // Walk through layout to find pod at cursor line
        let mut y: u16 = 0;
        for (ns, ns_pods) in grouped.iter() {
            // Namespace header
            if body_line == y {
                // Cursor on namespace header, ignore
                return;
            }
            y += NS_HEADER_H;

            // Pods in this namespace
            for p in ns_pods {
                let pod_height = if self.state.is_expanded(&p.namespace, &p.name) {
                    EXPANDED_H
                } else {
                    ROW_H
                };

                if body_line >= y && body_line < y + pod_height {
                    // Found the pod - toggle expansion
                    self.state
                        .toggle_expansion(ns.to_string(), p.name.clone());
                    return;
                }
                y += pod_height;
            }

            // Separator line
            y += 1;
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
        // Refresh caches once per render cycle
        self.refresh_caches();
        draw_with_data(f, area, &mut self.state, &self.pod_cache, &self.node_cache);
    }

    fn content_height(&self) -> Option<u16> {
        // Calculate height based on cached data and expansion state
        // help_bar(1) + tabs(1) + blank(1) + header(1) = 4 lines
        const HEADER_LINES: u16 = 4;

        if self.state.selected_tab == 0 {
            // Nodes: 1 line each (use cached data)
            Some(HEADER_LINES + self.node_cache.len() as u16 * CARD_HEIGHT)
        } else {
            // Pods: account for expanded pod if any (use cached data)
            let mut grouped: BTreeMap<&str, Vec<&PodStat>> = BTreeMap::new();
            for p in &self.pod_cache {
                grouped.entry(p.namespace.as_str()).or_default().push(p);
            }

            let mut height = HEADER_LINES;
            for (_, ns_pods) in grouped.iter() {
                height += NS_HEADER_H; // Namespace header
                for p in ns_pods {
                    if self.state.is_expanded(&p.namespace, &p.name) {
                        height += EXPANDED_H;
                    } else {
                        height += ROW_H;
                    }
                }
                height += 1; // Separator
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
    pods: &[PodStat],
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
        draw_pods_tab(f, hdr_area, body_area, pods, state);
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
/// Renders directly to frame - Neovim handles scrolling and folding natively.
fn draw_pods_tab(
    f: &mut Frame,
    hdr_area: Rect,
    body_area: Rect,
    pods: &[PodStat],
    state: &TopViewState,
) {
    use crate::ui::layout::calculate_name_width;

    // Group by namespace
    let mut grouped: BTreeMap<&str, Vec<&PodStat>> = BTreeMap::new();
    for p in pods {
        grouped.entry(p.namespace.as_str()).or_default().push(p);
    }

    // Column widths
    let title_w = calculate_name_width(pods.iter().map(|p| p.name.as_str()), 3); // +3 for indent

    // Header row
    draw_header(f, hdr_area, title_w);

    // Render grouped pods directly to frame (no ScrollView)
    // Always render all content - Neovim handles folding natively
    let mut y: u16 = body_area.y;

    for (ns, ns_pods) in grouped.iter() {
        let ns_total_cpu: u64 = ns_pods.iter().map(|p| p.cpu_m).sum();
        let ns_total_mem: u64 = ns_pods.iter().map(|p| p.mem_mi).sum();

        // Namespace header (no indent - serves as fold marker)
        let ns_header_rect = Rect {
            x: body_area.x,
            y,
            width: body_area.width,
            height: NS_HEADER_H,
        };

        let ns_title = format!(
            "{} ({}) - CPU: {}m | MEM: {} MiB",
            ns,
            ns_pods.len(),
            ns_total_cpu,
            ns_total_mem
        );

        let ns_style = Style::default()
            .fg(colors::SUCCESS)
            .add_modifier(Modifier::BOLD);

        f.render_widget(Paragraph::new(ns_title).style(ns_style), ns_header_rect);
        y += NS_HEADER_H;

        // Render pods in namespace
        for p in ns_pods {
            let is_expanded = state.is_expanded(&p.namespace, &p.name);
            let pod_height = if is_expanded { EXPANDED_H } else { GRAPH_H };

            let graph_rect = Rect {
                x: body_area.x,
                y,
                width: body_area.width,
                height: pod_height,
            };

            if is_expanded {
                draw_expanded_pod(f, graph_rect, p, title_w);
            } else {
                draw_compact_pod(f, graph_rect, p, title_w);
            }

            y += if is_expanded { EXPANDED_H } else { ROW_H };
        }

        // Add separator line after namespace group
        let sep_rect = Rect {
            x: body_area.x,
            y,
            width: body_area.width,
            height: 1,
        };
        let separator = "─".repeat(body_area.width as usize);
        f.render_widget(
            Paragraph::new(separator).style(Style::default().fg(Color::DarkGray)),
            sep_rect,
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

    // Sparklines (rows 1 to n-1)
    let sparkline_y = area.y + 1;
    let sparkline_height = area.height.saturating_sub(2); // Row 0 for header, last row for time

    let cpu_data = history_slice(&p.cpu_history, cpu_col.width);
    let mem_data = history_slice(&p.mem_history, mem_col.width);

    f.render_widget(
        Sparkline::default()
            .data(cpu_data)
            .style(Style::default().fg(colors::INFO)),
        Rect {
            x: cpu_col.x,
            y: sparkline_y,
            width: cpu_col.width,
            height: sparkline_height,
        },
    );

    f.render_widget(
        Sparkline::default()
            .data(mem_data)
            .style(Style::default().fg(colors::WARNING)),
        Rect {
            x: mem_col.x,
            y: sparkline_y,
            width: mem_col.width,
            height: sparkline_height,
        },
    );

    // Time markers on bottom row of sparkline area
    let time_y = area.y + area.height - 1;
    let history_len = p.cpu_history.len();

    // Format time markers for each column's width separately
    let cpu_time = format_time_markers(history_len, cpu_col.width);
    let mem_time = format_time_markers(history_len, mem_col.width);

    f.render_widget(
        Paragraph::new(cpu_time).style(Style::default().fg(Color::Gray)),
        Rect { x: cpu_col.x, y: time_y, width: cpu_col.width, height: 1 },
    );
    f.render_widget(
        Paragraph::new(mem_time).style(Style::default().fg(Color::Gray)),
        Rect { x: mem_col.x, y: time_y, width: mem_col.width, height: 1 },
    );
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
