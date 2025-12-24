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
mod state;

use crossterm::event::{Event, KeyCode, MouseEventKind};
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
        components::{draw_help_overlay, make_gauge, overview_help_items, GaugeStyle},
        events::{handle_scroll_key, Scrollable},
        views::View,
    },
};

use data::{fetch_cluster_stats, fetch_events, fetch_namespaces};

pub use state::{OverviewState, Pane, PaneState};

/// Overview view displaying a 6-pane cluster dashboard.
#[derive(Default)]
pub struct OverviewView {
    state: OverviewState,
}

impl View for OverviewView {
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

                match k.code {
                    KeyCode::Char('?') => {
                        self.state.toggle_help();
                        true
                    }
                    KeyCode::Tab => {
                        self.state.focus_next();
                        true
                    }
                    KeyCode::BackTab => {
                        self.state.focus_prev();
                        true
                    }
                    other => handle_scroll_key(&mut self.state, other),
                }
            }
            Event::Mouse(m) => match m.kind {
                MouseEventKind::ScrollDown => {
                    self.state.scroll_down();
                    true
                }
                MouseEventKind::ScrollUp => {
                    self.state.scroll_up();
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

/// Main draw function for the Overview view.
fn draw(f: &mut Frame, area: Rect, st: &mut OverviewState) {
    // Split into 2 rows × 3 columns
    let rows =
        Layout::vertical([Constraint::Percentage(60), Constraint::Percentage(40)]).split(area);

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

    // Update item counts
    st.info.set_item_count(info_lines.len());
    st.nodes.set_item_count(node_snapshot.len());
    st.namespace.set_item_count(namespaces.len());
    st.top_cpu.set_item_count(by_cpu.len().min(30));
    st.top_mem.set_item_count(by_mem.len().min(30));
    st.events.set_item_count(events.len());

    // Evaluate focus state before borrowing pane states mutably
    let focus_info = st.is_focused(Pane::Info);
    let focus_nodes = st.is_focused(Pane::Nodes);
    let focus_namespace = st.is_focused(Pane::Namespace);
    let focus_top_cpu = st.is_focused(Pane::TopCpu);
    let focus_top_mem = st.is_focused(Pane::TopMem);
    let focus_events = st.is_focused(Pane::Events);

    // Top row
    draw_text_list(
        f,
        cols_top[0],
        " Info ",
        &info_lines,
        &mut st.info,
        Color::Blue,
        focus_info,
    );

    draw_nodes_table(
        f,
        cols_top[1],
        " Nodes ",
        &node_snapshot,
        &mut st.nodes,
        focus_nodes,
    );

    draw_text_list(
        f,
        cols_top[2],
        " Namespaces ",
        &namespaces,
        &mut st.namespace,
        Color::Magenta,
        focus_namespace,
    );

    // Bottom row
    draw_nodes_table(
        f,
        cols_bot[0],
        " Top-CPU ",
        &by_cpu[..by_cpu.len().min(30)],
        &mut st.top_cpu,
        focus_top_cpu,
    );

    draw_nodes_table(
        f,
        cols_bot[1],
        " Top-MEM ",
        &by_mem[..by_mem.len().min(30)],
        &mut st.top_mem,
        focus_top_mem,
    );

    draw_text_list(
        f,
        cols_bot[2],
        " Events ",
        &events,
        &mut st.events,
        Color::Yellow,
        focus_events,
    );

    // Help overlay
    if st.show_help {
        draw_help_overlay(f, area, "Help", &overview_help_items(), Some("Press ? to close"));
    }
}

/// Draws a scrollable list of text lines with selection.
fn draw_text_list(
    f: &mut Frame,
    area: Rect,
    title: &str,
    lines: &[Line],
    pane_state: &mut PaneState,
    accent: Color,
    is_focused: bool,
) {
    // Border style changes based on focus
    let border_style = if is_focused {
        Style::default()
            .fg(tailwind::YELLOW.c400)
            .add_modifier(Modifier::BOLD)
    } else {
        Style::default().fg(accent).add_modifier(Modifier::BOLD)
    };

    let border = Block::default()
        .title(title)
        .borders(Borders::ALL)
        .border_style(border_style);
    f.render_widget(border, area);

    let inner = area.inner(Margin {
        horizontal: 1,
        vertical: 1,
    });

    let mut sv = ScrollView::new(Size::new(inner.width, lines.len() as u16));

    for (i, l) in lines.iter().enumerate() {
        let is_selected = is_focused && i == pane_state.selected;
        let style = if is_selected {
            Style::default()
                .bg(tailwind::GRAY.c700)
                .add_modifier(Modifier::BOLD)
        } else {
            Style::default()
        };

        // Create a styled line
        let styled_line = if is_selected {
            Line::from(Span::styled(format!("{}", l), style))
        } else {
            l.clone()
        };

        sv.render_widget(
            styled_line,
            Rect {
                x: 0,
                y: i as u16,
                width: inner.width,
                height: 1,
            },
        );
    }

    f.render_stateful_widget(sv, inner, &mut pane_state.scroll);
}

/// Draws a scrollable table of node statistics with selection.
fn draw_nodes_table(
    f: &mut Frame,
    area: Rect,
    title: &str,
    stats: &[NodeStat],
    pane_state: &mut PaneState,
    is_focused: bool,
) {
    // Border style changes based on focus
    let border_style = if is_focused {
        Style::default()
            .fg(tailwind::YELLOW.c400)
            .add_modifier(Modifier::BOLD)
    } else {
        Style::default()
            .fg(Color::Cyan)
            .add_modifier(Modifier::BOLD)
    };

    let border = Block::default()
        .title(title)
        .borders(Borders::ALL)
        .border_style(border_style);
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
        let is_selected = is_focused && row == pane_state.selected;

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

        // Name style with selection highlight
        let name_style = if is_selected {
            Style::default()
                .fg(tailwind::YELLOW.c300)
                .bg(tailwind::GRAY.c700)
                .add_modifier(Modifier::BOLD)
        } else {
            Style::default()
                .fg(tailwind::BLUE.c400)
                .add_modifier(Modifier::BOLD)
        };

        sv.render_widget(Span::styled(n.name.clone(), name_style), cols[0]);
        sv.render_widget(make_gauge("CPU", n.cpu_pct, GaugeStyle::Cpu), cols[1]);
        sv.render_widget(
            make_gauge("MEM", n.mem_pct, GaugeStyle::Custom(tailwind::EMERALD.c400)),
            cols[2],
        );
    }

    f.render_stateful_widget(sv, inner, &mut pane_state.scroll);
}
