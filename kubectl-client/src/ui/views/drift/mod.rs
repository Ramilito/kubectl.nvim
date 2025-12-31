//! Drift view - Shows differences between local manifests and deployed cluster state.
//!
//! Powered by kubediff library.
//! Uses native vim folds for expanding/collapsing diffs.

use crossterm::event::{Event, KeyCode};
use kubediff::{DiffResult, Process, TargetResult};
use ratatui::{
    layout::{Constraint, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::Paragraph,
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

/// Drift view displaying kubediff results with inline diffs.
pub struct DriftView {
    /// Path to diff against cluster
    path: String,
    /// Cached results from kubediff
    results: Vec<TargetResult>,
    /// Error message if refresh failed
    error: Option<String>,
    /// Filter: when true, hide unchanged resources
    hide_unchanged: bool,
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
            error: None,
            hide_unchanged: false,
        };
        view.refresh();
        view
    }

    /// Refreshes diff results from kubediff.
    fn refresh(&mut self) {
        self.error = None;

        if self.path.is_empty() {
            self.error = Some("No path specified. Usage: :Kubectl drift <path>".to_string());
            self.results = Vec::new();
            return;
        }

        // Call kubediff to process the target
        let result = Process::process_target(&self.path);
        self.results = vec![result];
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
    }

    /// Checks if a result should be shown based on filter.
    fn should_show(&self, result: &DiffResult) -> bool {
        if !self.hide_unchanged {
            return true;
        }
        // Show if changed or error
        result.error.is_some() || result.diff.is_some()
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
            Constraint::Min(0),    // Results with inline diffs
        ])
        .split(area);

        // Help bar
        draw_help_bar(f, layouts[0], &drift_hints());

        // Summary line with path
        let counts = self.count_statuses();
        draw_summary(f, layouts[1], &counts, self.hide_unchanged, &self.path);

        // Main content area with inline diffs
        draw_results_with_diffs(
            f,
            layouts[2],
            &self.results,
            &self.error,
            &self.path,
            self.hide_unchanged,
            self,
        );
    }

    fn set_cursor_line(&mut self, _line: u16) -> bool {
        // No longer needed - using native vim folds
        false
    }

    fn content_height(&self) -> Option<u16> {
        let mut height: u16 = 3; // Help bar + summary + border top

        for target in &self.results {
            if target.build_error.is_some() {
                height += 1;
                continue;
            }

            height += 1; // Target header

            for result in &target.results {
                if !self.hide_unchanged || result.error.is_some() || result.diff.is_some() {
                    height += 1; // Result line

                    // Add diff lines
                    if let Some(ref diff) = result.diff {
                        height += diff.lines().count() as u16;
                    }
                    if let Some(ref err) = result.error {
                        height += 1; // Error line
                        let _ = err; // Suppress unused warning
                    }
                }
            }

            height += 1; // Blank after target
        }

        height += 1; // Border bottom

        if self.error.is_some() {
            height += 2;
        }

        Some(height.max(10))
    }
}

