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
    style::{palette::tailwind, Color, Modifier, Style},
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
    fn refresh_caches(&mut self) {
        self.pod_cache = pod_stats()
            .lock()
            .map(|guard| guard.values().cloned().collect())
            .unwrap_or_default();
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
                .fg(tailwind::BLUE.c400),
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
            .fg(tailwind::CYAN.c400)
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
            .fg(tailwind::BLUE.c400),
        name_col,
    );

    // Sparklines with current value and delta
    let label_width = 12u16;
    let cpu_data = deque_to_vec(&p.cpu_history, cpu_col.width.saturating_sub(label_width));
    let mem_data = deque_to_vec(&p.mem_history, mem_col.width.saturating_sub(label_width));
    let cpu_delta = calc_delta(p.cpu_m, &p.cpu_history);
    let mem_delta = calc_delta(p.mem_mi, &p.mem_history);

    // CPU sparkline
    f.render_widget(
        Sparkline::default()
            .data(&cpu_data)
            .style(Style::default().fg(tailwind::GREEN.c500)),
        Rect {
            width: cpu_col.width.saturating_sub(label_width),
            ..cpu_col
        },
    );

    // Label area for current value and delta (right side, doesn't overlap sparkline)
    let cpu_label_area = Rect {
        x: cpu_col.x + cpu_col.width.saturating_sub(label_width),
        y: cpu_col.y,
        width: label_width.min(cpu_col.width),
        height: 1,
    };

    // CPU current value
    let cpu_label = format!("{}m", p.cpu_m);
    f.render_widget(
        Paragraph::new(cpu_label)
            .alignment(Alignment::Right)
            .style(
                Style::default()
                    .fg(tailwind::GREEN.c300)
                    .add_modifier(Modifier::BOLD),
            ),
        cpu_label_area,
    );

    // CPU delta line
    if let Some((delta, is_up)) = cpu_delta {
        if delta > 0 {
            let delta_label = if is_up {
                format!("↑{}m", delta)
            } else {
                format!("↓{}m", delta)
            };
            f.render_widget(
                Paragraph::new(delta_label)
                    .alignment(Alignment::Right)
                    .style(Style::default().fg(tailwind::GRAY.c500)),
                Rect {
                    y: cpu_label_area.y + 1,
                    ..cpu_label_area
                },
            );
        }
    }

    // MEM sparkline
    f.render_widget(
        Sparkline::default()
            .data(&mem_data)
            .style(Style::default().fg(tailwind::ORANGE.c400)),
        Rect {
            width: mem_col.width.saturating_sub(label_width),
            ..mem_col
        },
    );

    // Label area for MEM current value and delta (right side, doesn't overlap sparkline)
    let mem_label_area = Rect {
        x: mem_col.x + mem_col.width.saturating_sub(label_width),
        y: mem_col.y,
        width: label_width.min(mem_col.width),
        height: 1,
    };

    // MEM current value
    let mem_label = format!("{} MiB", p.mem_mi);
    f.render_widget(
        Paragraph::new(mem_label)
            .alignment(Alignment::Right)
            .style(
                Style::default()
                    .fg(tailwind::ORANGE.c300)
                    .add_modifier(Modifier::BOLD),
            ),
        mem_label_area,
    );

    // MEM delta line
    if let Some((delta, is_up)) = mem_delta {
        if delta > 0 {
            let delta_label = if is_up {
                format!("↑{} MiB", delta)
            } else {
                format!("↓{} MiB", delta)
            };
            f.render_widget(
                Paragraph::new(delta_label)
                    .alignment(Alignment::Right)
                    .style(Style::default().fg(tailwind::GRAY.c500)),
                Rect {
                    y: mem_label_area.y + 1,
                    ..mem_label_area
                },
            );
        }
    }
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
            .style(Style::default().fg(tailwind::BLUE.c300).add_modifier(Modifier::BOLD)),
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

    let cpu_data = deque_to_vec(&p.cpu_history, cpu_col.width);
    let mem_data = deque_to_vec(&p.mem_history, mem_col.width);

    f.render_widget(
        Sparkline::default()
            .data(&cpu_data)
            .style(Style::default().fg(tailwind::GREEN.c500)),
        Rect {
            x: cpu_col.x,
            y: sparkline_y,
            width: cpu_col.width,
            height: sparkline_height,
        },
    );

    f.render_widget(
        Sparkline::default()
            .data(&mem_data)
            .style(Style::default().fg(tailwind::ORANGE.c400)),
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
                tailwind::RED.c400
            } else if pct > 70 {
                tailwind::YELLOW.c400
            } else {
                tailwind::GREEN.c400
            }
        }
        _ => tailwind::GRAY.c300,
    }
}

/// Formats time markers for the expanded sparkline view as a visual timeline.
/// Shows actual collected data range with "now" always at the right.
fn format_time_markers(data_points: usize, width: u16) -> String {
    let total_seconds = data_points * 15;
    let w = width as usize;

    if w < 10 {
        return "now".to_string();
    }

    // Build the timeline base
    let mut result: Vec<char> = vec!['─'; w];

    // Always show "now" marker at the right with a bullet point
    let now_label = "●now";
    let now_pos = w.saturating_sub(now_label.chars().count());
    for (i, c) in now_label.chars().enumerate() {
        if now_pos + i < w {
            result[now_pos + i] = c;
        }
    }

    // Format the start time based on how much data we have
    let start_label = if total_seconds == 0 {
        "○".to_string() // Empty circle - no history yet
    } else if total_seconds < 60 {
        format!("{}s", total_seconds)
    } else {
        let minutes = total_seconds / 60;
        format!("{}m", minutes)
    };

    // Place start label at the left
    for (i, c) in start_label.chars().enumerate() {
        if i < w.saturating_sub(now_label.chars().count() + 2) {
            result[i] = c;
        }
    }

    // Add middle marker if we have enough space and time
    let total_minutes = total_seconds / 60;
    if total_minutes >= 2 && w > 30 {
        let mid_label = format!("{}m", total_minutes / 2);
        let mid_pos = w / 2 - mid_label.chars().count() / 2;

        // Only place if it doesn't overlap with start or end
        if mid_pos > start_label.chars().count() + 2
            && mid_pos + mid_label.chars().count() + 2 < now_pos
        {
            // Add tick marks
            if mid_pos > 0 {
                result[mid_pos - 1] = '┤';
            }
            for (i, c) in mid_label.chars().enumerate() {
                result[mid_pos + i] = c;
            }
            let end = mid_pos + mid_label.chars().count();
            if end < w {
                result[end] = '├';
            }
        }
    }

    result.into_iter().collect()
}

/// Converts a VecDeque to a Vec, taking at most `max_w` elements.
/// Reverses the order so oldest is first (left) and newest is last (right).
fn deque_to_vec(data: &std::collections::VecDeque<u64>, max_w: u16) -> Vec<u64> {
    let w = max_w as usize;
    let mut v: Vec<u64> = data.iter().take(w).copied().collect();
    v.reverse();
    v
}

/// Calculate delta from previous value in history.
/// Returns (delta, is_increase) or None if not enough history.
fn calc_delta(current: u64, history: &std::collections::VecDeque<u64>) -> Option<(u64, bool)> {
    // history[0] is current, history[1] is previous sample
    if history.len() < 2 {
        return None;
    }
    let prev = history.get(1)?;
    if current >= *prev {
        Some((current - *prev, true))
    } else {
        Some((*prev - current, false))
    }
}
