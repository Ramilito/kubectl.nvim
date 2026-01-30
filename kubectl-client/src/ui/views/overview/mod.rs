//! Overview view - Six-pane cluster dashboard.
//!
//! Layout:
//! ```text
//! ┌────────────┬──────────────┬──────────────┐
//! │   Info     │    Nodes     │  Namespace   │  (60%)
//! ├────────────┼──────────────┼──────────────┤
//! │  Top-CPU   │   Top-MEM    │   Events     │  (40%)
//! └────────────┴──────────────┴──────────────┘
//! ```

mod data;

use crossterm::event::Event;
use ratatui::{
    layout::{Constraint, Layout, Margin, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders},
    Frame,
};

use crate::{
    metrics::{nodes::NodeStat, pods::PodStat},
    node_stats, pod_stats,
    ui::{
        components::{draw_help_bar, make_gauge, overview_hints, GaugeStyle},
        views::View,
    },
};

use data::{fetch_cluster_stats, fetch_events, fetch_namespaces};

use crate::ui::colors;

/// Border overhead for each panel (top + bottom border)
const PANEL_BORDER: u16 = 2;
/// Fixed height for info panel (3 lines)
const INFO_LINES: u16 = 3;
/// Fixed height for pod panels (top 10)
const POD_LINES: u16 = 15;

/// Overview view displaying a 6-pane cluster dashboard.
pub struct OverviewView {
    /// Cached node count
    node_count: usize,
    /// Cached namespace count
    namespace_count: usize,
    /// Cached event count
    event_count: usize,
    /// Whether cache needs refresh
    cache_dirty: bool,
}

impl Default for OverviewView {
    fn default() -> Self {
        Self {
            node_count: 0,
            namespace_count: 0,
            event_count: 0,
            cache_dirty: true,
        }
    }
}

impl OverviewView {
    /// Refresh cached counts from live data
    fn refresh_cache(&mut self) {
        if !self.cache_dirty {
            return;
        }

        self.node_count = node_stats()
            .lock()
            .map(|g| g.len())
            .unwrap_or(0);

        self.namespace_count = fetch_namespaces().len();
        self.event_count = fetch_events().len();
        self.cache_dirty = false;
    }

    /// Calculate height needed for top row (max of Info, Nodes, Namespaces)
    fn top_row_height(&self) -> u16 {
        let info_h = INFO_LINES + PANEL_BORDER;
        let nodes_h = self.node_count as u16 + PANEL_BORDER;
        let ns_h = self.namespace_count as u16 + PANEL_BORDER;
        info_h.max(nodes_h).max(ns_h)
    }

    /// Calculate height needed for bottom row (max of Top-CPU, Top-MEM, Events)
    fn bottom_row_height(&self) -> u16 {
        let pods_h = POD_LINES + PANEL_BORDER;
        // Events take 2 lines each (header + message)
        let events_h = (self.event_count * 2) as u16 + PANEL_BORDER;
        pods_h.max(events_h)
    }
}

impl View for OverviewView {
    fn on_event(&mut self, _ev: &Event) -> bool {
        false
    }

    fn draw(&mut self, f: &mut Frame, area: Rect) {
        self.refresh_cache();
        draw(f, area, self.top_row_height(), self.bottom_row_height());
    }

    fn content_height(&self) -> Option<u16> {
        // Get live counts for accurate height calculation
        let node_count = node_stats()
            .lock()
            .map(|g| g.len())
            .unwrap_or(self.node_count);
        let namespace_count = fetch_namespaces().len();
        let event_count = fetch_events().len();

        let top_h = (INFO_LINES + PANEL_BORDER)
            .max(node_count as u16 + PANEL_BORDER)
            .max(namespace_count as u16 + PANEL_BORDER);

        // Events take 2 lines each (header + message)
        let event_lines = (event_count * 2) as u16;
        let bot_h = (POD_LINES + PANEL_BORDER)
            .max(event_lines + PANEL_BORDER);

        // 1 for help bar + top row + bottom row
        Some(1 + top_h + bot_h)
    }

    fn on_metrics_update(&mut self) {
        self.cache_dirty = true;
    }
}

