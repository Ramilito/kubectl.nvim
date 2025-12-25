//! State management for the Top view.

/// State for the Top view.
#[derive(Default)]
pub struct TopViewState {
    /// Currently selected tab (0 = Nodes, 1 = Pods).
    pub selected_tab: usize,
    /// Whether the help overlay is visible.
    pub show_help: bool,
    /// Current cursor line (0-indexed, synced from Neovim).
    pub cursor_line: u16,
    /// Expanded pod (namespace, name) if any.
    pub expanded_pod: Option<(String, String)>,
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

    /// Sets the cursor line.
    pub fn set_cursor(&mut self, line: u16) {
        self.cursor_line = line;
    }

    /// Toggles expansion for a pod.
    pub fn toggle_expansion(&mut self, namespace: String, name: String) {
        if let Some((ref ns, ref n)) = self.expanded_pod {
            if ns == &namespace && n == &name {
                self.expanded_pod = None;
                return;
            }
        }
        self.expanded_pod = Some((namespace, name));
    }

    /// Returns true if the given pod is expanded.
    pub fn is_expanded(&self, namespace: &str, name: &str) -> bool {
        self.expanded_pod
            .as_ref()
            .map(|(ns, n)| ns == namespace && n == name)
            .unwrap_or(false)
    }
}
