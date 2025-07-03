//! Six-pane OVERVIEW screen for the dashboard.
//
// Layout
// ┌────────────┬──────────────┬──────────────┐
// │  info       │   nodes      │  namespace   │
// ├────────────┼──────────────┼──────────────┤
// │  top-cpu    │   top-mem    │   events     │
// └────────────┴──────────────┴──────────────┘

use ratatui::{
    layout::{Constraint, Layout, Margin, Rect},
    prelude::*,
    style::palette::tailwind,
    text::{Line, Span},
    widgets::{Block, Borders, Gauge},
};
use tui_widgets::scrollview::{ScrollView, ScrollViewState};

use crate::metrics::nodes::NodeStat;

#[derive(Clone, Copy)]
#[derive(Default)]
enum Pane {
    Info,
    #[default]
    Nodes,
    Namespace,
    TopCpu,
    TopMem,
    Events,
}

impl Pane {
    fn next(self) -> Self {
        use Pane::*;
        match self {
            Info => Nodes,
            Nodes => Namespace,
            Namespace => TopCpu,
            TopCpu => TopMem,
            TopMem => Events,
            Events => Info,
        }
    }
    fn prev(self) -> Self {
        use Pane::*;
        match self {
            Info => Events,
            Events => TopMem,
            TopMem => TopCpu,
            TopCpu => Namespace,
            Namespace => Nodes,
            Nodes => Info,
        }
    }
}

/*────────────────────── Public state object ───────────────────────────*/

#[derive(Default)]
pub struct OverviewState {
    focus: Pane, // which pane currently receives scroll input?
    pub info: ScrollViewState,
    pub nodes: ScrollViewState,
    pub namespace: ScrollViewState,
    pub top_cpu: ScrollViewState,
    pub top_mem: ScrollViewState,
    pub events: ScrollViewState,
}

impl OverviewState {
    /* focus cycling (Tab / Shift-Tab) */
    pub fn focus_next(&mut self) {
        self.focus = self.focus.next();
    }
    pub fn focus_prev(&mut self) {
        self.focus = self.focus.prev();
    }

    /* thin wrappers so caller doesn’t care which pane has focus */
    pub fn scroll_down(&mut self) {
        self.focus_mut().scroll_down();
    }
    pub fn scroll_up(&mut self) {
        self.focus_mut().scroll_up();
    }
    pub fn scroll_page_down(&mut self) {
        self.focus_mut().scroll_page_down();
    }
    pub fn scroll_page_up(&mut self) {
        self.focus_mut().scroll_page_up();
    }

    fn focus_mut(&mut self) -> &mut ScrollViewState {
        match self.focus {
            Pane::Info => &mut self.info,
            Pane::Nodes => &mut self.nodes,
            Pane::Namespace => &mut self.namespace,
            Pane::TopCpu => &mut self.top_cpu,
            Pane::TopMem => &mut self.top_mem,
            Pane::Events => &mut self.events,
        }
    }
}

/*────────────────────── TOP-LEVEL DRAW FUNCTION ───────────────────────*/

pub fn draw(f: &mut Frame, stats: &[NodeStat], area: Rect, st: &mut OverviewState) {
    /*────────────── split outer rect: 2 rows × 3 cols ──────────────*/
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

    /*─────────────── data prep (top-N lists etc.) ──────────────────*/
    let mut by_cpu = stats.to_vec();
    by_cpu.sort_by(|a, b| b.cpu_pct.total_cmp(&a.cpu_pct));

    let mut by_mem = stats.to_vec();
    by_mem.sort_by(|a, b| b.mem_pct.total_cmp(&a.mem_pct));

    // demo placeholders – replace with real data later
    let namespaces: Vec<Line> = ["default", "kube-system", "monitoring"]
        .iter()
        .map(|s| Line::from(*s))
        .collect();
    let events: Vec<Line> = (1..=20)
        .map(|i| Line::from(format!("event #{i} happened …")))
        .collect();

    /*────────────────────── TOP ROW ───────────────────────────────*/
    draw_text_list(
        f,
        cols_top[0],
        " Info ",
        &[
            Line::from(format!("Nodes: {}", stats.len())),
            Line::from("TAB / Shift-TAB – cycle focus"),
            Line::from("↑/↓, PgUp/PgDn  – scroll pane"),
            Line::from("q – quit"),
        ],
        &mut st.info,
        Color::Blue,
    );

    draw_nodes_table(f, cols_top[1], " Nodes ", stats, &mut st.nodes);

    draw_text_list(
        f,
        cols_top[2],
        " Namespaces ",
        &namespaces,
        &mut st.namespace,
        Color::Magenta,
    );

    /*────────────────────── BOTTOM ROW ────────────────────────────*/
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

/*──────────────────── helpers ──────────────────────────────────────────*/

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

    // widest name for neat columns
    let max_name = stats
        .iter()
        .map(|n| Line::from(n.name.clone()).width() as u16 + 1)
        .max()
        .unwrap_or(1)
        .min(inner.width / 2);

    let make_gauge = |lbl: &str, pct: f64, col: Color| {
        Gauge::default()
            .gauge_style(Style::default().fg(col).bg(tailwind::GRAY.c800))
            .label(format!("{lbl}: {}", pct.round() as u16))
            .use_unicode(true)
            .percent(pct.clamp(0.0, 100.0) as u16)
    };

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
        sv.render_widget(make_gauge("CPU", n.cpu_pct, tailwind::GREEN.c500), cols[1]);
        sv.render_widget(
            make_gauge("MEM", n.mem_pct, tailwind::EMERALD.c400),
            cols[2],
        );
    }

    f.render_stateful_widget(sv, inner, sv_state);
}
