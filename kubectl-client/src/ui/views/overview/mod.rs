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

mod state;

use crossterm::event::{Event, KeyCode, MouseEventKind};
use ratatui::{
    layout::{Constraint, Layout, Margin, Rect, Size},
    style::{palette::tailwind, Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders},
    Frame,
};
use tui_widgets::scrollview::{ScrollView, ScrollViewState};

use crate::{
    metrics::nodes::NodeStat,
    node_stats,
    ui::{
        components::{make_gauge, GaugeStyle},
        events::{handle_scroll_key, Scrollable},
        views::View,
    },
};

pub use state::OverviewState;

/// Overview view displaying a 6-pane cluster dashboard.
#[derive(Default)]
pub struct OverviewView {
    state: OverviewState,
}

impl View for OverviewView {
    fn on_event(&mut self, ev: &Event) -> bool {
        match ev {
            Event::Key(k) => match k.code {
                KeyCode::Tab => {
                    self.state.focus_next();
                    true
                }
                KeyCode::BackTab => {
                    self.state.focus_prev();
                    true
                }
                other => handle_scroll_key(&mut self.state, other),
            },
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

    // Demo placeholders - replace with real data later
    let namespaces: Vec<Line> = ["default", "kube-system", "monitoring"]
        .iter()
        .map(|s| Line::from(*s))
        .collect();
    let events: Vec<Line> = (1..=20)
        .map(|i| Line::from(format!("event #{i} happened …")))
        .collect();

    // Top row
    draw_text_list(
        f,
        cols_top[0],
        " Info ",
        &[
            Line::from(format!("Nodes: {}", node_snapshot.len())),
            Line::from("TAB / Shift-TAB – cycle focus"),
            Line::from("↑/↓, PgUp/PgDn  – scroll pane"),
            Line::from("q – quit"),
        ],
        &mut st.info,
        Color::Blue,
    );

    draw_nodes_table(f, cols_top[1], " Nodes ", &node_snapshot, &mut st.nodes);

    draw_text_list(
        f,
        cols_top[2],
        " Namespaces ",
        &namespaces,
        &mut st.namespace,
        Color::Magenta,
    );

    // Bottom row
    draw_nodes_table(
        f,
        cols_bot[0],
        " Top-CPU ",
        &by_cpu[..by_cpu.len().min(30)],
        &mut st.top_cpu,
    );

    draw_nodes_table(
        f,
        cols_bot[1],
        " Top-MEM ",
        &by_mem[..by_mem.len().min(30)],
        &mut st.top_mem,
    );

    draw_text_list(
        f,
        cols_bot[2],
        " Events ",
        &events,
        &mut st.events,
        Color::Yellow,
    );
}

/// Draws a scrollable list of text lines.
fn draw_text_list(
    f: &mut Frame,
    area: Rect,
    title: &str,
    lines: &[Line],
    sv_state: &mut ScrollViewState,
    accent: Color,
) {
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

    f.render_stateful_widget(sv, inner, sv_state);
}

/// Draws a scrollable table of node statistics.
fn draw_nodes_table(
    f: &mut Frame,
    area: Rect,
    title: &str,
    stats: &[NodeStat],
    sv_state: &mut ScrollViewState,
) {
    let border = Block::default()
        .title(title)
        .borders(Borders::ALL)
        .border_style(
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        );
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

        sv.render_widget(
            Span::styled(
                n.name.clone(),
                Style::default()
                    .fg(tailwind::BLUE.c400)
                    .add_modifier(Modifier::BOLD),
            ),
            cols[0],
        );
        sv.render_widget(make_gauge("CPU", n.cpu_pct, GaugeStyle::Cpu), cols[1]);
        sv.render_widget(
            make_gauge("MEM", n.mem_pct, GaugeStyle::Custom(tailwind::EMERALD.c400)),
            cols[2],
        );
    }

    f.render_stateful_widget(sv, inner, sv_state);
}
