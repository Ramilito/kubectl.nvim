//! State management for the Overview view.

use tui_widgets::scrollview::ScrollViewState;

use crate::ui::events::Scrollable;

/// The six panes in the overview layout.
#[derive(Clone, Copy, Default, PartialEq, Eq)]
pub enum Pane {
    Info,
    #[default]
    Nodes,
    Namespace,
    TopCpu,
    TopMem,
    Events,
}

impl Pane {
    pub fn next(self) -> Self {
        use Pane::*;
        match self {
            Info => Nodes,
            Nodes => Namespace,
            Namespace => TopCpu,
            TopCpu => TopMem,
            TopMem => Events,
            Events => Info,
        }
    }

    pub fn prev(self) -> Self {
        use Pane::*;
        match self {
            Info => Events,
            Events => TopMem,
            TopMem => TopCpu,
            TopCpu => Namespace,
            Namespace => Nodes,
            Nodes => Info,
        }
    }
}

/// State for a single pane with scroll and selection.
#[derive(Default)]
pub struct PaneState {
    pub scroll: ScrollViewState,
    pub selected: usize,
    pub item_count: usize,
}

impl PaneState {
    /// Moves selection down, returns true if changed.
    pub fn select_next(&mut self) -> bool {
        if self.item_count > 0 && self.selected < self.item_count - 1 {
            self.selected += 1;
            true
        } else {
            false
        }
    }

    /// Moves selection up, returns true if changed.
    pub fn select_prev(&mut self) -> bool {
        if self.selected > 0 {
            self.selected -= 1;
            true
        } else {
            false
        }
    }

    /// Updates item count and clamps selection.
    pub fn set_item_count(&mut self, count: usize) {
        self.item_count = count;
        if count > 0 && self.selected >= count {
            self.selected = count - 1;
        }
    }
}

/// State for the Overview view.
#[derive(Default)]
pub struct OverviewState {
    /// Currently focused pane.
    pub focus: Pane,
    /// State for each pane.
    pub info: PaneState,
    pub nodes: PaneState,
    pub namespace: PaneState,
    pub top_cpu: PaneState,
    pub top_mem: PaneState,
    pub events: PaneState,
}

impl OverviewState {
    /// Focuses the next pane (Tab).
    pub fn focus_next(&mut self) {
        self.focus = self.focus.next();
    }

    /// Focuses the previous pane (Shift-Tab).
    pub fn focus_prev(&mut self) {
        self.focus = self.focus.prev();
    }

    /// Returns true if the given pane is focused.
    pub fn is_focused(&self, pane: Pane) -> bool {
        self.focus == pane
    }

    /// Returns a mutable reference to the focused pane's state.
    fn focus_mut(&mut self) -> &mut PaneState {
        match self.focus {
            Pane::Info => &mut self.info,
            Pane::Nodes => &mut self.nodes,
            Pane::Namespace => &mut self.namespace,
            Pane::TopCpu => &mut self.top_cpu,
            Pane::TopMem => &mut self.top_mem,
            Pane::Events => &mut self.events,
        }
    }

    /// Moves selection down in the focused pane.
    pub fn select_next(&mut self) {
        self.focus_mut().select_next();
    }

    /// Moves selection up in the focused pane.
    pub fn select_prev(&mut self) {
        self.focus_mut().select_prev();
    }
}

impl Scrollable for OverviewState {
    fn scroll_down(&mut self) {
        self.select_next();
    }

    fn scroll_up(&mut self) {
        self.select_prev();
    }

    fn scroll_page_down(&mut self) {
        // Move selection by ~10 items
        for _ in 0..10 {
            if !self.focus_mut().select_next() {
                break;
            }
        }
    }

    fn scroll_page_up(&mut self) {
        // Move selection by ~10 items
        for _ in 0..10 {
            if !self.focus_mut().select_prev() {
                break;
            }
        }
    }
}