/// Main draw function for the Overview view.
fn draw(f: &mut Frame, area: Rect, top_row_h: u16, bot_row_h: u16) {
    // Layout: help bar at top, then 2 rows × 3 columns
    let [help_area, content_area] = Layout::vertical([
        Constraint::Length(1), // Help bar
        Constraint::Min(0),    // Rest for content
    ])
    .areas(area);

    // Draw help bar
    draw_help_bar(f, help_area, &overview_hints());

    // Split content into 2 rows with calculated heights
    let rows = Layout::vertical([
        Constraint::Length(top_row_h),
        Constraint::Length(bot_row_h),
    ])
    .split(content_area);

    let cols_top = Layout::horizontal([
        Constraint::Percentage(33),
        Constraint::Percentage(34),
        Constraint::Percentage(33),
    ])
    .split(rows[0]);

    let cols_bot = Layout::horizontal([
        Constraint::Percentage(33),
        Constraint::Percentage(34),
        Constraint::Percentage(33),
    ])
    .split(rows[1]);

    // Snapshot node data (convert HashMap values to Vec)
    let node_snapshot: Vec<NodeStat> = {
        node_stats()
            .lock()
            .map(|guard| guard.values().cloned().collect())
            .unwrap_or_default()
    };

    // Pre-calculate stats before sorting consumes the vectors
    let total_nodes = node_snapshot.len();
    let ready_nodes = node_snapshot.iter().filter(|n| n.status == "Ready").count();

    // Sort nodes by memory for the Nodes panel
    let mut by_mem = node_snapshot;
    by_mem.sort_by(|a, b| b.mem_pct.total_cmp(&a.mem_pct));

    // Snapshot pod data for Top-CPU/Top-MEM panels
    let pod_snapshot: Vec<PodStat> = {
        pod_stats()
            .read()
            .map(|guard| guard.values().cloned().collect())
            .unwrap_or_default()
    };

    // Sort pods by CPU (millicores, descending)
    let mut pods_by_cpu = pod_snapshot.clone();
    pods_by_cpu.sort_by(|a, b| b.cpu_m.cmp(&a.cpu_m));

    // Sort pods by memory (MiB, descending)
    let mut pods_by_mem = pod_snapshot;
    pods_by_mem.sort_by(|a, b| b.mem_mi.cmp(&a.mem_mi));

    // Fetch real namespace data
    let ns_data = fetch_namespaces();
    let namespaces: Vec<Line> = ns_data
        .iter()
        .map(|ns| {
            let status_color = match ns.status.as_str() {
                "Active" => colors::INFO,
                "Terminating" => colors::ERROR,
                _ => colors::GRAY,
            };
            Line::from(vec![
                Span::styled(&ns.name, Style::default().fg(colors::HEADER)),
                Span::raw(" "),
                Span::styled(&ns.status, Style::default().fg(status_color)),
            ])
        })
        .collect();

    // Fetch real event data - each event becomes 2 lines (header + message)
    let event_data = fetch_events();
    let events: Vec<Line> = event_data
        .iter()
        .flat_map(|ev| {
            let type_color = match ev.type_.as_str() {
                "Warning" => colors::DEBUG, // yellow
                "Error" => colors::ERROR,
                _ => colors::INFO,
            };
            let count_str = if ev.count > 1 {
                format!("({}x) ", ev.count)
            } else {
                String::new()
            };
            // Format namespace (truncate if needed)
            let ns = if ev.namespace.len() > 12 {
                format!("{}…", &ev.namespace[..11])
            } else {
                ev.namespace.clone()
            };
            // Line 1: Header with type, count, object, reason
            let header = Line::from(vec![
                Span::styled(&ev.type_, Style::default().fg(type_color)),
                Span::raw(" "),
                Span::styled(count_str, Style::default().fg(colors::GRAY)),
                Span::styled(format!("{}/", ns), Style::default().fg(colors::GRAY)),
                Span::styled(&ev.object, Style::default().fg(colors::HEADER)),
                Span::raw(" "),
                Span::styled(&ev.reason, Style::default().fg(colors::SUCCESS).add_modifier(Modifier::BOLD)),
            ]);
            // Line 2: Message (indented)
            let message = Line::from(vec![
                Span::raw("  "),
                Span::styled(&ev.message, Style::default().fg(colors::GRAY)),
            ]);
            vec![header, message]
        })
        .collect();

    // Fetch cluster stats (using pre-calculated values)
    let stats = fetch_cluster_stats(total_nodes, ready_nodes);

    let info_lines = vec![
        Line::from(vec![
            Span::styled("Nodes: ", Style::default().fg(colors::GRAY)),
            Span::styled(
                format!("{}/{}", stats.ready_node_count, stats.node_count),
                Style::default().fg(colors::INFO).add_modifier(Modifier::BOLD),
            ),
            Span::raw(" ready"),
        ]),
        Line::from(vec![
            Span::styled("Pods: ", Style::default().fg(colors::GRAY)),
            Span::styled(
                stats.pod_count.to_string(),
                Style::default().fg(colors::HEADER).add_modifier(Modifier::BOLD),
            ),
        ]),
        Line::from(vec![
            Span::styled("Namespaces: ", Style::default().fg(colors::GRAY)),
            Span::styled(
                stats.namespace_count.to_string(),
                Style::default().fg(colors::PENDING).add_modifier(Modifier::BOLD),
            ),
        ]),
    ];

    // Top row (use by_mem for Nodes since order doesn't matter and avoids extra clone)
    draw_text_list(f, cols_top[0], " Info ", &info_lines, Color::Blue);
    draw_nodes_table(f, cols_top[1], " Nodes ", &by_mem);
    draw_text_list(f, cols_top[2], " Namespaces ", &namespaces, Color::Magenta);

    // Bottom row - show top pods by CPU and memory
    draw_pods_table(f, cols_bot[0], " Top-CPU ", &pods_by_cpu, true);
    draw_pods_table(f, cols_bot[1], " Top-MEM ", &pods_by_mem, false);
    draw_text_list(f, cols_bot[2], " Events ", &events, Color::Yellow);
}

