//! Drift view - Shows differences between local manifests and deployed cluster state.
//!
//! Features a side-by-side layout with resource list and diff preview.
//! Powered by kubediff library.

use crossterm::event::{Event, KeyCode};
use kubediff::{DiffResult, Process, TargetResult};
use ratatui::{
    layout::{Constraint, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, Paragraph, Wrap},
    Frame,
};

use crate::ui::{
    colors,
    components::{draw_help_bar, drift_hints},
    views::View,
};

/// Status icons for diff results
const ICON_NO_CHANGE: &str = "✓";
const ICON_CHANGED: &str = "~";
const ICON_ERROR: &str = "✗";

/// Flattened resource entry for the list
struct ResourceEntry {
    target_idx: usize,
    result_idx: usize,
    kind: String,
    name: String,
    status: ResourceStatus,
    diff_lines: i32,
}

#[derive(Clone, Copy, PartialEq)]
enum ResourceStatus {
    Changed,
    Unchanged,
    Error,
}

/// Drift view with side-by-side layout.
pub struct DriftView {
    /// Path to diff against cluster
    path: String,
    /// Cached results from kubediff
    results: Vec<TargetResult>,
    /// Filter: when true, hide unchanged resources
    hide_unchanged: bool,
    /// Flattened list of resources for navigation
    entries: Vec<ResourceEntry>,
    /// Current selection index (synced from vim cursor)
    selected_idx: Option<usize>,
}

/// Counts of resources by status
struct StatusCounts {
    changed: usize,
    unchanged: usize,
    errors: usize,
}

impl DriftView {
    /// Creates a new DriftView for the given path.
    pub fn new(path: String) -> Self {
        let mut view = Self {
            path,
            results: Vec::new(),
            hide_unchanged: false,
            entries: Vec::new(),
            selected_idx: None,
        };
        view.refresh();
        view
    }

    /// Refreshes diff results from kubediff.
    fn refresh(&mut self) {
        if self.path.is_empty() {
            self.results = Vec::new();
            self.entries = Vec::new();
            return;
        }

        let result = Process::process_target(&self.path);
        self.results = vec![result];
        self.rebuild_entries();

        // Select first item if available
        self.selected_idx = if self.entries.is_empty() {
            None
        } else {
            Some(0)
        };
    }

    /// Rebuilds the flattened entry list.
    fn rebuild_entries(&mut self) {
        self.entries.clear();

        for (target_idx, target) in self.results.iter().enumerate() {
            for (result_idx, result) in target.results.iter().enumerate() {
                let status = if result.error.is_some() {
                    ResourceStatus::Error
                } else if result.diff.is_some() {
                    ResourceStatus::Changed
                } else {
                    ResourceStatus::Unchanged
                };

                // Skip unchanged if filter active
                if self.hide_unchanged && status == ResourceStatus::Unchanged {
                    continue;
                }

                let diff_lines = result
                    .diff
                    .as_ref()
                    .map(|d| d.lines().count() as i32)
                    .unwrap_or(0);

                self.entries.push(ResourceEntry {
                    target_idx,
                    result_idx,
                    kind: result.kind.clone(),
                    name: result.resource_name.clone(),
                    status,
                    diff_lines,
                });
            }
        }
    }

    /// Counts resources by status.
    fn count_statuses(&self) -> StatusCounts {
        let mut counts = StatusCounts {
            changed: 0,
            unchanged: 0,
            errors: 0,
        };

        for target in &self.results {
            for result in &target.results {
                if result.error.is_some() {
                    counts.errors += 1;
                } else if result.diff.is_some() {
                    counts.changed += 1;
                } else {
                    counts.unchanged += 1;
                }
            }
        }

        counts
    }

    /// Toggles the filter to hide unchanged resources.
    fn toggle_filter(&mut self) {
        self.hide_unchanged = !self.hide_unchanged;
        self.rebuild_entries();
        self.selected_idx = if self.entries.is_empty() {
            None
        } else {
            Some(0)
        };
    }

