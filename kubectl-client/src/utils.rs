use jiff::Timestamp;

#[derive(Debug, Clone, Copy)]
pub enum AccessorMode {
    Sort,
    Filter,
}

/// Compute time since a jiff::Timestamp, returning a human-readable string
pub fn time_since_jiff(ts: &Timestamp) -> String {
    let now = jiff::Timestamp::now();
    let span = now.since(*ts);
    let Ok(span) = span else {
        return "unknown".to_string();
    };

    // jiff Span stores duration in the finest unit, we need to decompose manually
    let total_secs = span.get_seconds();
    let days = total_secs / 86400;
    let hours = (total_secs % 86400) / 3600;
    let mins = (total_secs % 3600) / 60;
    let secs = total_secs % 60;

    if days > 365 {
        let years = days / 365;
        format!("{}y{}d", years, days % 365)
    } else if days > 7 {
        format!("{}d", days)
    } else if days > 0 || hours > 23 {
        format!("{}d{}h", days, hours % 24)
    } else if hours > 0 {
        format!("{}h{}m", hours, mins % 60)
    } else if mins > 0 {
        format!("{}m{}s", mins, secs % 60)
    } else {
        format!("{}s", secs)
    }
}

pub fn pad_key(n: usize) -> String {
    format!("{:020}", n)
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct FieldValue {
    pub value: String,
    pub symbol: Option<String>,
    pub sort_by: Option<usize>,
    /// Diagnostic hint message (e.g., container waiting/terminated message)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hint: Option<String>,
}

impl Default for FieldValue {
    fn default() -> Self {
        Self {
            value: "".to_string(),
            symbol: None,
            sort_by: None,
            hint: None,
        }
    }
}
