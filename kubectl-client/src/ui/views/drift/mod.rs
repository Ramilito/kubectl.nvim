//! Drift view - Shows differences between local manifests and deployed cluster state.
//!
//! Powered by kubediff library.

use crossterm::event::{Event, KeyCode};
use kubediff::{DiffResult, Process, TargetResult};
use ratatui::{
    layout::{Constraint, Layout, Margin, Rect},
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
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

/// Drift view displaying kubediff results.
pub struct DriftView {
    /// Path to diff against cluster
    path: String,
    /// Cached results from kubediff
    results: Vec<TargetResult>,
    /// Index of expanded result (for showing diff details)
    expanded_idx: Option<usize>,
    /// Current cursor line (synced from Neovim)
    cursor_line: u16,
    /// Error message if refresh failed
    error: Option<String>,
    /// Flattened list of (target_idx, result_idx) for cursor mapping
    line_map: Vec<(usize, Option<usize>)>,
}

impl DriftView {
    /// Creates a new DriftView for the given path.
    pub fn new(path: String) -> Self {
        let mut view = Self {
            path,
            results: Vec::new(),
            expanded_idx: None,
            cursor_line: 0,
            error: None,
            line_map: Vec::new(),
        };
        view.refresh();
        view
    }

    /// Refreshes diff results from kubediff.
    fn refresh(&mut self) {
        self.error = None;
        self.expanded_idx = None;

        if self.path.is_empty() {
            self.error = Some("No path specified. Usage: :Kubectl drift <path>".to_string());
            self.results = Vec::new();
            return;
        }

        // Call kubediff to process the target
        let result = Process::process_target(&self.path);
        self.results = vec![result];
        self.rebuild_line_map();
    }

    /// Rebuilds the line map for cursor-to-result mapping.
    fn rebuild_line_map(&mut self) {
        self.line_map.clear();

        // Line 0: help bar
        // Line 1: blank or error

        for (target_idx, target) in self.results.iter().enumerate() {
            // Target header line
            self.line_map.push((target_idx, None));

            // Result lines
            for result_idx in 0..target.results.len() {
                self.line_map.push((target_idx, Some(result_idx)));
            }

            // Blank line after target
            self.line_map.push((target_idx, None));
        }
    }

    /// Gets the result at the current cursor position.
    fn result_at_cursor(&self) -> Option<(usize, usize)> {
        // Skip: help bar (1) + border top (1) = 2 lines
        let effective_line = self.cursor_line.saturating_sub(2);
        self.line_map
            .get(effective_line as usize)
            .and_then(|(t, r)| r.map(|ri| (*t, ri)))
    }

    /// Toggles expansion of the result at cursor.
    fn toggle_expand(&mut self) {
        if let Some((target_idx, result_idx)) = self.result_at_cursor() {
            let flat_idx = self.results[..target_idx]
                .iter()
                .map(|t| t.results.len())
                .sum::<usize>()
                + result_idx;

            if self.expanded_idx == Some(flat_idx) {
                self.expanded_idx = None;
            } else {
                self.expanded_idx = Some(flat_idx);
            }
        }
    }

    /// Gets the currently expanded diff result.
    fn get_expanded_result(&self) -> Option<&DiffResult> {
        let flat_idx = self.expanded_idx?;
        let mut current = 0;
        for target in &self.results {
            if current + target.results.len() > flat_idx {
                return target.results.get(flat_idx - current);
            }
            current += target.results.len();
        }
        None
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
                KeyCode::Enter => {
                    self.toggle_expand();
                    true
                }
                _ => false,
            },
            _ => false,
        }
    }

    fn draw(&mut self, f: &mut Frame, area: Rect) {
        // Layout: help bar, content, optional diff panel
        let has_expansion = self.expanded_idx.is_some();
        let layouts = if has_expansion {
            Layout::vertical([
                Constraint::Length(1),  // Help bar
                Constraint::Percentage(50), // Results list
                Constraint::Percentage(50), // Diff detail
            ])
            .split(area)
        } else {
            Layout::vertical([
                Constraint::Length(1), // Help bar
                Constraint::Min(0),    // Results list
            ])
            .split(area)
        };

        // Help bar
        draw_help_bar(f, layouts[0], &drift_hints());

        // Main content area
        let content_area = layouts[1];
        draw_results(f, content_area, &self.results, &self.error, &self.path);

        // Diff detail panel (if expanded)
        if has_expansion && layouts.len() > 2 {
            if let Some(result) = self.get_expanded_result() {
                draw_diff_panel(f, layouts[2], result);
            }
        }
    }

    fn set_cursor_line(&mut self, line: u16) -> bool {
        self.cursor_line = line;
        true
    }

    fn content_height(&self) -> Option<u16> {
        let mut height: u16 = 2; // Help bar + blank

        for target in &self.results {
            height += 1; // Target header
            height += target.results.len() as u16;
            height += 1; // Blank after target
        }

        if self.error.is_some() {
            height += 2;
        }

        // Add space for expanded diff
        if self.expanded_idx.is_some() {
            height += 20; // Reserve space for diff panel
        }

        Some(height.max(10))
    }
}

