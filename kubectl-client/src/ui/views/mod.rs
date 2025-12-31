//! View implementations for the dashboard.
//!
//! Each view is a self-contained unit with its own state and rendering logic.

mod drift;
mod overview;
mod top;

use crossterm::event::Event;
use ratatui::{layout::Rect, Frame};

pub use drift::DriftView;
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

    /// Returns the required content height for the current state.
    ///
    /// Used to dynamically size the buffer for native Neovim scrolling.
    /// Returns `None` to use the default/window height.
    fn content_height(&self) -> Option<u16> {
        None
    }

    /// Signals that metrics data has been updated.
    ///
    /// Views should invalidate any cached metrics data and refresh on next draw.
    fn on_metrics_update(&mut self) {
        // Default implementation does nothing
    }

    /// Sets a new path and refreshes the view.
    ///
    /// Returns `true` if a redraw is needed.
    fn set_path(&mut self, _path: String) -> bool {
        // Default implementation does nothing
        false
    }
}

/// Creates a view by name.
///
/// # Arguments
/// * `name` - View name: "top", "top_ui", "overview", "overview_ui", or "drift"
/// * `args` - Optional arguments for the view (e.g., path for drift view)
///
/// # Returns
/// Boxed view instance. Defaults to OverviewView for unknown names.
pub fn make_view(name: &str, args: Option<&str>) -> Box<dyn View> {
    match name.to_ascii_lowercase().as_str() {
        "drift" => Box::new(DriftView::new(args.unwrap_or("").to_string())),
        "top" | "top_ui" => Box::new(TopView::default()),
        "overview" | "overview_ui" => Box::new(OverviewView::default()),
        _ => Box::new(OverviewView::default()),
    }
}
