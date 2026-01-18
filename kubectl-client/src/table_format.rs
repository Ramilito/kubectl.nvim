//! Table formatting for Neovim buffer display.
//!
//! Converts processed resource rows into formatted lines with extmark positions
//! for syntax highlighting in Neovim buffers.

use std::collections::HashMap;
use std::fmt::Write;

use k8s_openapi::serde_json;
use serde::{Deserialize, Serialize};

use crate::events::{get_semantic_highlight, symbols};

/// Sort configuration for the table header.
#[derive(Debug, Clone, Deserialize)]
pub struct SortBy {
    pub current_word: String,
    pub order: String, // "asc" or "desc"
}

/// Window parameters needed for column width calculation.
#[derive(Debug, Clone, Deserialize)]
pub struct WindowParams {
    pub width: usize,
    pub text_offset: usize,
}

/// An extmark to be applied in the Neovim buffer.
#[derive(Debug, Clone, Serialize)]
pub struct Extmark {
    pub row: usize,
    pub start_col: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub end_col: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hl_group: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub virt_text: Option<Vec<(String, String)>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub virt_text_pos: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hl_mode: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub line_hl_group: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sign_text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sign_hl_group: Option<String>,
}

impl Extmark {
    fn highlight(row: usize, start_col: usize, end_col: usize, hl_group: String) -> Self {
        Self {
            row,
            start_col,
            end_col: Some(end_col),
            hl_group: Some(hl_group),
            virt_text: None,
            virt_text_pos: None,
            hl_mode: None,
            line_hl_group: None,
            sign_text: None,
            sign_hl_group: None,
        }
    }

    fn virt_text(row: usize, start_col: usize, text: Vec<(String, String)>, pos: &str) -> Self {
        Self {
            row,
            start_col,
            end_col: None,
            hl_group: None,
            virt_text: Some(text),
            virt_text_pos: Some(pos.to_string()),
            hl_mode: None,
            line_hl_group: None,
            sign_text: None,
            sign_hl_group: None,
        }
    }

    fn virt_text_with_hl_mode(
        row: usize,
        start_col: usize,
        text: Vec<(String, String)>,
        pos: &str,
        hl_mode: &str,
    ) -> Self {
        Self {
            row,
            start_col,
            end_col: None,
            hl_group: None,
            virt_text: Some(text),
            virt_text_pos: Some(pos.to_string()),
            hl_mode: Some(hl_mode.to_string()),
            line_hl_group: None,
            sign_text: None,
            sign_hl_group: None,
        }
    }
}

/// Result of table formatting.
#[derive(Debug, Clone, Serialize)]
pub struct FormatTableResult {
    pub lines: Vec<String>,
    pub extmarks: Vec<Extmark>,
}

/// Extracted cell data - value and optional highlight.
struct ExtractedCell {
    value: String,
    symbol: Option<String>,
}

/// Single-pass extraction of all cell values with width calculation.
/// Returns (extracted_rows, column_widths) where widths[i] is max width for column i.
#[inline]
fn extract_all_cells(
    rows: &[HashMap<String, serde_json::Value>],
    columns: &[String],
) -> (Vec<Vec<ExtractedCell>>, Vec<usize>) {
    let ncols = columns.len();
    let mut widths = vec![0usize; ncols];
    let mut extracted = Vec::with_capacity(rows.len());

    for row in rows {
        let mut row_cells = Vec::with_capacity(ncols);
        for (col_idx, col) in columns.iter().enumerate() {
            let cell = extract_cell_value(row.get(col));
            widths[col_idx] = widths[col_idx].max(cell.value.len());
            row_cells.push(cell);
        }
        extracted.push(row_cells);
    }

    (extracted, widths)
}

/// Calculate and distribute extra padding across columns.
#[inline]
fn apply_padding(widths: &mut [usize], headers: &[String], window: &WindowParams) {
    let text_width = window.width.saturating_sub(window.text_offset);
    let separator_width = 3;
    let ncols = headers.len();

    // Adjust widths: max of header length and content, plus separator
    let mut total_width = 0;
    for (i, header) in headers.iter().enumerate() {
        widths[i] = widths[i].max(header.len()) + separator_width;
        if i == ncols - 1 {
            widths[i] = widths[i] - separator_width + 1;
        }
        total_width += widths[i];
    }

    // Distribute remaining space
    let total_padding = text_width.saturating_sub(total_width + 2);
    if total_padding == 0 {
        return;
    }

    let base = total_padding / ncols;
    let remainder = total_padding % ncols;
    for (i, w) in widths.iter_mut().enumerate() {
        *w += base + if i < remainder { 1 } else { 0 };
    }
}

