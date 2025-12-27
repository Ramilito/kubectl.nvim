use k8s_openapi::chrono::{DateTime, Utc};
use k8s_openapi::serde_json;

#[derive(Debug, Clone, Copy)]
pub enum AccessorMode {
    Sort,
    Filter,
}

pub fn pad_key(n: usize) -> String {
    format!("{:020}", n)
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct FieldValue {
    pub value: String,
    pub symbol: Option<String>,
    pub sort_by: Option<usize>,
}
// Implement Default
impl Default for FieldValue {
    fn default() -> Self {
        Self {
            value: "".to_string(),
            symbol: None,
            sort_by: None,
        }
    }
}

pub fn time_since(ts_str: &str) -> String {
    if let Ok(ts) = ts_str.parse::<DateTime<Utc>>() {
        let now = Utc::now();
        let diff = now.signed_duration_since(ts);

        if diff.num_seconds() < 0 {
            return "In the future".to_string();
        }

        // Extract units
        let days = diff.num_days();
        let years = days / 365;
        let hours = diff.num_hours() % 24;
        let minutes = diff.num_minutes() % 60;
        let seconds = diff.num_seconds() % 60;

        // Format based on size
        if days > 365 {
            format!("{}y{}d", years, days % 365)
        } else if days > 7 {
            format!("{}d", days)
        } else if days > 0 || hours > 23 {
            format!("{}d{}h", days, hours)
        } else if hours > 0 {
            format!("{}h{}m", hours, minutes)
        } else {
            format!("{}m{}s", minutes, seconds)
        }
    } else {
        "".to_string()
    }
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct FormattedJson {
    pub formatted: String,
    pub start_idx: usize,
    pub end_idx: usize,
}

/// Find and format JSON in a string.
/// Returns formatted JSON with start/end indices, or None if no valid JSON found.
/// Indices are 1-based for Lua compatibility.
pub fn format_json(input: &str) -> Option<FormattedJson> {
    let bytes = input.as_bytes();

    for (start, _) in bytes.iter().enumerate().filter(|(_, &b)| b == b'{') {
        let mut depth = 0;
        for (i, &b) in bytes[start..].iter().enumerate() {
            match b {
                b'{' => depth += 1,
                b'}' => {
                    depth -= 1;
                    if depth == 0 {
                        let end = start + i + 1;
                        let candidate = &input[start..end];

                        if let Ok(value) = serde_json::from_str::<serde_json::Value>(candidate) {
                            if let Ok(formatted) = serde_json::to_string_pretty(&value) {
                                // Return 1-based indices for Lua
                                return Some(FormattedJson {
                                    formatted,
                                    start_idx: start + 1,
                                    end_idx: end,
                                });
                            }
                        }
                        break;
                    }
                }
                _ => {}
            }
        }
    }

    None
}
