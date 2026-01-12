//! Quantity parsing helpers for Kubernetes resource values.

/// Parse Kubernetes CPU quantity string to cores as f64
pub fn parse_cpu_to_cores(s: &str) -> Option<f64> {
    if let Some(n) = s.strip_suffix('m') {
        n.parse::<f64>().ok().map(|v| v / 1000.0)
    } else if let Some(n) = s.strip_suffix('n') {
        n.parse::<f64>().ok().map(|v| v / 1_000_000_000.0)
    } else if let Some(n) = s.strip_suffix('u') {
        n.parse::<f64>().ok().map(|v| v / 1_000_000.0)
    } else {
        s.parse::<f64>().ok()
    }
}

/// Parse Kubernetes memory quantity string to bytes as i64
pub fn parse_memory_to_bytes(s: &str) -> Option<i64> {
    let suffixes: &[(&str, i64)] = &[
        ("Ei", 1024 * 1024 * 1024 * 1024 * 1024 * 1024),
        ("Pi", 1024 * 1024 * 1024 * 1024 * 1024),
        ("Ti", 1024 * 1024 * 1024 * 1024),
        ("Gi", 1024 * 1024 * 1024),
        ("Mi", 1024 * 1024),
        ("Ki", 1024),
        ("E", 1000 * 1000 * 1000 * 1000 * 1000 * 1000),
        ("P", 1000 * 1000 * 1000 * 1000 * 1000),
        ("T", 1000 * 1000 * 1000 * 1000),
        ("G", 1000 * 1000 * 1000),
        ("M", 1000 * 1000),
        ("K", 1000),
        ("k", 1000),
    ];

    for (suffix, multiplier) in suffixes {
        if let Some(n) = s.strip_suffix(suffix) {
            return n.parse::<f64>().ok().map(|v| (v * (*multiplier as f64)).round() as i64);
        }
    }

    s.parse::<i64>().ok()
}
