//! State management for the Overview view.

use tui_widgets::scrollview::ScrollViewState;

use crate::ui::events::Scrollable;

/// The six panes in the overview layout.
#[derive(Clone, Copy, Default)]
enum Pane {
    Info,
    #[default]
    Nodes,
    Namespace,
    TopCpu,
    TopMem,
    Events,
}

impl Pane {
    fn next(self) -> Self {
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

    fn prev(self) -> Self {
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

/// State for the Overview view.
#[derive(Default)]
pub struct OverviewState {
    /// Currently focused pane.
    focus: Pane,
    /// Scroll state for each pane.
    pub info: ScrollViewState,
    pub nodes: ScrollViewState,
    pub namespace: ScrollViewState,
    pub top_cpu: ScrollViewState,
    pub top_mem: ScrollViewState,
    pub events: ScrollViewState,
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

    /// Returns a mutable reference to the focused pane's scroll state.
    fn focus_mut(&mut self) -> &mut ScrollViewState {
        match self.focus {
            Pane::Info => &mut self.info,
            Pane::Nodes => &mut self.nodes,
            Pane::Namespace => &mut self.namespace,
            Pane::TopCpu => &mut self.top_cpu,
            Pane::TopMem => &mut self.top_mem,
            Pane::Events => &mut self.events,
        }
    }
}

impl Scrollable for OverviewState {
    fn scroll_down(&mut self) {
        self.focus_mut().scroll_down();
    }

    fn scroll_up(&mut self) {
        self.focus_mut().scroll_up();
    }

    fn scroll_page_down(&mut self) {
        self.focus_mut().scroll_page_down();
    }

    fn scroll_page_up(&mut self) {
        self.focus_mut().scroll_page_up();
    }
}
