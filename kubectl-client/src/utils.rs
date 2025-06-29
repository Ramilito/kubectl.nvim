use k8s_openapi::chrono::{DateTime, Utc};

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
