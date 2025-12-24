//! Layout utilities for UI components.
//!
//! Provides shared layout calculations and helper functions used across views.

use ratatui::{
    layout::{Constraint, Layout, Rect},
    text::Line,
};

/// Default gap between columns (e.g., between CPU and MEM columns).
pub const COL_GAP: u16 = 2;

/// Maximum width for name/title columns.
pub const MAX_TITLE_WIDTH: u16 = 100;

/// Splits a rectangle into 4 columns: [NAME, CPU, GAP, MEM].
///
/// Used for consistent column layout in node/pod displays.
pub fn column_split(area: Rect, name_width: u16) -> [Rect; 4] {
    Layout::horizontal([
        Constraint::Length(name_width),
        Constraint::Percentage(50),
        Constraint::Length(COL_GAP),
        Constraint::Percentage(50),
    ])
    .areas(area)
}

/// Creates a centered rectangle within the given area.
///
/// Used for modal popups like help overlays.
pub fn centered_rect(width: u16, height: u16, area: Rect) -> Rect {
    let x = area.x + (area.width.saturating_sub(width)) / 2;
    let y = area.y + (area.height.saturating_sub(height)) / 2;
    Rect::new(x, y, width.min(area.width), height.min(area.height))
}

/// Calculates the optimal column width for a list of names.
///
/// Returns the width of the longest name (plus padding), clamped to MAX_TITLE_WIDTH.
pub fn calculate_name_width<'a>(names: impl Iterator<Item = &'a str>, padding: u16) -> u16 {
    names
        .map(|name| Line::from(name).width() as u16 + padding)
        .max()
        .unwrap_or(1)
        .clamp(1, MAX_TITLE_WIDTH)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_centered_rect() {
        let area = Rect::new(0, 0, 100, 50);
        let popup = centered_rect(40, 20, area);

        assert_eq!(popup.x, 30); // (100 - 40) / 2
        assert_eq!(popup.y, 15); // (50 - 20) / 2
        assert_eq!(popup.width, 40);
        assert_eq!(popup.height, 20);
    }

    #[test]
    fn test_centered_rect_clamped() {
        let area = Rect::new(0, 0, 30, 10);
        let popup = centered_rect(50, 20, area);

        assert_eq!(popup.width, 30); // clamped to area width
        assert_eq!(popup.height, 10); // clamped to area height
    }

    #[test]
    fn test_calculate_name_width() {
        let names = vec!["short", "medium-name", "very-long-name-here"];
        let width = calculate_name_width(names.iter().map(|s| *s), 2);

        // "very-long-name-here" is 19 chars + 2 padding = 21
        assert_eq!(width, 21);
    }
}
