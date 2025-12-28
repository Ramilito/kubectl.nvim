use futures::{AsyncBufReadExt, TryStreamExt};
use k8s_openapi::api::core::v1::Pod;
use k8s_openapi::chrono::{Duration, Utc};
use k8s_openapi::serde_json;
use kube::api::LogParams;
use kube::{Api, Client};
use mlua::{prelude::*, UserData, UserDataMethods};
use std::sync::{
    atomic::{AtomicBool, AtomicUsize, Ordering},
    Arc, Mutex,
};
use tokio::sync::mpsc;

use crate::structs::{CmdStreamArgs, PodRef};
use crate::{block_on, with_client, RUNTIME};
use k8s_openapi::chrono::DateTime;

/// Unicode block characters for histogram (9 levels: 0-8)
const BAR_CHARS: [char; 9] = [' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];

/// Try to find and parse a K8s timestamp (2024-01-15T10:30:45.123Z format)
fn find_timestamp(line: &str) -> Option<DateTime<Utc>> {
    // Look for pattern: YYYY-MM-DDTHH:MM:SS
    for (i, _) in line.match_indices('T') {
        // Need at least 10 chars before T (YYYY-MM-DD) and 8 after (HH:MM:SS)
        if i < 10 || i + 9 > line.len() {
            continue;
        }

        let start = i - 10;
        // Find end - look for Z or end of timestamp
        let rest = &line[i + 1..];
        let end = if let Some(z_pos) = rest.find('Z') {
            i + 1 + z_pos + 1
        } else {
            continue;
        };

        let candidate = &line[start..end];
        if let Ok(ts) = candidate.parse::<DateTime<Utc>>() {
            return Some(ts);
        }
    }
    None
}

/// Format a timestamp label based on the time range duration.
fn format_time_label(ts: DateTime<Utc>, total_hours: i64) -> String {
    if total_hours < 24 {
        // Less than a day: just show time
        ts.format("%H:%M").to_string()
    } else if total_hours < 24 * 7 {
        // Less than a week: show day and time
        ts.format("%d %H:%M").to_string()
    } else {
        // Week or more: show month-day
        ts.format("%m-%d").to_string()
    }
}

/// Build and render histogram as bar chart lines.
fn render_histogram(
    lines: &[String],
    since_duration: Option<Duration>,
    bucket_count: usize,
) -> Vec<String> {
    if bucket_count == 0 {
        return Vec::new();
    }

    // Collect all timestamps
    let timestamps: Vec<DateTime<Utc>> = lines.iter().filter_map(|l| find_timestamp(l)).collect();

    if timestamps.is_empty() {
        return Vec::new();
    }

    // Determine time range
    let now = Utc::now();
    let start_time = if let Some(dur) = since_duration {
        now - dur
    } else if let Some(min_ts) = timestamps.iter().min() {
        *min_ts
    } else {
        return Vec::new();
    };
    let end_time = now;

    let total_duration = end_time.signed_duration_since(start_time);
    if total_duration.num_seconds() <= 0 {
        return Vec::new();
    }

    let bucket_duration_secs = total_duration.num_seconds() as f64 / bucket_count as f64;

    // Initialize and fill buckets
    let mut buckets = vec![0usize; bucket_count];
    for ts in &timestamps {
        let offset = ts.signed_duration_since(start_time).num_seconds() as f64;
        let bucket_idx = (offset / bucket_duration_secs) as usize;
        let bucket_idx = bucket_idx.min(bucket_count - 1);
        buckets[bucket_idx] += 1;
    }

    let max_count = *buckets.iter().max().unwrap_or(&1).max(&1);

    // Build bar line
    let mut bar_line = String::from("│");
    for count in &buckets {
        let level = ((*count as f64 / max_count as f64) * 8.0 + 0.5) as usize;
        let level = level.min(8);
        bar_line.push(BAR_CHARS[level]);
    }
    bar_line.push('│');

    // Build label line
    let total_hours = total_duration.num_hours();
    let first_label = format_time_label(start_time, total_hours);
    let last_label = format_time_label(end_time, total_hours);
    let padding = bucket_count.saturating_sub(first_label.len() + last_label.len()).max(1);
    let label_line = format!(
        " {}{}{}",
        first_label,
        "─".repeat(padding),
        last_label
    );

    vec![bar_line, label_line]
}

/// A streaming log session that follows pod logs in real-time.
/// Supports multiple pods.
pub struct LogSession {
    rx_out: Mutex<mpsc::UnboundedReceiver<String>>,
    open: Arc<AtomicBool>,
}

impl LogSession {
    #[tracing::instrument(skip(client))]
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        client: Client,
        pods: Vec<PodRef>,
        container: Option<String>,
        timestamps: bool,
        since: Option<String>,
        follow: bool,
        previous: bool,
        prefix: Option<bool>,
    ) -> LuaResult<Self> {
        if pods.is_empty() {
            return Err(LuaError::external("No pods specified"));
        }

        let (tx, rx) = mpsc::unbounded_channel::<String>();
        let open = Arc::new(AtomicBool::new(true));
        let active_count = Arc::new(AtomicUsize::new(0));

        let rt = RUNTIME
            .get()
            .ok_or_else(|| LuaError::runtime("Tokio runtime not initialized"))?;

        // Parse since duration
        let since_time = since
            .as_deref()
            .and_then(parse_duration)
            .map(|d| Utc::now() - d);

        // If following with no since, use since_seconds=1 to start from "now"
        let since_seconds = if follow && since_time.is_none() {
            Some(1)
        } else {
            None
        };

        let multi_pod = pods.len() > 1;
        let use_prefix = prefix.unwrap_or(multi_pod);

        // Spawn streaming tasks for each pod
        for pod_ref in pods {
            let pods_api: Api<Pod> = Api::namespaced(client.clone(), &pod_ref.namespace);
            let pod = match block_on(async { pods_api.get(&pod_ref.name).await }) {
                Ok(p) => p,
                Err(e) => {
                    if !multi_pod {
                        return Err(LuaError::external(format!(
                            "Failed to get pod {}: {}",
                            pod_ref.name, e
                        )));
                    }
                    continue;
                }
            };

            let spec = match pod.spec {
                Some(s) => s,
                None => continue,
            };

            let mut containers: Vec<String> =
                spec.containers.iter().map(|c| c.name.clone()).collect();
            if let Some(init) = spec.init_containers {
                containers.extend(init.iter().map(|c| c.name.clone()));
            }

            if let Some(ref target) = container {
                containers.retain(|c| c == target);
            }

            let multi_container = containers.len() > 1;
            let pod_name = pod_ref.name.clone();

            for container_name in containers {
                let tx = tx.clone();
                let open = open.clone();
                let active_count = active_count.clone();
                let pods_api = pods_api.clone();
                let pod_name = pod_name.clone();
                let container_for_stream = container_name.clone();

                active_count.fetch_add(1, Ordering::SeqCst);

                rt.spawn(async move {
                    let lp = LogParams {
                        follow,
                        container: Some(container_for_stream.clone()),
                        since_time,
                        since_seconds,
                        timestamps,
                        previous,
                        ..LogParams::default()
                    };

                    let stream_result = pods_api.log_stream(&pod_name, &lp).await;
                    let stream = match stream_result {
                        Ok(s) => s,
                        Err(e) => {
                            let _ = tx.send(format!("[{}] Error: {}", pod_name, e));
                            decrement_and_check(&active_count, &open);
                            return;
                        }
                    };

                    let mut lines = stream.lines();
                    loop {
                        if !open.load(Ordering::Acquire) {
                            break;
                        }

                        match lines.try_next().await {
                            Ok(Some(line)) => {
                                let formatted = if use_prefix {
                                    if multi_container {
                                        format!("[{}/{}] {}", pod_name, container_for_stream, line)
                                    } else {
                                        format!("[{}] {}", pod_name, line)
                                    }
                                } else {
                                    line
                                };
                                if tx.send(formatted).is_err() {
                                    break;
                                }
                            }
                            Ok(None) => break,
                            Err(e) => {
                                let _ =
                                    tx.send(format!("[{}] Stream error: {}", pod_name, e));
                                break;
                            }
                        }
                    }

                    decrement_and_check(&active_count, &open);
                });
            }
        }

        Ok(LogSession {
            rx_out: Mutex::new(rx),
            open,
        })
    }

    fn read_chunk(&self) -> LuaResult<Option<Vec<String>>> {
        let mut guard = self
            .rx_out
            .lock()
            .map_err(|_| LuaError::runtime("poisoned rx_out lock"))?;

        let mut lines = Vec::new();
        while let Ok(line) = guard.try_recv() {
            lines.push(line);
            if lines.len() >= 100 {
                break; // Batch limit to prevent blocking
            }
        }

        if lines.is_empty() {
            Ok(None)
        } else {
            Ok(Some(lines))
        }
    }

    fn is_open(&self) -> bool {
        self.open.load(Ordering::Acquire)
    }

    fn close(&self) {
        self.open.store(false, Ordering::Release);
    }
}

