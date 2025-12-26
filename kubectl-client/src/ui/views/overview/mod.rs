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
    layout::{Constraint, Layout, Margin, Rect, Size},
    style::{palette::tailwind, Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders},
    Frame,
};
use tui_widgets::scrollview::ScrollView;

use crate::{
    metrics::nodes::NodeStat,
    node_stats,
    ui::{
        components::{draw_help_bar, make_gauge, overview_hints, GaugeStyle},
        views::View,
    },
};

use data::{fetch_cluster_stats, fetch_events, fetch_namespaces};

/// Overview view displaying a 6-pane cluster dashboard.
#[derive(Default)]
pub struct OverviewView;

impl View for OverviewView {
    fn on_event(&mut self, _ev: &Event) -> bool {
        false
    }

    fn draw(&mut self, f: &mut Frame, area: Rect) {
        draw(f, area);
    }
}

/// Main draw function for the Overview view.
fn draw(f: &mut Frame, area: Rect) {
    // Layout: help bar at top, then 2 rows × 3 columns
    let [help_area, content_area] = Layout::vertical([
        Constraint::Length(1), // Help bar
        Constraint::Min(0),    // Rest for content
    ])
    .areas(area);

    // Draw help bar
    draw_help_bar(f, help_area, &overview_hints());

    // Split content into 2 rows × 3 columns
    let rows =
        Layout::vertical([Constraint::Percentage(60), Constraint::Percentage(40)]).split(content_area);

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

    // Snapshot data
    let node_snapshot: Vec<NodeStat> = { node_stats().lock().unwrap().clone() };

    // Sort nodes by metrics for top-N lists
    let mut by_cpu = node_snapshot.to_vec();
    by_cpu.sort_by(|a, b| b.cpu_pct.total_cmp(&a.cpu_pct));

    let mut by_mem = node_snapshot.to_vec();
    by_mem.sort_by(|a, b| b.mem_pct.total_cmp(&a.mem_pct));

    // Fetch real namespace data
    let ns_data = fetch_namespaces();
    let namespaces: Vec<Line> = ns_data
        .iter()
        .map(|ns| {
            let status_color = match ns.status.as_str() {
                "Active" => tailwind::GREEN.c400,
                "Terminating" => tailwind::RED.c400,
                _ => tailwind::GRAY.c400,
            };
            Line::from(vec![
                Span::styled(&ns.name, Style::default().fg(tailwind::BLUE.c300)),
                Span::raw(" "),
                Span::styled(&ns.status, Style::default().fg(status_color)),
            ])
        })
        .collect();

    // Fetch real event data
    let event_data = fetch_events();
    let events: Vec<Line> = event_data
        .iter()
        .map(|ev| {
            let type_color = match ev.type_.as_str() {
                "Warning" => tailwind::YELLOW.c400,
                "Error" => tailwind::RED.c400,
                _ => tailwind::GREEN.c400,
            };
            let count_str = if ev.count > 1 {
                format!("({}x) ", ev.count)
            } else {
                String::new()
            };
            // Truncate message if too long
            let msg = if ev.message.len() > 30 {
                format!("{}...", &ev.message[..27])
            } else {
                ev.message.clone()
            };
            // Format namespace (truncate if needed)
            let ns = if ev.namespace.len() > 12 {
                format!("{}…", &ev.namespace[..11])
            } else {
                ev.namespace.clone()
            };
            Line::from(vec![
                Span::styled(&ev.type_, Style::default().fg(type_color)),
                Span::raw(" "),
                Span::styled(count_str, Style::default().fg(tailwind::GRAY.c500)),
                Span::styled(format!("{}/", ns), Style::default().fg(tailwind::GRAY.c400)),
                Span::styled(&ev.object, Style::default().fg(tailwind::BLUE.c300)),
                Span::raw(" "),
                Span::styled(&ev.reason, Style::default().fg(tailwind::CYAN.c300).add_modifier(Modifier::BOLD)),
                Span::raw(": "),
                Span::raw(msg),
            ])
        })
        .collect();

    // Fetch cluster stats
    let ready_nodes = node_snapshot.iter().filter(|n| n.status == "Ready").count();
    let stats = fetch_cluster_stats(node_snapshot.len(), ready_nodes);

    let info_lines = vec![
        Line::from(vec![
            Span::styled("Nodes: ", Style::default().fg(tailwind::GRAY.c400)),
            Span::styled(
                format!("{}/{}", stats.ready_node_count, stats.node_count),
                Style::default().fg(tailwind::GREEN.c400).add_modifier(Modifier::BOLD),
            ),
            Span::raw(" ready"),
        ]),
        Line::from(vec![
            Span::styled("Pods: ", Style::default().fg(tailwind::GRAY.c400)),
            Span::styled(
                stats.pod_count.to_string(),
                Style::default().fg(tailwind::BLUE.c400).add_modifier(Modifier::BOLD),
            ),
        ]),
        Line::from(vec![
            Span::styled("Namespaces: ", Style::default().fg(tailwind::GRAY.c400)),
            Span::styled(
                stats.namespace_count.to_string(),
                Style::default().fg(tailwind::FUCHSIA.c400).add_modifier(Modifier::BOLD),
            ),
        ]),
    ];

    // Top row
    draw_text_list(f, cols_top[0], " Info ", &info_lines, Color::Blue);
    draw_nodes_table(f, cols_top[1], " Nodes ", &node_snapshot);
    draw_text_list(f, cols_top[2], " Namespaces ", &namespaces, Color::Magenta);

    // Bottom row
    draw_nodes_table(f, cols_bot[0], " Top-CPU ", &by_cpu[..by_cpu.len().min(30)]);
    draw_nodes_table(f, cols_bot[1], " Top-MEM ", &by_mem[..by_mem.len().min(30)]);
    draw_text_list(f, cols_bot[2], " Events ", &events, Color::Yellow);
}

/// Draws a scrollable list of text lines.
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

    let mut sv = ScrollView::new(Size::new(inner.width, lines.len() as u16));

    for (i, l) in lines.iter().enumerate() {
        sv.render_widget(
            l.clone(),
            Rect {
                x: 0,
                y: i as u16,
                width: inner.width,
                height: 1,
            },
        );
    }

    f.render_stateful_widget(sv, inner, &mut Default::default());
}

/// Draws a scrollable table of node statistics.
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

    let mut sv = ScrollView::new(Size::new(inner.width, stats.len() as u16));

    for (row, n) in stats.iter().enumerate() {
        let cols = Layout::horizontal([
            Constraint::Length(max_name),
            Constraint::Percentage(50),
            Constraint::Percentage(50),
        ])
        .split(Rect {
            x: 0,
            y: row as u16,
            width: inner.width,
            height: 1,
        });

        let name_style = Style::default()
            .fg(tailwind::BLUE.c400)
            .add_modifier(Modifier::BOLD);

        sv.render_widget(Span::styled(n.name.clone(), name_style), cols[0]);
        sv.render_widget(make_gauge("CPU", n.cpu_pct, GaugeStyle::Cpu), cols[1]);
        sv.render_widget(
            make_gauge("MEM", n.mem_pct, GaugeStyle::Custom(tailwind::EMERALD.c400)),
            cols[2],
        );
    }

    f.render_stateful_widget(sv, inner, &mut Default::default());
}