/// Draws the results list.
fn draw_results(
    f: &mut Frame,
    area: Rect,
    results: &[TargetResult],
    error: &Option<String>,
    path: &str,
) {
    let border = Block::default()
        .title(format!(" Drift: {} ", path))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(colors::HEADER));
    f.render_widget(border, area);

    let inner = area.inner(Margin {
        horizontal: 1,
        vertical: 1,
    });

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

    // Render each target and its results
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
        let target_line = Line::from(vec![
            Span::styled(
                format!("TARGET: {}", target.target),
                Style::default()
                    .fg(colors::SUCCESS)
                    .add_modifier(Modifier::BOLD),
            ),
        ]);
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

        // Results
        for result in &target.results {
            if y >= inner.height {
                break;
            }

            let (icon, icon_color, status) = if result.error.is_some() {
                (ICON_ERROR, colors::ERROR, "error")
            } else if result.diff.is_some() {
                (ICON_CHANGED, colors::DEBUG, "changed")
            } else {
                (ICON_NO_CHANGE, colors::INFO, "no changes")
            };

            let result_line = Line::from(vec![
                Span::raw("  "),
                Span::styled(icon, Style::default().fg(icon_color)),
                Span::raw(" "),
                Span::styled(
                    format!("{}/{}", result.kind, result.resource_name),
                    Style::default().fg(colors::HEADER),
                ),
                Span::raw(" "),
                Span::styled(
                    format!("({})", status),
                    Style::default().fg(colors::GRAY),
                ),
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

/// Draws the diff detail panel.
fn draw_diff_panel(f: &mut Frame, area: Rect, result: &DiffResult) {
    let title = format!(" Diff: {}/{} ", result.kind, result.resource_name);
    let border = Block::default()
        .title(title)
        .borders(Borders::ALL)
        .border_style(Style::default().fg(colors::PENDING));
    f.render_widget(border, area);

    let inner = area.inner(Margin {
        horizontal: 1,
        vertical: 1,
    });

    if let Some(ref err) = result.error {
        let err_line = Line::from(vec![
            Span::styled("Error: ", Style::default().fg(colors::ERROR)),
            Span::raw(err),
        ]);
        f.render_widget(Paragraph::new(err_line), inner);
        return;
    }

    if let Some(ref diff) = result.diff {
        // Render diff with syntax highlighting
        let lines: Vec<Line> = diff
            .lines()
            .enumerate()
            .filter_map(|(i, line)| {
                if i as u16 >= inner.height {
                    return None;
                }

                let style = if line.starts_with('+') && !line.starts_with("+++") {
                    Style::default().fg(colors::INFO) // Green for additions
                } else if line.starts_with('-') && !line.starts_with("---") {
                    Style::default().fg(colors::ERROR) // Red for deletions
                } else if line.starts_with("@@") {
                    Style::default().fg(colors::PENDING) // Purple for hunk headers
                } else {
                    Style::default().fg(colors::GRAY)
                };

                Some(Line::from(Span::styled(line, style)))
            })
            .collect();

        for (i, line) in lines.iter().enumerate() {
            if i as u16 >= inner.height {
                break;
            }
            f.render_widget(
                line.clone(),
                Rect {
                    x: inner.x,
                    y: inner.y + i as u16,
                    width: inner.width,
                    height: 1,
                },
            );
        }
    } else {
        let no_diff = Line::from(Span::styled(
            "No differences",
            Style::default().fg(colors::INFO),
        ));
        f.render_widget(Paragraph::new(no_diff), inner);
    }
}
