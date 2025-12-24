//! State management for the Top view.

/// State for the Top view.
#[derive(Default)]
pub struct TopViewState {
    /// Currently selected tab (0 = Nodes, 1 = Pods).
    pub selected_tab: usize,
    /// Whether the help overlay is visible.
    pub show_help: bool,
}

impl TopViewState {
    /// Switches to the next tab.
    pub fn next_tab(&mut self) {
        self.selected_tab = (self.selected_tab + 1) % 2;
    }

    /// Toggles the help overlay visibility.
    pub fn toggle_help(&mut self) {
        self.show_help = !self.show_help;
    }

    /// Returns true if the help overlay is visible.
    pub fn is_help_visible(&self) -> bool {
        self.show_help
    }
}
