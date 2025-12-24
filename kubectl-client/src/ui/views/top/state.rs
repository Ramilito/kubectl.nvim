//! State management for the Top view.

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use std::collections::HashSet;
use tui_widgets::scrollview::ScrollViewState;

use crate::ui::events::Scrollable;

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
    /// Scroll state for the Nodes tab.
    pub node_scroll: ScrollViewState,
    /// Scroll state for the Pods tab.
    pub pod_scroll: ScrollViewState,
    /// Current filter string for pods.
    pub filter: String,
    /// Current input mode.
    pub input_mode: InputMode,
    /// Set of collapsed namespace names.
    collapsed_namespaces: HashSet<String>,
    /// All known namespace names (for collapse_all).
    known_namespaces: HashSet<String>,
    /// Currently selected namespace index (for Pods tab).
    selected_ns_idx: usize,
    /// Ordered list of namespace names (updated each draw).
    ns_order: Vec<String>,
    /// Whether the help overlay is visible.
    pub show_help: bool,
}

impl TopViewState {
    // ─── Tab Navigation ───────────────────────────────────────────────────

    /// Switches to the next tab.
    pub fn next_tab(&mut self) {
        self.selected_tab = (self.selected_tab + 1) % 2;
    }

    /// Switches to the previous tab.
    #[allow(dead_code)]
    pub fn prev_tab(&mut self) {
        self.selected_tab = if self.selected_tab == 0 { 1 } else { 0 };
    }

    /// Returns true if the Pods tab is selected.
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

    // ─── Namespace Collapse/Expand ────────────────────────────────────────

    /// Toggles the collapsed state of a namespace.
    fn toggle_namespace(&mut self, ns: &str) {
        if self.collapsed_namespaces.contains(ns) {
            self.collapsed_namespaces.remove(ns);
        } else {
            self.collapsed_namespaces.insert(ns.to_string());
        }
    }

    /// Returns true if the namespace is collapsed.
    pub fn is_namespace_collapsed(&self, ns: &str) -> bool {
        self.collapsed_namespaces.contains(ns)
    }

    /// Expands all namespaces.
    pub fn expand_all(&mut self) {
        self.collapsed_namespaces.clear();
    }

    /// Collapses all known namespaces.
    pub fn collapse_all(&mut self) {
        self.collapsed_namespaces = self.known_namespaces.clone();
    }

    /// Updates the set of known namespaces.
    pub fn update_known_namespaces(&mut self, namespaces: impl Iterator<Item = String>) {
        self.known_namespaces.extend(namespaces);
    }

    // ─── Namespace Selection ──────────────────────────────────────────────

    /// Selects the next namespace.
    pub fn select_next_ns(&mut self) {
        if !self.ns_order.is_empty() {
            self.selected_ns_idx = (self.selected_ns_idx + 1).min(self.ns_order.len() - 1);
        }
    }

    /// Selects the previous namespace.
    pub fn select_prev_ns(&mut self) {
        self.selected_ns_idx = self.selected_ns_idx.saturating_sub(1);
    }

    /// Toggles the currently selected namespace.
    pub fn toggle_selected_ns(&mut self) {
        if let Some(ns) = self.ns_order.get(self.selected_ns_idx) {
            let ns = ns.clone();
            self.toggle_namespace(&ns);
        }
    }

    /// Returns the currently selected namespace name.
    pub fn selected_namespace(&self) -> Option<&str> {
        self.ns_order.get(self.selected_ns_idx).map(|s| s.as_str())
    }

    /// Updates the ordered list of namespaces.
    pub fn update_ns_order(&mut self, namespaces: Vec<String>) {
        // Clamp selection if list shrinks
        if !namespaces.is_empty() && self.selected_ns_idx >= namespaces.len() {
            self.selected_ns_idx = namespaces.len() - 1;
        }
        self.ns_order = namespaces;
    }
}

impl Scrollable for TopViewState {
    fn scroll_down(&mut self) {
        if self.selected_tab == 0 {
            self.node_scroll.scroll_down();
        } else {
            self.pod_scroll.scroll_down();
        }
    }

    fn scroll_up(&mut self) {
        if self.selected_tab == 0 {
            self.node_scroll.scroll_up();
        } else {
            self.pod_scroll.scroll_up();
        }
    }

    fn scroll_page_down(&mut self) {
        if self.selected_tab == 0 {
            self.node_scroll.scroll_page_down();
        } else {
            self.pod_scroll.scroll_page_down();
        }
    }

    fn scroll_page_up(&mut self) {
        if self.selected_tab == 0 {
            self.node_scroll.scroll_page_up();
        } else {
            self.pod_scroll.scroll_page_up();
        }
    }
}
