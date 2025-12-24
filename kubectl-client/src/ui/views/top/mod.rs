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
        components::{draw_header, draw_help_overlay, make_gauge, top_view_help_items, GaugeStyle},
        layout::column_split,
        views::View,
    },
};

pub use state::{InputMode, TopViewState};

/// Height constants for layout calculations.
const CARD_HEIGHT: u16 = 1; // One line per node
const GRAPH_H: u16 = 3; // Graph rows (with label overlay)
const ROW_H: u16 = GRAPH_H + 1; // +1 blank spacer row
const NS_HEADER_H: u16 = 1; // Namespace header row

/// Top view displaying nodes and pods metrics.
#[derive(Default)]
pub struct TopView {
    state: TopViewState,
}

impl View for TopView {
    fn set_cursor_line(&mut self, _line: u16) -> bool {
        // Neovim handles cursor position natively
        false
    }

    fn on_event(&mut self, ev: &Event) -> bool {
        match ev {
            Event::Key(k) => {
                // Help overlay intercepts most keys
                if self.state.is_help_visible() {
                    match k.code {
                        KeyCode::Char('?') | KeyCode::Esc => {
                            self.state.toggle_help();
                            return true;
                        }
                        _ => return true, // Consume all keys when help is open
                    }
                }

                // Filter prompt handles its own keys
                self.state.handle_key(*k);
                let is_filter_key = matches!(
                    k.code,
                    KeyCode::Char('/') | KeyCode::Esc | KeyCode::Enter | KeyCode::Backspace
                );
                if is_filter_key || self.state.input_mode == InputMode::Filtering {
                    return true;
                }

                // Navigation and actions
                match k.code {
                    KeyCode::Char('?') => {
                        self.state.toggle_help();
                        true
                    }
                    KeyCode::Tab => {
                        self.state.next_tab();
                        true
                    }
                    _ => false,
                }
            }
            Event::Mouse(_) => false,
            _ => false,
        }
    }

    fn draw(&mut self, f: &mut Frame, area: Rect) {
        draw(f, area, &mut self.state);
    }

    fn content_height(&self) -> Option<u16> {
        // Calculate maximum possible height based on current data
        // This is fast: just count items, no filtering/grouping needed
        const HEADER_LINES: u16 = 3;

        if self.state.selected_tab == 0 {
            // Nodes: 1 line each
            let count = node_stats().lock().map(|g| g.len()).unwrap_or(0) as u16;
            Some(HEADER_LINES + count * CARD_HEIGHT)
        } else {
            // Pods: worst case is all expanded
            // Each unique namespace = 1 line, each pod = ROW_H lines
            let (ns_count, pod_count) = pod_stats()
                .lock()
                .map(|g| {
                    let mut namespaces = std::collections::HashSet::new();
                    for key in g.keys() {
                        namespaces.insert(&key.0); // key is (namespace, name) tuple
                    }
                    (namespaces.len(), g.len())
                })
                .unwrap_or((0, 0));
            Some(HEADER_LINES + ns_count as u16 + pod_count as u16 * ROW_H)
        }
    }
}

/// Main draw function for the Top view.
fn draw(f: &mut Frame, area: Rect, state: &mut TopViewState) {
    // Snapshot data
    let pod_snapshot: Vec<PodStat> = pod_stats()
        .lock()
        .map(|guard| guard.values().cloned().collect())
        .unwrap_or_default();
    let node_snapshot: Vec<NodeStat> = node_stats()
        .lock()
        .map(|guard| guard.clone())
        .unwrap_or_default();

    // Layout: tabs - blank line - header - body
    let [tabs_area, _blank_area, hdr_area, body_area] = Layout::vertical([
        Constraint::Length(1),
        Constraint::Length(1), // Blank separator
        Constraint::Length(1),
        Constraint::Min(0),
    ])
    .areas(area);

    // Tab bar
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

    // Render appropriate tab content
    if state.selected_tab == 0 {
        draw_nodes_tab(f, hdr_area, body_area, &node_snapshot);
    } else {
        draw_pods_tab(f, hdr_area, body_area, &pod_snapshot, &state.filter);
    }

    // Help overlay
    if state.show_help {
        draw_help_overlay(f, area, "Help", &top_view_help_items(), Some("Press ? to close"));
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
    filter: &str,
) {
    use crate::ui::layout::calculate_name_width;

    // Filter pods
    let filtered: Vec<&PodStat> = if filter.is_empty() {
        pods.iter().collect()
    } else {
        let needle = filter.to_lowercase();
        pods.iter()
            .filter(|p| {
                let hay = format!("{}/{}", p.namespace, p.name).to_lowercase();
                hay.contains(&needle)
            })
            .collect()
    };

    // Group by namespace
    let mut grouped: BTreeMap<&str, Vec<&PodStat>> = BTreeMap::new();
    for p in &filtered {
        grouped.entry(p.namespace.as_str()).or_default().push(p);
    }

    // Column widths
    let title_w = calculate_name_width(filtered.iter().map(|p| p.name.as_str()), 3); // +3 for indent

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
            let graph_rect = Rect {
                x: body_area.x,
                y,
                width: body_area.width,
                height: GRAPH_H,
            };

            let [name_col, cpu_col, _gap, mem_col] = column_split(graph_rect, title_w);

            // Name column (indented)
            f.render_widget(
                Block::new()
                    .borders(Borders::NONE)
                    .title(format!("  {}", p.name))
                    .fg(tailwind::BLUE.c400),
                name_col,
            );

            // Sparklines with current value labels
            let cpu_data = deque_to_vec(&p.cpu_history, cpu_col.width.saturating_sub(8));
            let mem_data = deque_to_vec(&p.mem_history, mem_col.width.saturating_sub(10));

            // CPU sparkline with value label
            let cpu_label = format!("{}m", p.cpu_m);
            f.render_widget(
                Sparkline::default()
                    .data(&cpu_data)
                    .style(Style::default().fg(tailwind::GREEN.c500)),
                Rect {
                    width: cpu_col.width.saturating_sub(cpu_label.len() as u16 + 1),
                    ..cpu_col
                },
            );
            f.render_widget(
                Paragraph::new(cpu_label)
                    .alignment(Alignment::Right)
                    .style(
                        Style::default()
                            .fg(tailwind::GREEN.c300)
                            .add_modifier(Modifier::BOLD),
                    ),
                cpu_col,
            );

            // MEM sparkline with value label
            let mem_label = format!("{} MiB", p.mem_mi);
            f.render_widget(
                Sparkline::default()
                    .data(&mem_data)
                    .style(Style::default().fg(tailwind::ORANGE.c400)),
                Rect {
                    width: mem_col.width.saturating_sub(mem_label.len() as u16 + 1),
                    ..mem_col
                },
            );
            f.render_widget(
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
}

/// Converts a VecDeque to a Vec, taking at most `max_w` elements.
fn deque_to_vec(data: &std::collections::VecDeque<u64>, max_w: u16) -> Vec<u64> {
    let w = max_w as usize;
    data.iter().take(w).copied().collect()
}