fn decrement_and_check(active_count: &Arc<AtomicUsize>, open: &Arc<AtomicBool>) {
    let remaining = active_count.fetch_sub(1, Ordering::SeqCst) - 1;
    if remaining == 0 {
        open.store(false, Ordering::Release);
    }
}

fn parse_duration(s: &str) -> Option<Duration> {
    if s == "0" || s.is_empty() {
        return None;
    }
    if s.len() < 2 {
        return None;
    }
    let (num_str, unit) = s.split_at(s.len() - 1);
    let num: i64 = num_str.parse().ok()?;
    match unit {
        "s" => Some(Duration::seconds(num)),
        "m" => Some(Duration::minutes(num)),
        "h" => Some(Duration::hours(num)),
        _ => None,
    }
}

impl UserData for LogSession {
    fn add_methods<M: UserDataMethods<Self>>(m: &mut M) {
        m.add_method("read_chunk", |_, this, ()| Ok(this.read_chunk()?));
        m.add_method("open", |_, this, ()| Ok(this.is_open()));
        m.add_method("close", |_, this, ()| {
            this.close();
            Ok(())
        });
    }
}

/// Creates a new log session for real-time streaming (follow mode).
/// - `pods`: Table of { name, namespace } entries
/// - `since`: Duration like "5m", "1h" for historical logs. None with follow=false means all logs.
/// - `follow`: If true, streams continuously. If false, one-shot fetch then closes.
/// - `previous`: If true, fetch logs from the previous container instance.
/// - `prefix`: If Some(true), always add pod prefix; if Some(false), never; if None, auto-detect.
#[allow(clippy::too_many_arguments)]
pub fn log_session(
    _lua: &mlua::Lua,
    (pods_table, container, timestamps, since, follow, previous, prefix): (
        Vec<mlua::Table>,
        Option<String>,
        bool,
        Option<String>,
        bool,
        bool,
        Option<bool>,
    ),
) -> LuaResult<LogSession> {
    // Convert Lua tables to PodRef
    let mut pods = Vec::new();
    for tbl in pods_table {
        let name: String = tbl.get("name")?;
        let namespace: String = tbl.get("namespace")?;
        pods.push(PodRef { name, namespace });
    }

    crate::with_stream_client(|client| async move {
        LogSession::new(client, pods, container, timestamps, since, follow, previous, prefix)
    })
}

