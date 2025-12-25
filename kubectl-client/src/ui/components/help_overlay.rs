//! Inline context-aware help bar component.

use ratatui::{
    prelude::*,
    style::{palette::tailwind, Color, Modifier, Style},
    text::{Line, Span},
    widgets::Paragraph,
    Frame,
};

/// Draws a context-aware inline help bar at the given area.
///
/// Takes a slice of (key, description) tuples and renders them as:
/// `key:desc │ key:desc │ ...`
pub fn draw_help_bar(f: &mut Frame, area: Rect, hints: &[(&str, &str)]) {
    let mut spans = Vec::new();
    let separator = Span::styled(" │ ", Style::default().fg(tailwind::GRAY.c600));

    for (i, (key, desc)) in hints.iter().enumerate() {
        if i > 0 {
            spans.push(separator.clone());
        }
        spans.push(Span::styled(
            *key,
            Style::default()
                .fg(Color::Magenta)
                .add_modifier(Modifier::BOLD),
        ));
        spans.push(Span::styled(
            format!(":{}", desc),
            Style::default().fg(tailwind::GRAY.c400),
        ));
    }

    f.render_widget(
        Paragraph::new(Line::from(spans)).alignment(Alignment::Left),
        area,
    );
}

/// Help hints for TopView Nodes tab.
pub fn top_nodes_hints() -> Vec<(&'static str, &'static str)> {
    vec![("Tab", "to pods"), ("q", "quit")]
}

/// Help hints for TopView Pods tab.
pub fn top_pods_hints() -> Vec<(&'static str, &'static str)> {
    vec![
        ("Tab", "to nodes"),
        ("K", "details"),
        ("za", "fold"),
        ("zM", "fold all"),
        ("zR", "fold open all"),
        ("q", "quit"),
    ]
}

/// Help hints for Overview view.
pub fn overview_hints() -> Vec<(&'static str, &'static str)> {
    vec![("q", "quit")]
}
