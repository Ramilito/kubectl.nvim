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