/// One-shot async log fetch for initial view (non-streaming).
/// Returns JSON array of lines (histogram bar lines prepended to log lines).
#[tracing::instrument]
pub async fn log_stream_async(_lua: mlua::Lua, json: String) -> mlua::Result<String> {
    let args: CmdStreamArgs =
        serde_json::from_str(&json).map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;

    if args.pods.is_empty() {
        return serde_json::to_string(&vec!["No pods specified".to_string()])
            .map_err(|e| mlua::Error::external(format!("json encode error: {e}")));
    }

    let since_duration = args.since_time_input.as_deref().and_then(parse_duration);
    let since_time = since_duration.map(|d| Utc::now() - d);
    let bucket_count = args.width.unwrap_or(50);

    let multi_pod = args.pods.len() > 1;
    let show_prefix = args.prefix.unwrap_or(multi_pod);

    with_client(move |client| async move {
        let mut all_streams = Vec::new();

        for pod_ref in &args.pods {
            let pods_api: Api<Pod> = Api::namespaced(client.clone(), &pod_ref.namespace);
            let pod = match pods_api.get(&pod_ref.name).await {
                Ok(pod) => pod,
                Err(e) => {
                    // For multi-pod, continue with other pods; for single pod, return error
                    if multi_pod {
                        continue;
                    }
                    return serde_json::to_string(&vec![format!(
                        "No pod named {} in {} found: {}",
                        pod_ref.name, pod_ref.namespace, e
                    )])
                    .map_err(|e| mlua::Error::external(format!("json encode error: {e}")));
                }
            };

            let spec = match pod.spec {
                Some(s) => s,
                None => continue,
            };

            let mut containers: Vec<String> =
                spec.containers.iter().map(|c| c.name.clone()).collect();
            if let Some(init) = spec.init_containers {
                containers.extend(init.iter().map(|c| c.name.clone()));
            }

            if let Some(ref target) = args.container {
                containers.retain(|c| c == target);
            }

            let pod_name = pod_ref.name.clone();
            let multi_container = containers.len() > 1;

            for container_name in containers {
                let lp = LogParams {
                    follow: false,
                    container: Some(container_name.clone()),
                    since_time,
                    pretty: true,
                    timestamps: args.timestamps.unwrap_or_default(),
                    previous: args.previous.unwrap_or_default(),
                    ..LogParams::default()
                };

                let s = match pods_api.log_stream(&pod_name, &lp).await {
                    Ok(s) => s,
                    Err(_) => continue,
                };

                let pod_name = pod_name.clone();
                let container_name = container_name.clone();
                let stream = s.lines().map_ok(move |line| {
                    if show_prefix {
                        if multi_container {
                            format!("[{}/{}] {}", pod_name, container_name, line)
                        } else {
                            format!("[{}] {}", pod_name, line)
                        }
                    } else {
                        line.to_string()
                    }
                });
                all_streams.push(stream);
            }
        }

        if all_streams.is_empty() {
            return serde_json::to_string(&vec!["No logs found".to_string()])
                .map_err(|e| mlua::Error::external(format!("json encode error: {e}")));
        }

        let mut combined = futures::stream::select_all(all_streams);
        let mut collected_logs: Vec<String> = Vec::new();

        while let Some(line) = combined.try_next().await? {
            collected_logs.push(line);
        }

        // Render histogram and prepend to logs
        let mut result = render_histogram(&collected_logs, since_duration, bucket_count);
        result.append(&mut collected_logs);

        serde_json::to_string(&result)
            .map_err(|e| mlua::Error::external(format!("json encode error: {e}")))
    })
}