    /// Gets the currently selected resource's diff result.
    fn selected_result(&self) -> Option<&DiffResult> {
        let entry = self.entries.get(self.selected_idx?)?;
        self.results
            .get(entry.target_idx)?
            .results
            .get(entry.result_idx)
    }
}

impl View for DriftView {
    fn on_event(&mut self, ev: &Event) -> bool {
        match ev {
            Event::Key(k) => match k.code {
                KeyCode::Char('r') => {
                    self.refresh();
                    true
                }
                KeyCode::Char('f') => {
                    self.toggle_filter();
                    true
                }
                _ => false,
            },
            _ => false,
        }
    }

    fn draw(&mut self, f: &mut Frame, area: Rect) {
        let layouts = Layout::vertical([
            Constraint::Length(1), // Help bar
            Constraint::Length(1), // Summary line
            Constraint::Min(0),    // Main content (split pane)
        ])
        .split(area);

        // Help bar
        draw_help_bar(f, layouts[0], &drift_hints());

        // If no path is set, show a prompt message
        if self.path.is_empty() {
            let msg = Paragraph::new(Line::from(vec![
                Span::styled("Press ", Style::default().fg(colors::GRAY)),
                Span::styled("p", Style::default().fg(colors::PENDING).add_modifier(Modifier::BOLD)),
                Span::styled(" to select a path", Style::default().fg(colors::GRAY)),
            ]))
            .alignment(ratatui::layout::Alignment::Center);

            // Center vertically
            let vertical_center = layouts[2].y + layouts[2].height / 2;
            let msg_area = Rect::new(layouts[2].x, vertical_center, layouts[2].width, 1);
            f.render_widget(msg, msg_area);
            return;
        }

        // Summary line with path
        let counts = self.count_statuses();
        draw_summary(f, layouts[1], &counts, self.hide_unchanged, &self.path);

        // Split pane: resource list | diff preview
        let panes = Layout::horizontal([
            Constraint::Percentage(35), // Resource list
            Constraint::Percentage(65), // Diff preview
        ])
        .split(layouts[2]);

        // Left pane: Resource list
        draw_resource_list(f, panes[0], &self.entries);

        // Right pane: Diff preview
        draw_diff_preview(f, panes[1], self.selected_result());
    }

    fn set_cursor_line(&mut self, line: u16) -> bool {
        // Map cursor line to list entry
        // Layout: help bar (1) + summary (1) + border (1) + list items
        // So list items start at line 3 (0-indexed)
        let list_start = 3u16;
        if line >= list_start {
            let entry_idx = (line - list_start) as usize;
            if entry_idx < self.entries.len() {
                self.selected_idx = Some(entry_idx);
                return true;
            }
        }
        false
    }

    fn content_height(&self) -> Option<u16> {
        // Fixed height based on content
        let list_height = self.entries.len() as u16 + 4; // entries + borders + header
        let diff_height = self
            .selected_result()
            .and_then(|r| r.diff.as_ref())
            .map(|d| d.lines().count() as u16 + 4)
            .unwrap_or(10);

        Some(list_height.max(diff_height).max(15))
    }

    fn set_path(&mut self, path: String) -> bool {
        self.path = path;
        self.refresh();
        true
    }
}

/// Draws the summary line with status counts and path.
fn draw_summary(
    f: &mut Frame,
    area: Rect,
    counts: &StatusCounts,
    filter_active: bool,
    path: &str,
) {
    let mut spans = vec![
        Span::styled(
            format!(" {} ", path),
            Style::default()
                .fg(colors::HEADER)
                .add_modifier(Modifier::BOLD),
        ),
        Span::styled("│ ", Style::default().fg(colors::GRAY)),
        Span::styled(
            format!("{} changed", counts.changed),
            Style::default().fg(colors::DEBUG),
        ),
        Span::styled(" │ ", Style::default().fg(colors::GRAY)),
        Span::styled(
            format!("{} unchanged", counts.unchanged),
            Style::default().fg(colors::INFO),
        ),
        Span::styled(" │ ", Style::default().fg(colors::GRAY)),
        Span::styled(
            format!("{} errors", counts.errors),
            Style::default().fg(colors::ERROR),
        ),
    ];

    if filter_active {
        spans.push(Span::styled(" │ ", Style::default().fg(colors::GRAY)));
        spans.push(Span::styled(
            "[filtered]",
            Style::default()
                .fg(colors::PENDING)
                .add_modifier(Modifier::BOLD),
        ));
    }

    let summary = Line::from(spans);
    f.render_widget(Paragraph::new(summary), area);
}

