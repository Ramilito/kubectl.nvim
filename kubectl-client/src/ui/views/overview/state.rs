//! State management for the Overview view.

/// State for the Overview view.
#[derive(Default)]
pub struct OverviewState {
    /// Whether the help overlay is visible.
    pub show_help: bool,
}

impl OverviewState {
    /// Toggles the help overlay visibility.
    pub fn toggle_help(&mut self) {
        self.show_help = !self.show_help;
    }

    /// Returns true if the help overlay is visible.
    pub fn is_help_visible(&self) -> bool {
        self.show_help
    }
}