/// Draws a list of text lines.
fn draw_text_list(f: &mut Frame, area: Rect, title: &str, lines: &[Line], accent: Color) {
    let border = Block::default()
        .title(title)
        .borders(Borders::ALL)
        .border_style(Style::default().fg(accent).add_modifier(Modifier::BOLD));
    f.render_widget(border, area);

    let inner = area.inner(Margin {
        horizontal: 1,
        vertical: 1,
    });

    for (i, l) in lines.iter().enumerate() {
        if i as u16 >= inner.height {
            break;
        }
        f.render_widget(
            l.clone(),
            Rect {
                x: inner.x,
                y: inner.y + i as u16,
                width: inner.width,
                height: 1,
            },
        );
    }
}

/// Draws a table of node statistics. Renders directly without ScrollView.
fn draw_nodes_table(f: &mut Frame, area: Rect, title: &str, stats: &[NodeStat]) {
    let border = Block::default()
        .title(title)
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD));
    f.render_widget(border, area);

    let inner = area.inner(Margin {
        horizontal: 1,
        vertical: 1,
    });

    // Calculate widest name for neat columns
    let max_name = stats
        .iter()
        .map(|n| Line::from(n.name.clone()).width() as u16 + 1)
        .max()
        .unwrap_or(1)
        .min(inner.width / 2);

    for (row, n) in stats.iter().enumerate() {
        if row as u16 >= inner.height {
            break;
        }

        let row_rect = Rect {
            x: inner.x,
            y: inner.y + row as u16,
            width: inner.width,
            height: 1,
        };

        let cols = Layout::horizontal([
            Constraint::Length(max_name),
            Constraint::Percentage(50),
            Constraint::Percentage(50),
        ])
        .split(row_rect);

        let name_style = Style::default()
            .fg(colors::HEADER)
            .add_modifier(Modifier::BOLD);

        f.render_widget(Span::styled(n.name.clone(), name_style), cols[0]);
        f.render_widget(make_gauge("CPU", n.cpu_pct, GaugeStyle::Cpu), cols[1]);
        f.render_widget(make_gauge("MEM", n.mem_pct, GaugeStyle::Memory), cols[2]);
    }
}

/// Draws a table of top pod statistics (CPU or memory focused).
/// Shows just numbers, no gauges. Renders directly without ScrollView.
fn draw_pods_table(f: &mut Frame, area: Rect, title: &str, stats: &[PodStat], show_cpu: bool) {
    let border = Block::default()
        .title(title)
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD));
    f.render_widget(border, area);

    let inner = area.inner(Margin {
        horizontal: 1,
        vertical: 1,
    });

    // Limit to top 15
    let display_stats = &stats[..stats.len().min(15)];

    // Calculate widest name for neat columns (namespace/name format)
    let max_name = display_stats
        .iter()
        .map(|p| {
            let display_name = format!("{}/{}", p.namespace, p.name);
            Line::from(display_name).width() as u16 + 1
        })
        .max()
        .unwrap_or(1)
        .min(inner.width.saturating_sub(12)); // Leave room for value column

    for (row, p) in display_stats.iter().enumerate() {
        if row as u16 >= inner.height {
            break;
        }

        let row_rect = Rect {
            x: inner.x,
            y: inner.y + row as u16,
            width: inner.width,
            height: 1,
        };

        let cols = Layout::horizontal([
            Constraint::Length(max_name),
            Constraint::Min(10),
        ])
        .split(row_rect);

        let name_style = Style::default()
            .fg(colors::HEADER)
            .add_modifier(Modifier::BOLD);

        // Format: namespace/name (truncated if needed)
        let display_name = format!("{}/{}", p.namespace, p.name);
        let truncated_name = if display_name.len() > max_name as usize {
            format!("{}…", &display_name[..max_name.saturating_sub(1) as usize])
        } else {
            display_name
        };

        f.render_widget(Span::styled(truncated_name, name_style), cols[0]);

        // Show just the value as text
        let value_text = if show_cpu {
            format!("{}m", p.cpu_m)
        } else {
            format!("{}Mi", p.mem_mi)
        };

        f.render_widget(
            Span::styled(value_text, Style::default().fg(colors::INFO)),
            cols[1],
        );
    }
}
