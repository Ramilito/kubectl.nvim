//! Top view - Nodes and Pods metrics display.
//!
//! Shows two tabs:
//! - Nodes: Gauge-based display of CPU/MEM usage per node
//! - Pods: Sparkline graphs grouped by namespace with filtering

mod state;

use crossterm::event::{Event, KeyCode, MouseEventKind};
use ratatui::{
    layout::{Alignment, Constraint, Layout, Rect},
    prelude::*,
    style::{palette::tailwind, Color, Modifier, Style},
    text::Line,
    widgets::{Block, Borders, Paragraph, Sparkline, Tabs},
    Frame,
};
use std::collections::BTreeMap;
use tui_widgets::scrollview::ScrollViewState;

use crate::{
    metrics::{nodes::NodeStat, pods::PodStat},
    node_stats, pod_stats,
    ui::{
        components::{draw_header, draw_help_overlay, make_gauge, top_view_help_items, GaugeStyle},
        events::Scrollable,
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
    fn set_cursor_line(&mut self, line: u16) -> bool {
        // Only sync cursor for Pods tab
        if self.state.is_pods_tab() {
            let changed = self.state.set_cursor_line(line);
            tracing::debug!("TopView set_cursor_line({}) -> changed={}", line, changed);
            changed
        } else {
            tracing::debug!("TopView set_cursor_line({}) -> not pods tab", line);
            false
        }
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
                    KeyCode::Char('e') => {
                        self.state.expand_all();
                        true
                    }
                    KeyCode::Char('E') => {
                        self.state.collapse_all();
                        true
                    }
                    // Namespace selection (Pods tab) or scroll (Nodes tab)
                    KeyCode::Char('j') | KeyCode::Down => {
                        if self.state.is_pods_tab() {
                            self.state.select_next_ns();
                        } else {
                            self.state.scroll_down();
                        }
                        true
                    }
                    KeyCode::Char('k') | KeyCode::Up => {
                        if self.state.is_pods_tab() {
                            self.state.select_prev_ns();
                        } else {
                            self.state.scroll_up();
                        }
                        true
                    }
                    // Toggle selected namespace
                    KeyCode::Enter | KeyCode::Char(' ') => {
                        if self.state.is_pods_tab() {
                            self.state.toggle_selected_ns();
                            true
                        } else {
                            false
                        }
                    }
                    // Page scroll
                    KeyCode::PageDown => {
                        self.state.scroll_page_down();
                        true
                    }
                    KeyCode::PageUp => {
                        self.state.scroll_page_up();
                        true
                    }
                    _ => false,
                }
            }
            Event::Mouse(m) => match m.kind {
                MouseEventKind::ScrollDown => {
                    if self.state.is_pods_tab() {
                        self.state.select_next_ns();
                    } else {
                        self.state.scroll_down();
                    }
                    true
                }
                MouseEventKind::ScrollUp => {
                    if self.state.is_pods_tab() {
                        self.state.select_prev_ns();
                    } else {
                        self.state.scroll_up();
                    }
                    true
                }
                _ => false,
            },
            _ => false,
        }
    }

    fn draw(&mut self, f: &mut Frame, area: Rect) {
        draw(f, area, &mut self.state);
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
        draw_nodes_tab(f, hdr_area, body_area, &node_snapshot, &mut state.node_scroll);
    } else {
        draw_pods_tab(f, hdr_area, body_area, &pod_snapshot, state);
    }

    // Help overlay
    if state.show_help {
        draw_help_overlay(f, area, "Help", &top_view_help_items(), Some("Press ? to close"));
    }
}

/// Draws the Nodes tab content.
/// Renders directly to frame without ScrollView for native buffer scrolling.
fn draw_nodes_tab(
    f: &mut Frame,
    hdr_area: Rect,
    body_area: Rect,
    nodes: &[NodeStat],
    _scroll_state: &mut ScrollViewState,
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
/// Renders directly to frame without ScrollView for native buffer scrolling.
fn draw_pods_tab(
    f: &mut Frame,
    hdr_area: Rect,
    body_area: Rect,
    pods: &[PodStat],
    state: &mut TopViewState,
) {
    use crate::ui::layout::calculate_name_width;

    // Filter pods
    let filtered: Vec<&PodStat> = if state.filter.is_empty() {
        pods.iter().collect()
    } else {
        let needle = state.filter.to_lowercase();
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

    // Track known namespaces for collapse_all
    state.update_known_namespaces(grouped.keys().map(|s| s.to_string()));

    // Update ordered namespace list for selection
    let ns_list: Vec<String> = grouped.keys().map(|s| s.to_string()).collect();
    state.update_ns_order(ns_list);

    // Column widths
    let title_w = calculate_name_width(filtered.iter().map(|p| p.name.as_str()), 3); // +3 for indent

    // Header row
    draw_header(f, hdr_area, title_w);

    // Calculate namespace positions for cursor mapping
    let mut ns_positions: Vec<u16> = Vec::new();
    let mut pos: u16 = 0;
    for (ns, ns_pods) in &grouped {
        ns_positions.push(pos);
        pos += NS_HEADER_H;
        if !state.is_namespace_collapsed(ns) {
            pos += ns_pods.len() as u16 * ROW_H;
        }
    }
    state.update_ns_positions(ns_positions);

    // Render grouped pods directly to frame (no ScrollView)
    let mut y: u16 = body_area.y;

    for (ns, ns_pods) in grouped.iter() {
        let is_collapsed = state.is_namespace_collapsed(ns);
        // Use ASCII indicators to avoid multi-byte UTF-8 alignment issues
        let indicator = if is_collapsed { ">" } else { "v" };
        let ns_total_cpu: u64 = ns_pods.iter().map(|p| p.cpu_m).sum();
        let ns_total_mem: u64 = ns_pods.iter().map(|p| p.mem_mi).sum();

        // Namespace header
        let ns_header_rect = Rect {
            x: body_area.x,
            y,
            width: body_area.width,
            height: NS_HEADER_H,
        };

        let ns_title = format!(
            "{} {} ({}) - CPU: {}m | MEM: {} MiB",
            indicator,
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

        if is_collapsed {
            continue;
        }

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
