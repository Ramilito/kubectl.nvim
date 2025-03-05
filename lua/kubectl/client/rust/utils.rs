use k8s_openapi::chrono::{DateTime, Utc};
use kube::api::DynamicObject;

pub fn strip_managed_fields(obj: &mut DynamicObject) {
    obj.metadata.managed_fields = None;
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

pub fn sort_dynamic<T, F>(
    data: &mut [T],
    sort_by: Option<String>,
    sort_order: Option<String>,
    get_field_value: F,
) where
    F: Fn(&T, &str) -> Option<String>,
{
    let field = sort_by
        .and_then(|s| {
            let trimmed = s.trim();
            if trimmed.is_empty() {
                Some("namespace".to_owned())
            } else {
                Some(trimmed.to_lowercase())
            }
        })
        .unwrap_or_else(|| "namespace".to_owned());

    let order = sort_order
        .and_then(|s| {
            let trimmed = s.trim();
            if trimmed.is_empty() {
                Some("asc".to_owned())
            } else {
                Some(trimmed.to_lowercase())
            }
        })
        .unwrap_or_else(|| "asc".to_owned());

    data.sort_by(|a, b| {
        let a_val = get_field_value(a, &field).unwrap_or_default();
        let b_val = get_field_value(b, &field).unwrap_or_default();
        if order == "desc" {
            b_val.cmp(&a_val)
        } else {
            a_val.cmp(&b_val)
        }
    });
}

pub fn filter_dynamic<'a, T, F>(
    data: &'a [T],
    filter_value: &str,
    fields: &[&str],
    get_field_value: F,
) -> Vec<&'a T>
where
    F: Fn(&T, &str) -> Option<String>,
{
    data.iter()
        .filter(|item| {
            fields.iter().any(|field| {
                get_field_value(item, field).map_or(false, |val| val.contains(filter_value))
            })
        })
        .collect()
}
