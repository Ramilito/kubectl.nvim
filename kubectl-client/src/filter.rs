/// Filter `data` according to a comma-separated pattern list.
///
/// * Multiple patterns are separated by commas (`,`)
/// * Prefix a pattern with `!` for **negative** filtering
/// * **All** patterns must match for the row to be kept
///
/// A *pattern matches* an item when **any** of the supplied `fields`
/// contains the pattern’s text.
///
/// ```text
/// "foo,!bar,baz"
/// └── keep rows that
///     ├─ contain "foo"
///     ├─ contain "baz"
///     └─ do **not** contain "bar"
/// ```
#[tracing::instrument(skip(data, get_field_value))]
pub fn filter_dynamic<'a, T, F>(
    data: &'a [T],
    patterns: &str,
    fields: &[&str],
    get_field_value: F,
) -> Vec<&'a T>
where
    F: Fn(&T, &str) -> Option<String>,
{
    // ── 1. Split and normalize the pattern list ──────────────────────────────
    let compiled: Vec<(bool /* negative? */, String /* text */)> = patterns
        .split(',')
        .filter_map(|raw| {
            // ignore empty segments caused by stray commas
            let raw = raw.trim();
            if raw.is_empty() {
                return None;
            }
            let negative = raw.starts_with('!');
            let text = if negative { &raw[1..] } else { raw };
            Some((negative, text.to_owned()))
        })
        .collect();

    // ── 2. Apply the AND-over-patterns / OR-over-fields logic ────────────────
    data.iter()
        .filter(|item| {
            compiled.iter().all(|(negative, pat)| {
                let found = fields.iter().any(|field| {
                    get_field_value(item, field)
                        .as_deref()
                        .is_some_and(|val| val.contains(pat))
                });

                if *negative {
                    // Negative pattern: *must not* be found
                    !found
                } else {
                    // Positive pattern: *must* be found
                    found
                }
            })
        })
        .collect()
}
