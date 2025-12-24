//! View implementations for the dashboard.
//!
//! Each view is a self-contained unit with its own state and rendering logic.

mod overview;
mod top;

use crossterm::event::Event;
use ratatui::{layout::Rect, Frame};

pub use overview::OverviewView;
pub use top::TopView;

/// Trait for dashboard views.
///
/// Views handle events and render themselves to the terminal.
pub trait View: Send {
    /// Handles an input event.
    ///
    /// Returns `true` if the event was consumed and a redraw is needed.
    fn on_event(&mut self, ev: &Event) -> bool;

    /// Renders the view to the given frame area.
    fn draw(&mut self, f: &mut Frame, area: Rect);

    /// Sets the cursor line from Neovim for selection sync.
    ///
    /// The line is 0-indexed. Returns `true` if a redraw is needed.
    fn set_cursor_line(&mut self, _line: u16) -> bool {
        // Default implementation does nothing
        false
    }
}

/// Creates a view by name.
///
/// # Arguments
/// * `name` - View name: "top", "top_ui", "overview", or "overview_ui"
///
/// # Returns
/// Boxed view instance. Defaults to OverviewView for unknown names.
pub fn make_view(name: &str) -> Box<dyn View> {
    match name.to_ascii_lowercase().as_str() {
        "top" | "top_ui" => Box::new(TopView::default()),
        "overview" | "overview_ui" => Box::new(OverviewView::default()),
        _ => Box::new(OverviewView::default()),
    }
}
