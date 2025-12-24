//! State management for the Top view.

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

/// Input mode for the Top view.
#[derive(PartialEq, Eq, Default)]
pub enum InputMode {
    #[default]
    Normal,
    Filtering,
}

/// State for the Top view.
#[derive(Default)]
pub struct TopViewState {
    /// Currently selected tab (0 = Nodes, 1 = Pods).
    pub selected_tab: usize,
    /// Current filter string for pods.
    pub filter: String,
    /// Current input mode.
    pub input_mode: InputMode,
    /// Whether the help overlay is visible.
    pub show_help: bool,
}

impl TopViewState {
    // ─── Tab Navigation ───────────────────────────────────────────────────

    /// Switches to the next tab.
    pub fn next_tab(&mut self) {
        self.selected_tab = (self.selected_tab + 1) % 2;
    }

    /// Returns true if the Pods tab is selected.
    #[allow(dead_code)]
    pub fn is_pods_tab(&self) -> bool {
        self.selected_tab == 1
    }

    // ─── Help Overlay ─────────────────────────────────────────────────────

    /// Toggles the help overlay visibility.
    pub fn toggle_help(&mut self) {
        self.show_help = !self.show_help;
    }

    /// Returns true if the help overlay is visible.
    pub fn is_help_visible(&self) -> bool {
        self.show_help
    }

    // ─── Filter Input ─────────────────────────────────────────────────────

    /// Handles a key event for filter input.
    pub fn handle_key(&mut self, key: KeyEvent) {
        match self.input_mode {
            InputMode::Normal => {
                if let KeyCode::Char('/') = key.code {
                    self.input_mode = InputMode::Filtering;
                }
            }
            InputMode::Filtering => match key.code {
                KeyCode::Esc => {
                    self.filter.clear();
                    self.input_mode = InputMode::Normal;
                }
                KeyCode::Enter => self.input_mode = InputMode::Normal,
                KeyCode::Backspace => {
                    self.filter.pop();
                }
                KeyCode::Char(c)
                    if key.modifiers.is_empty() || key.modifiers == KeyModifiers::SHIFT =>
                {
                    self.filter.push(c);
                }
                _ => {}
            },
        }
    }
}