/// Format table data into lines and extmarks for Neovim buffer display.
#[tracing::instrument(skip(rows, headers))]
pub fn format_table(
    rows: &[HashMap<String, serde_json::Value>],
    headers: &[String],
    sort_by: Option<&SortBy>,
    window: &WindowParams,
) -> FormatTableResult {
    if headers.is_empty() || rows.is_empty() {
        return FormatTableResult {
            lines: Vec::new(),
            extmarks: Vec::new(),
        };
    }

    let columns: Vec<String> = headers.iter().map(|h| h.to_lowercase()).collect();

    // Single-pass: extract all cells and calculate widths
    let (extracted, mut widths) = extract_all_cells(rows, &columns);
    apply_padding(&mut widths, headers, window);

    // Pre-calculate total line width for capacity
    let total_width: usize = widths.iter().sum();

    let mut lines = Vec::with_capacity(rows.len() + 1);
    let mut extmarks = Vec::with_capacity(rows.len() * columns.len() / 4); // rough estimate

    // Determine effective sort_by
    let effective_sort = sort_by
        .filter(|s| !s.current_word.is_empty())
        .map(|s| (s.current_word.as_str(), s.order.as_str()))
        .unwrap_or_else(|| (headers.first().map(|s| s.as_str()).unwrap_or(""), "asc"));

    // Create header line
    let mut header_line = String::with_capacity(total_width);
    let mut col_position = 0;

    for (i, header) in headers.iter().enumerate() {
        let col_width = widths[i];
        let start_col = col_position;
        let end_col = start_col + header.len() + 1;

        // Add sort indicator
        if header == effective_sort.0 {
            let indicator = if effective_sort.1 == "asc" { "▲" } else { "▼" };
            extmarks.push(Extmark::virt_text(
                0,
                end_col,
                vec![(indicator.to_string(), symbols().header.clone())],
                "overlay",
            ));
        }

        // Add header highlight
        extmarks.push(Extmark::virt_text_with_hl_mode(
            0,
            start_col,
            vec![(format!("{:width$}", header, width = col_width), symbols().header.clone())],
            "overlay",
            "combine",
        ));

        write!(&mut header_line, "{:width$}", header, width = col_width).unwrap();
        col_position += col_width;
    }
    lines.push(header_line);

    // Create data rows from pre-extracted cells
    for (row_index, row_cells) in extracted.iter().enumerate() {
        let mut row_line = String::with_capacity(total_width);
        let mut col_position = 0;

        for (col_idx, cell) in row_cells.iter().enumerate() {
            let col_width = widths[col_idx];

            if let Some(ref hl) = cell.symbol {
                extmarks.push(Extmark::highlight(
                    row_index + 1,
                    col_position,
                    col_position + col_width,
                    hl.clone(),
                ));
            }

            write!(&mut row_line, "{:width$}", cell.value, width = col_width).unwrap();
            col_position += col_width;
        }

        // Add semantic line highlight based on status/phase
        if let Some(hl) = get_row_semantic_highlight(&rows[row_index]) {
            extmarks.push(Extmark {
                row: row_index + 1,
                start_col: 0,
                end_col: None,
                hl_group: None,
                virt_text: None,
                virt_text_pos: None,
                hl_mode: None,
                line_hl_group: Some(hl.to_string()),
                sign_text: None,
                sign_hl_group: None,
            });
        }

        lines.push(row_line);
    }

    FormatTableResult { lines, extmarks }
}

/// Get semantic line highlight for a row based on status/phase field.
#[inline]
fn get_row_semantic_highlight(row: &HashMap<String, serde_json::Value>) -> Option<&'static str> {
    // Check status field first
    if let Some(status) = get_field_value(row, "status") {
        if let Some(hl) = get_semantic_highlight(&status) {
            return Some(hl);
        }
    }
    // Check phase field
    if let Some(phase) = get_field_value(row, "phase") {
        if let Some(hl) = get_semantic_highlight(&phase) {
            return Some(hl);
        }
    }
    None
}

/// Extract string value from a field (handles both {value: x} and plain string).
#[inline]
fn get_field_value(row: &HashMap<String, serde_json::Value>, field: &str) -> Option<String> {
    row.get(field).and_then(|v| {
        if let Some(obj) = v.as_object() {
            obj.get("value").and_then(|v| v.as_str()).map(|s| s.to_string())
        } else {
            v.as_str().map(|s| s.to_string())
        }
    })
}

/// Extract value and optional highlight group from a cell.
#[inline(always)]
fn extract_cell_value(cell: Option<&serde_json::Value>) -> ExtractedCell {
    match cell {
        Some(serde_json::Value::Object(obj)) => ExtractedCell {
            value: obj
                .get("value")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string(),
            symbol: obj
                .get("symbol")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string()),
        },
        Some(serde_json::Value::String(s)) => ExtractedCell {
            value: s.clone(),
            symbol: None,
        },
        Some(v) => ExtractedCell {
            value: v.to_string(),
            symbol: None,
        },
        None => ExtractedCell {
            value: String::new(),
            symbol: None,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_format_empty_table() {
        let result = format_table(
            &[],
            &["NAME".to_string()],
            None,
            &WindowParams {
                width: 100,
                text_offset: 0,
            },
        );
        assert!(result.lines.is_empty());
    }

    #[test]
    fn test_format_simple_table() {
        let mut row: HashMap<String, serde_json::Value> = HashMap::new();
        row.insert("name".to_string(), json!("test-pod"));
        row.insert("status".to_string(), json!("Running"));

        let result = format_table(
            &[row],
            &["NAME".to_string(), "STATUS".to_string()],
            None,
            &WindowParams {
                width: 100,
                text_offset: 0,
            },
        );

        assert_eq!(result.lines.len(), 2); // header + 1 data row
        assert!(result.lines[0].contains("NAME"));
        assert!(result.lines[1].contains("test-pod"));
    }
}