/// Draws the summary line with status counts and path.
fn draw_summary(f: &mut Frame, area: Rect, counts: &StatusCounts, filter_active: bool, path: &str) {
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

/// Draws the results list with inline diffs.
fn draw_results_with_diffs(
    f: &mut Frame,
    area: Rect,
    results: &[TargetResult],
    error: &Option<String>,
    path: &str,
    _hide_unchanged: bool,
    view: &DriftView,
) {
    // No border - renders directly for clean fold detection
    // Path is shown in the summary line instead
    let _ = path; // Path shown elsewhere

    let inner = area;
    let mut y = 0u16;

    // Show error if present
    if let Some(err) = error {
        let error_line = Line::from(vec![
            Span::styled(ICON_ERROR, Style::default().fg(colors::ERROR)),
            Span::raw(" "),
            Span::styled(err, Style::default().fg(colors::ERROR)),
        ]);
        if y < inner.height {
            f.render_widget(
                Paragraph::new(error_line),
                Rect {
                    x: inner.x,
                    y: inner.y + y,
                    width: inner.width,
                    height: 1,
                },
            );
        }
        return;
    }

    // Render each target and its results with inline diffs
    for target in results {
        // Build error if present
        if let Some(ref build_err) = target.build_error {
            let err_line = Line::from(vec![
                Span::styled(ICON_ERROR, Style::default().fg(colors::ERROR)),
                Span::raw(" Build error: "),
                Span::styled(build_err, Style::default().fg(colors::ERROR)),
            ]);
            if y < inner.height {
                f.render_widget(
                    Paragraph::new(err_line),
                    Rect {
                        x: inner.x,
                        y: inner.y + y,
                        width: inner.width,
                        height: 1,
                    },
                );
            }
            y += 1;
            continue;
        }

        // Target header
        let target_line = Line::from(vec![Span::styled(
            format!("TARGET: {}", target.target),
            Style::default()
                .fg(colors::SUCCESS)
                .add_modifier(Modifier::BOLD),
        )]);
        if y < inner.height {
            f.render_widget(
                Paragraph::new(target_line),
                Rect {
                    x: inner.x,
                    y: inner.y + y,
                    width: inner.width,
                    height: 1,
                },
            );
        }
        y += 1;

        // Results with inline diffs
        for result in &target.results {
            if y >= inner.height {
                break;
            }

            // Skip unchanged if filter is active
            if !view.should_show(result) {
                continue;
            }

            let (icon, row_color, status) = if result.error.is_some() {
                (ICON_ERROR, colors::ERROR, "error")
            } else if result.diff.is_some() {
                (ICON_CHANGED, colors::DEBUG, "changed")
            } else {
                (ICON_NO_CHANGE, colors::INFO, "no changes")
            };

            // Resource line with full row coloring (yellow for changed, red for error)
            let result_line = Line::from(vec![
                Span::styled(format!("{:<2}", icon), Style::default().fg(row_color)),
                Span::styled(
                    format!("{}/{}", result.kind, result.resource_name),
                    Style::default().fg(row_color),
                ),
                Span::styled(format!(" ({})", status), Style::default().fg(row_color)),
            ]);

            f.render_widget(
                Paragraph::new(result_line),
                Rect {
                    x: inner.x,
                    y: inner.y + y,
                    width: inner.width,
                    height: 1,
                },
            );
            y += 1;

            // Inline error message
            if let Some(ref err) = result.error {
                if y < inner.height {
                    let err_line = Line::from(vec![
                        Span::raw("    "),
                        Span::styled(err, Style::default().fg(colors::ERROR)),
                    ]);
                    f.render_widget(
                        Paragraph::new(err_line),
                        Rect {
                            x: inner.x,
                            y: inner.y + y,
                            width: inner.width,
                            height: 1,
                        },
                    );
                    y += 1;
                }
            }

            // Inline diff content (for vim folds)
            if let Some(ref diff) = result.diff {
                for diff_line in diff.lines() {
                    if y >= inner.height {
                        break;
                    }

                    let style = if diff_line.starts_with('+') && !diff_line.starts_with("+++") {
                        Style::default().fg(colors::INFO).bg(Color::Rgb(20, 40, 20))
                    } else if diff_line.starts_with('-') && !diff_line.starts_with("---") {
                        Style::default()
                            .fg(colors::ERROR)
                            .bg(Color::Rgb(40, 20, 20))
                    } else if diff_line.starts_with("@@") {
                        Style::default().fg(colors::PENDING)
                    } else {
                        Style::default().fg(colors::GRAY)
                    };

                    // Indent diff lines
                    let line = Line::from(vec![
                        Span::raw("    "),
                        Span::styled(diff_line, style),
                    ]);

                    f.render_widget(
                        Paragraph::new(line),
                        Rect {
                            x: inner.x,
                            y: inner.y + y,
                            width: inner.width,
                            height: 1,
                        },
                    );
                    y += 1;
                }
            }
        }

        y += 1; // Blank line after target
    }

    // Empty state
    if results.is_empty() || results.iter().all(|t| t.results.is_empty()) {
        let empty_line = Line::from(vec![Span::styled(
            "No resources found to diff",
            Style::default().fg(colors::GRAY),
        )]);
        f.render_widget(
            Paragraph::new(empty_line),
            Rect {
                x: inner.x,
                y: inner.y,
                width: inner.width,
                height: 1,
            },
        );
    }
}
