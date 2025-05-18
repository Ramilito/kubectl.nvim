use ratatui::{
    layout::{Constraint, Layout, Margin, Rect},
    prelude::*,
    style::palette::tailwind,
    text::Line,
    widgets::{Block, Borders, Gauge, Padding, Paragraph, Tabs},
};
use tui_widgets::scrollview::{ScrollView, ScrollViewState};

use super::nodes_state::NodeStat;
use super::pods_state::PodStat;

/* ───────────── constants ─────────────────────────────────────────────── */
const CARD_HEIGHT: u16 = 1; // one line per row
const MAX_TITLE_WIDTH: u16 = 40;

/* ───────────── per-view state ────────────────────────────────────────── */
#[derive(Default)]
pub struct TopViewState {
    selected_tab: usize, // 0 = Nodes, 1 = Pods
    node_scroll: ScrollViewState,
    pod_scroll: ScrollViewState,
}

impl TopViewState {
    fn active_scroll(&mut self) -> &mut ScrollViewState {
        if self.selected_tab == 0 {
            &mut self.node_scroll
        } else {
            &mut self.pod_scroll
        }
    }
    /* key helpers (called by outer View impl) */
    pub fn next_tab(&mut self) {
        self.selected_tab = (self.selected_tab + 1) % 2;
    }
    pub fn prev_tab(&mut self) {
        self.selected_tab = if self.selected_tab == 0 { 1 } else { 0 };
    }
    pub fn scroll_down(&mut self) {
        self.active_scroll().scroll_down();
    }
    pub fn scroll_up(&mut self) {
        self.active_scroll().scroll_up();
    }
    pub fn scroll_page_down(&mut self) {
        self.active_scroll().scroll_page_down();
    }
    pub fn scroll_page_up(&mut self) {
        self.active_scroll().scroll_page_up();
    }

    /* compatibility aliases */
    pub fn focus_next(&mut self) {
        self.next_tab();
    }
    pub fn focus_prev(&mut self) {
        self.prev_tab();
    }
}

pub fn draw(
    f: &mut Frame,
    area: Rect,
    state: &mut TopViewState,
    node_stats: &[NodeStat],
    pod_stats: &[PodStat],
) {
    /* outer frame -------------------------------------------------------- */
    let outer = Block::new()
        .title(" Top (live) ")
        .borders(Borders::ALL)
        .border_style(
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        );
    f.render_widget(outer, area);

    /* inner region (padding 1) ------------------------------------------ */
    let inner = area.inner(Margin {
        vertical: 1,
        horizontal: 1,
    });

    /* tab bar + body split ---------------------------------------------- */
    let [tabs_area, body_area] =
        Layout::vertical([Constraint::Length(1), Constraint::Min(0)]).areas(inner);

    /* tab bar ------------------------------------------------------------ */
    let tab_titles = ["Nodes", "Pods"]
        .into_iter()
        .map(Line::from)
        .collect::<Vec<_>>();
    let tabs = Tabs::new(tab_titles)
        .select(state.selected_tab)
        .style(Style::default().fg(Color::White))
        .highlight_style(
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        );
    f.render_widget(tabs, tabs_area);

    /* dataset choice + name-column width -------------------------------- */
    let (rows, title_width): (usize, u16) = if state.selected_tab == 0 {
        let w = node_stats
            .iter()
            .map(|ns| Line::from(ns.name.clone()).width() as u16 + 1)
            .max()
            .unwrap_or(0)
            .clamp(1, MAX_TITLE_WIDTH);
        (node_stats.len(), w)
    } else {
        let w = pod_stats
            .iter()
            .map(|ps| {
                let full = format!("{}/{}", ps.namespace, ps.name);
                Line::from(full).width() as u16 + 1
            })
            .max()
            .unwrap_or(0)
            .clamp(1, MAX_TITLE_WIDTH);
        (pod_stats.len(), w)
    };

    /* scroll-view -------------------------------------------------------- */
    let content_h = rows as u16 * CARD_HEIGHT;
    let mut sv = ScrollView::new(Size::new(body_area.width, content_h));

    /* helper for node gauges -------------------------------------------- */
    let make_gauge = |label: &str, pct: f64, color: Color| {
        Gauge::default()
            .gauge_style(Style::default().fg(color).bg(tailwind::GRAY.c800))
            .label(format!("{label}: {}", pct.round() as u16))
            .use_unicode(true)
            .percent(pct.clamp(0.0, 100.0) as u16)
    };

    /* render rows -------------------------------------------------------- */
    for idx in 0..rows {
        let y = idx as u16 * CARD_HEIGHT;
        let card = Rect {
            x: 0,
            y,
            width: body_area.width,
            height: CARD_HEIGHT,
        };

        let cols = Layout::horizontal([
            Constraint::Length(title_width),
            Constraint::Percentage(50),
            Constraint::Percentage(50),
        ])
        .split(card);

        if state.selected_tab == 0 {
            /* ── Nodes tab: percent gauges ─────────────────────────────── */
            let ns = &node_stats[idx];
            sv.render_widget(
                Block::new()
                    .borders(Borders::NONE)
                    .padding(Padding::vertical(1))
                    .title(ns.name.clone())
                    .fg(tailwind::BLUE.c400),
                cols[0],
            );
            sv.render_widget(make_gauge("CPU", ns.cpu_pct, tailwind::GREEN.c500), cols[1]);
            sv.render_widget(
                make_gauge("MEM", ns.mem_pct, tailwind::EMERALD.c400),
                cols[2],
            );
        } else {
            /* ── Pods tab: absolute numbers ────────────────────────────── */
            let ps = &pod_stats[idx];
            let display = format!("{}/{}", ps.namespace, ps.name);
            sv.render_widget(
                Block::new()
                    .borders(Borders::NONE)
                    .padding(Padding::vertical(1))
                    .title(display)
                    .fg(tailwind::BLUE.c400),
                cols[0],
            );

            let cpu_line = Line::from(format!("CPU: {} m", ps.cpu_m));
            let mem_line = Line::from(format!("MEM: {} Mi", ps.mem_mi));

            sv.render_widget(
                Paragraph::new(cpu_line).style(Style::default().fg(tailwind::GREEN.c500)),
                cols[1],
            );
            sv.render_widget(
                Paragraph::new(mem_line).style(Style::default().fg(tailwind::EMERALD.c400)),
                cols[2],
            );
        }
    }

    /* final paint -------------------------------------------------------- */
    let sv_state = state.active_scroll();
    f.render_stateful_widget(sv, body_area, sv_state);
}
