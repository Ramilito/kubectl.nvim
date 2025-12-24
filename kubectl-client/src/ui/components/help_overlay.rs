//! Modal help overlay component.

use ratatui::{
    prelude::*,
    style::{palette::tailwind, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph},
    Frame,
};

use crate::ui::layout::centered_rect;

/// A single help entry with a key binding and description.
pub struct HelpEntry {
    pub key: &'static str,
    pub description: &'static str,
}

impl HelpEntry {
    pub const fn new(key: &'static str, description: &'static str) -> Self {
        Self { key, description }
    }
}

/// Section separator for help entries.
pub enum HelpItem {
    Entry(HelpEntry),
    Section(&'static str),
    Blank,
}

/// Draws a centered help overlay with the given entries.
///
/// # Arguments
/// * `f` - Frame to render to
/// * `area` - Full screen area (popup will be centered within)
/// * `title` - Popup title
/// * `items` - Help items to display
/// * `footer` - Optional footer text
pub fn draw_help_overlay(
    f: &mut Frame,
    area: Rect,
    title: &str,
    items: &[HelpItem],
    footer: Option<&str>,
) {
    let lines: Vec<Line> = items
        .iter()
        .map(|item| match item {
            HelpItem::Entry(entry) => {
                let key_width = 12; // Fixed width for alignment
                let padded_key = format!("{:<width$}", entry.key, width = key_width);
                Line::from(vec![
                    Span::styled(
                        padded_key,
                        Style::default()
                            .fg(tailwind::YELLOW.c400)
                            .add_modifier(Modifier::BOLD),
                    ),
                    Span::raw(entry.description),
                ])
            }
            HelpItem::Section(name) => Line::from(Span::styled(
                format!("── {} ──", name),
                Style::default().fg(tailwind::CYAN.c400),
            )),
            HelpItem::Blank => Line::from(""),
        })
        .collect();

    // Calculate popup dimensions
    let max_line_width = lines
        .iter()
        .map(|l| l.width())
        .max()
        .unwrap_or(20)
        .max(20) as u16;
    let popup_width = max_line_width + 4; // +4 for borders and padding
    let popup_height = lines.len() as u16 + 2; // +2 for borders

    // For centering, use a reasonable visible area height (cap at 40 lines)
    // This ensures the overlay appears near the top where the user is looking,
    // even when the content area is very tall for scrolling.
    let visible_area = Rect {
        height: area.height.min(40),
        ..area
    };
    let popup_area = centered_rect(popup_width, popup_height, visible_area);

    // Build block with optional footer
    let mut block = Block::new()
        .title(format!(" {} ", title))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(tailwind::CYAN.c400));

    if let Some(footer_text) = footer {
        block = block.title_bottom(
            Line::from(format!(" {} ", footer_text))
                .style(Style::default().fg(tailwind::GRAY.c500))
                .centered(),
        );
    }

    f.render_widget(Clear, popup_area);
    f.render_widget(
        Paragraph::new(lines)
            .block(block)
            .style(Style::default().fg(tailwind::GRAY.c200)),
        popup_area,
    );
}

/// Standard help items for the Top view.
pub fn top_view_help_items() -> Vec<HelpItem> {
    vec![
        HelpItem::Entry(HelpEntry::new("Tab", "Switch between Nodes/Pods tabs")),
        HelpItem::Blank,
        HelpItem::Section("Navigation"),
        HelpItem::Entry(HelpEntry::new("j/↓", "Select next namespace")),
        HelpItem::Entry(HelpEntry::new("k/↑", "Select previous namespace")),
        HelpItem::Entry(HelpEntry::new("PgDn/PgUp", "Scroll view")),
        HelpItem::Blank,
        HelpItem::Section("Namespaces"),
        HelpItem::Entry(HelpEntry::new("Enter/Space", "Toggle selected namespace")),
        HelpItem::Entry(HelpEntry::new("e", "Expand all namespaces")),
        HelpItem::Entry(HelpEntry::new("E", "Collapse all namespaces")),
        HelpItem::Blank,
        HelpItem::Section("Other"),
        HelpItem::Entry(HelpEntry::new("/", "Filter pods")),
        HelpItem::Entry(HelpEntry::new("?", "Toggle this help")),
        HelpItem::Entry(HelpEntry::new("q", "Quit")),
    ]
}

/// Standard help items for the Overview view.
pub fn overview_help_items() -> Vec<HelpItem> {
    vec![
        HelpItem::Section("Navigation"),
        HelpItem::Entry(HelpEntry::new("Tab", "Focus next pane")),
        HelpItem::Entry(HelpEntry::new("Shift-Tab", "Focus previous pane")),
        HelpItem::Entry(HelpEntry::new("j/↓", "Select next item")),
        HelpItem::Entry(HelpEntry::new("k/↑", "Select previous item")),
        HelpItem::Entry(HelpEntry::new("PgDn/PgUp", "Page down/up")),
        HelpItem::Blank,
        HelpItem::Section("Other"),
        HelpItem::Entry(HelpEntry::new("?", "Toggle this help")),
        HelpItem::Entry(HelpEntry::new("q", "Quit")),
    ]
}
