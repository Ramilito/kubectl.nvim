use k8s_openapi::chrono::{DateTime, Utc};
use kube::api::DynamicObject;
use mlua::{Function, Lua, Result, Table};

#[derive(Clone, Copy)]
pub enum AccessorMode {
    Sort,
    Filter,
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
    use std::cmp::Ordering;

    let field = sort_by
        .map(|s| s.trim().to_lowercase())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "namespace".to_owned());

    let order = sort_order
        .map(|s| s.trim().to_lowercase())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "asc".to_owned());

    data.sort_by(|a, b| {
        if field == "namespace" {
            let a_ns = get_field_value(a, "namespace").unwrap_or_default();
            let b_ns = get_field_value(b, "namespace").unwrap_or_default();

            let ns_cmp = if order == "desc" {
                b_ns.cmp(&a_ns)
            } else {
                a_ns.cmp(&b_ns)
            };

            if ns_cmp == Ordering::Equal {
                let a_name = get_field_value(a, "name").unwrap_or_default();
                let b_name = get_field_value(b, "name").unwrap_or_default();
                // Always ascending by name here
                a_name.cmp(&b_name)
            } else {
                ns_cmp
            }
        } else {
            let a_val = get_field_value(a, &field).unwrap_or_default();
            let b_val = get_field_value(b, &field).unwrap_or_default();
            if order == "desc" {
                b_val.cmp(&a_val)
            } else {
                a_val.cmp(&b_val)
            }
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
                get_field_value(item, field).is_some_and(|val| val.contains(filter_value))
            })
        })
        .collect()
}

pub fn debug_print(lua: &Lua, msg: &str) -> Result<()> {
    let globals = lua.globals();
    let vim: Table = globals.get("vim")?;
    let notify: Function = vim.get("notify")?;
    notify.call::<String>(msg)?;
    Ok(())
}