/// Draws the resource list in the left pane.
fn draw_resource_list(f: &mut Frame, area: Rect, entries: &[ResourceEntry]) {
    let items: Vec<ListItem> = entries
        .iter()
        .map(|entry| {
            let (icon, color) = match entry.status {
                ResourceStatus::Changed => (ICON_CHANGED, colors::DEBUG),
                ResourceStatus::Unchanged => (ICON_NO_CHANGE, colors::INFO),
                ResourceStatus::Error => (ICON_ERROR, colors::ERROR),
            };

            let diff_info = if entry.diff_lines > 0 {
                format!(" ({})", entry.diff_lines)
            } else {
                String::new()
            };

            let line = Line::from(vec![
                Span::styled(format!("{} ", icon), Style::default().fg(color)),
                Span::styled(
                    format!("{}/{}", entry.kind, entry.name),
                    Style::default().fg(color),
                ),
                Span::styled(diff_info, Style::default().fg(colors::GRAY)),
            ]);

            ListItem::new(line)
        })
        .collect();

    let list = List::new(items).block(
        Block::default()
            .title(" Resources ")
            .borders(Borders::ALL)
            .border_style(Style::default().fg(colors::GRAY)),
    );

    f.render_widget(list, area);
}

/// Draws the diff preview in the right pane.
fn draw_diff_preview(f: &mut Frame, area: Rect, result: Option<&DiffResult>) {
    let block = Block::default()
        .title(" Diff Preview ")
        .borders(Borders::ALL)
        .border_style(Style::default().fg(colors::GRAY));

    let inner = block.inner(area);
    f.render_widget(block, area);

    match result {
        None => {
            let msg = Paragraph::new("Select a resource to view diff")
                .style(Style::default().fg(colors::GRAY));
            f.render_widget(msg, inner);
        }
        Some(result) => {
            if let Some(ref err) = result.error {
                let err_text = Paragraph::new(vec![
                    Line::from(Span::styled(
                        "Error:",
                        Style::default()
                            .fg(colors::ERROR)
                            .add_modifier(Modifier::BOLD),
                    )),
                    Line::from(Span::styled(err.as_str(), Style::default().fg(colors::ERROR))),
                ])
                .wrap(Wrap { trim: false });
                f.render_widget(err_text, inner);
            } else if let Some(ref diff) = result.diff {
                let lines: Vec<Line> = diff
                    .lines()
                    .map(|line| {
                        let style = if line.starts_with('+') && !line.starts_with("+++") {
                            Style::default()
                                .fg(colors::INFO)
                                .bg(Color::Rgb(20, 40, 20))
                        } else if line.starts_with('-') && !line.starts_with("---") {
                            Style::default()
                                .fg(colors::ERROR)
                                .bg(Color::Rgb(40, 20, 20))
                        } else if line.starts_with("@@") {
                            Style::default().fg(colors::PENDING)
                        } else {
                            Style::default().fg(colors::GRAY)
                        };
                        Line::from(Span::styled(line, style))
                    })
                    .collect();

                let diff_text = Paragraph::new(lines).wrap(Wrap { trim: false });
                f.render_widget(diff_text, inner);
            } else {
                let msg = Paragraph::new(Line::from(vec![
                    Span::styled(ICON_NO_CHANGE, Style::default().fg(colors::INFO)),
                    Span::raw(" No differences"),
                ]))
                .style(Style::default().fg(colors::INFO));
                f.render_widget(msg, inner);
            }
        }
    }
}
