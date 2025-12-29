use futures::{AsyncBufReadExt, TryStreamExt};
use k8s_openapi::api::core::v1::{Pod, PodSpec};
use k8s_openapi::chrono::{DateTime, Duration, Utc};
use k8s_openapi::serde_json;
use kube::api::LogParams;
use kube::{Api, Client};
use mlua::{prelude::*, UserData, UserDataMethods};
use tokio::sync::mpsc;

use crate::streaming::{StreamingSession, TaskHandle};
use crate::structs::{LogConfig, PodRef};
use crate::{block_on, with_client, RUNTIME};

// ============================================================================
// Shared Types and Helpers
// ============================================================================

/// A resolved container target ready for log streaming.
struct ResolvedContainer {
    api: Api<Pod>,
    pod_name: String,
    container_name: String,
}

/// Result of resolving log targets from pods.
struct ResolvedTargets {
    containers: Vec<ResolvedContainer>,
    is_multi_container: bool,
    use_prefix: bool,
}

/// Resolve pods and containers into concrete log targets.
/// Handles pod fetching, container discovery, and prefix logic.
async fn resolve_log_targets(
    client: &Client,
    pods: &[PodRef],
    target_container: Option<&str>,
    prefix_override: Option<bool>,
) -> Result<ResolvedTargets, String> {
    if pods.is_empty() {
        return Err("No pods specified".to_string());
    }

    let is_multi_pod = pods.len() > 1;
    let mut containers = Vec::new();
    let mut total_containers = 0;

    for pod_ref in pods {
        let api: Api<Pod> = Api::namespaced(client.clone(), &pod_ref.namespace);

        let pod = match api.get(&pod_ref.name).await {
            Ok(pod) => pod,
            Err(e) => {
                if is_multi_pod {
                    continue; // Skip failed pods in multi-pod mode
                }
                return Err(format!(
                    "Failed to get pod {} in {}: {}",
                    pod_ref.name, pod_ref.namespace, e
                ));
            }
        };

        let spec = match pod.spec {
            Some(s) => s,
            None => continue,
        };

        let container_names = get_container_names(&spec, target_container);
        total_containers += container_names.len();

        for container_name in container_names {
            containers.push(ResolvedContainer {
                api: api.clone(),
                pod_name: pod_ref.name.clone(),
                container_name,
            });
        }
    }

    let is_multi_container = total_containers > 1;
    let use_prefix = prefix_override.unwrap_or(is_multi_pod);

    Ok(ResolvedTargets {
        containers,
        is_multi_container,
        use_prefix,
    })
}

/// Extract container names from a pod spec, optionally filtering to a target.
fn get_container_names(spec: &PodSpec, target: Option<&str>) -> Vec<String> {
    let mut names: Vec<String> = spec.containers.iter().map(|c| c.name.clone()).collect();
    if let Some(init) = &spec.init_containers {
        names.extend(init.iter().map(|c| c.name.clone()));
    }
    if let Some(target) = target {
        names.retain(|name| name == target);
    }
    names
}

/// Format a log line with optional pod/container prefix.
fn format_log_line(
    line: &str,
    pod_name: &str,
    container_name: &str,
    use_prefix: bool,
    is_multi_container: bool,
) -> String {
    if !use_prefix {
        return line.to_string();
    }
    if is_multi_container {
        format!("[{}/{}] {}", pod_name, container_name, line)
    } else {
        format!("[{}] {}", pod_name, line)
    }
}

/// Parse a duration string like "5m", "1h", "30s".
fn parse_duration(input: &str) -> Option<Duration> {
    if input.is_empty() || input == "0" || input.len() < 2 {
        return None;
    }
    let (num_str, unit) = input.split_at(input.len() - 1);
    let num: i64 = num_str.parse().ok()?;
    match unit {
        "s" => Some(Duration::seconds(num)),
        "m" => Some(Duration::minutes(num)),
        "h" => Some(Duration::hours(num)),
        _ => None,
    }
}

// ============================================================================
// Histogram Rendering
// ============================================================================

/// Unicode block characters for histogram (9 levels: 0-8)
const HISTOGRAM_BAR_CHARS: [char; 9] = [' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];

/// Default number of histogram buckets
const DEFAULT_HISTOGRAM_BUCKETS: usize = 50;

/// Try to find and parse a K8s timestamp (2024-01-15T10:30:45.123Z format)
fn find_timestamp(line: &str) -> Option<DateTime<Utc>> {
    for (i, _) in line.match_indices('T') {
        if i < 10 || i + 9 > line.len() {
            continue;
        }

        let start = i - 10;
        let rest = &line[i + 1..];
        let end = rest.find('Z').map(|z_pos| i + 1 + z_pos + 1)?;

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
        ts.format("%H:%M").to_string()
    } else if total_hours < 24 * 7 {
        ts.format("%d %H:%M").to_string()
    } else {
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

    let timestamps: Vec<DateTime<Utc>> = lines.iter().filter_map(|l| find_timestamp(l)).collect();
    if timestamps.is_empty() {
        return Vec::new();
    }

    let now = Utc::now();
    let start_time = match since_duration
        .map(|dur| now - dur)
        .or_else(|| timestamps.iter().min().copied())
    {
        Some(t) => t,
        None => return Vec::new(),
    };
    let end_time = now;

    let total_duration = end_time.signed_duration_since(start_time);
    if total_duration.num_seconds() <= 0 {
        return Vec::new();
    }

    let bucket_duration_secs = total_duration.num_seconds() as f64 / bucket_count as f64;

    let mut buckets = vec![0usize; bucket_count];
    for ts in &timestamps {
        let offset = ts.signed_duration_since(start_time).num_seconds() as f64;
        let bucket_idx = ((offset / bucket_duration_secs) as usize).min(bucket_count - 1);
        buckets[bucket_idx] += 1;
    }

    let max_count = *buckets.iter().max().unwrap_or(&1).max(&1);

    // Build bar line
    let mut bar_line = String::from("│");
    for count in &buckets {
        let level = ((*count as f64 / max_count as f64) * 8.0 + 0.5) as usize;
        bar_line.push(HISTOGRAM_BAR_CHARS[level.min(8)]);
    }
    bar_line.push('│');

    // Build label line
    let total_hours = total_duration.num_hours();
    let first_label = format_time_label(start_time, total_hours);
    let last_label = format_time_label(end_time, total_hours);
    let padding = bucket_count
        .saturating_sub(first_label.len() + last_label.len())
        .max(1);
    let label_line = format!(" {}{}{}",  first_label, "─".repeat(padding), last_label);

    vec![bar_line, label_line]
}

// ============================================================================
// Streaming Log Session
// ============================================================================

/// Maximum lines to read in a single chunk to prevent blocking.
const MAX_CHUNK_SIZE: usize = 100;

/// A streaming log session that follows pod logs in real-time.
pub struct LogSession {
    session: StreamingSession<String>,
}

impl LogSession {
    #[tracing::instrument(skip(client))]
    pub fn new(client: Client, config: LogConfig) -> LuaResult<Self> {
        let targets = block_on(async {
            resolve_log_targets(
                &client,
                &config.pods,
                config.container.as_deref(),
                config.prefix,
            )
            .await
        })
        .map_err(LuaError::external)?;

        if targets.containers.is_empty() {
            return Err(LuaError::external("No containers found"));
        }

        let session = StreamingSession::new();
        let runtime = RUNTIME
            .get()
            .ok_or_else(|| LuaError::runtime("Tokio runtime not initialized"))?;

        let since_time = config.since.as_deref().and_then(parse_duration).map(|d| Utc::now() - d);

        // If following with no since, use since_seconds=1 to start from "now"
        let follow = config.follow.unwrap_or(false);
        let since_seconds = if follow && since_time.is_none() {
            Some(1)
        } else {
            None
        };

        let params = ContainerLogParams {
            follow,
            since_time,
            since_seconds,
            timestamps: config.timestamps.unwrap_or(false),
            previous: config.previous.unwrap_or(false),
            use_prefix: targets.use_prefix,
            is_multi_container: targets.is_multi_container,
        };

        for target in targets.containers {
            spawn_container_log_task(
                runtime,
                target,
                session.sender(),
                session.task_handle(),
                params,
            );
        }

        Ok(LogSession { session })
    }

    fn read_chunk(&self) -> LuaResult<Option<Vec<String>>> {
        let lines = self
            .session
            .try_recv_batch(MAX_CHUNK_SIZE)
            .map_err(|e| LuaError::runtime(e.to_string()))?;

        if lines.is_empty() {
            Ok(None)
        } else {
            Ok(Some(lines))
        }
    }

    fn is_open(&self) -> bool {
        self.session.is_open()
    }

    fn close(&self) {
        self.session.close();
    }
}

impl UserData for LogSession {
    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method("read_chunk", |_, this, ()| this.read_chunk());
        methods.add_method("open", |_, this, ()| Ok(this.is_open()));
        methods.add_method("close", |_, this, ()| {
            this.close();
            Ok(())
        });
    }
}

/// Parameters for a container log streaming task.
#[derive(Clone, Copy)]
struct ContainerLogParams {
    follow: bool,
    since_time: Option<DateTime<Utc>>,
    since_seconds: Option<i64>,
    timestamps: bool,
    previous: bool,
    use_prefix: bool,
    is_multi_container: bool,
}

/// Spawn an async task that streams logs from a single container.
fn spawn_container_log_task(
    runtime: &tokio::runtime::Runtime,
    target: ResolvedContainer,
    log_sender: mpsc::UnboundedSender<String>,
    task_handle: TaskHandle,
    params: ContainerLogParams,
) {
    // Guard automatically decrements task count when dropped
    let _guard = task_handle.guard();

    runtime.spawn(async move {
        // Move guard into async block so it's dropped when task completes
        let _guard = _guard;

        let log_params = LogParams {
            follow: params.follow,
            container: Some(target.container_name.clone()),
            since_time: params.since_time,
            since_seconds: params.since_seconds,
            timestamps: params.timestamps,
            previous: params.previous,
            ..LogParams::default()
        };

        let log_stream = match target.api.log_stream(&target.pod_name, &log_params).await {
            Ok(stream) => stream,
            Err(e) => {
                let _ = log_sender.send(format!("[{}] Error: {}", target.pod_name, e));
                return;
            }
        };

        let mut lines = log_stream.lines();
        loop {
            if !task_handle.is_active() {
                break;
            }

            match lines.try_next().await {
                Ok(Some(line)) => {
                    let formatted = format_log_line(
                        &line,
                        &target.pod_name,
                        &target.container_name,
                        params.use_prefix,
                        params.is_multi_container,
                    );
                    if log_sender.send(formatted).is_err() {
                        break;
                    }
                }
                Ok(None) => break,
                Err(e) => {
                    let _ = log_sender.send(format!("[{}] Stream error: {}", target.pod_name, e));
                    break;
                }
            }
        }
    });
}

// ============================================================================
// FFI Entry Points
// ============================================================================

/// Creates a new log session for real-time streaming.
/// Accepts a single table with configuration options.
pub fn log_session(_lua: &mlua::Lua, config: LogConfig) -> LuaResult<LogSession> {
    crate::with_stream_client(|client| async move { LogSession::new(client, config) })
}

/// One-shot async log fetch for initial view (non-streaming).
/// Returns JSON array of lines (histogram bar lines prepended to log lines).
#[tracing::instrument]
pub async fn fetch_logs_async(_lua: mlua::Lua, json: String) -> mlua::Result<String> {
    let config: LogConfig = serde_json::from_str(&json)
        .map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;

    let bucket_count = config.histogram_width.unwrap_or(DEFAULT_HISTOGRAM_BUCKETS);
    let since_duration = config.since.as_deref().and_then(parse_duration);
    let since_time = since_duration.map(|d| Utc::now() - d);

    with_client(move |client| async move {
        let targets = resolve_log_targets(
            &client,
            &config.pods,
            config.container.as_deref(),
            config.prefix,
        )
        .await
        .map_err(|e| mlua::Error::external(e))?;

        if targets.containers.is_empty() {
            return serde_json::to_string(&vec!["No logs found".to_string()])
                .map_err(|e| mlua::Error::external(format!("json encode error: {e}")));
        }

        let mut all_streams = Vec::new();

        for target in targets.containers {
            let log_params = LogParams {
                follow: false,
                container: Some(target.container_name.clone()),
                since_time,
                pretty: true,
                timestamps: config.timestamps.unwrap_or(false),
                previous: config.previous.unwrap_or(false),
                ..LogParams::default()
            };

            let log_stream = match target.api.log_stream(&target.pod_name, &log_params).await {
                Ok(stream) => stream,
                Err(_) => continue,
            };

            let pod_name = target.pod_name;
            let container_name = target.container_name;
            let use_prefix = targets.use_prefix;
            let is_multi_container = targets.is_multi_container;

            let stream = log_stream.lines().map_ok(move |line| {
                format_log_line(&line, &pod_name, &container_name, use_prefix, is_multi_container)
            });
            all_streams.push(stream);
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

        let mut result = render_histogram(&collected_logs, since_duration, bucket_count);
        result.append(&mut collected_logs);

        serde_json::to_string(&result)
            .map_err(|e| mlua::Error::external(format!("json encode error: {e}")))
    })
}

// ============================================================================
// JSON Toggle (unrelated utility, kept for compatibility)
// ============================================================================

#[derive(Debug, Clone)]
pub struct ToggleJsonResult {
    pub json: String,
    pub start_idx: usize,
    pub end_idx: usize,
}

/// Find JSON in a string and toggle between pretty/minified format.
/// Indices are 1-based for Lua compatibility.
pub fn toggle_json(input: &str) -> Option<ToggleJsonResult> {
    let bytes = input.as_bytes();
    let mut depth = 0;
    let mut start = None;

    for (i, &byte) in bytes.iter().enumerate() {
        match byte {
            b'{' => {
                if depth == 0 {
                    start = Some(i);
                }
                depth += 1;
            }
            b'}' => {
                depth -= 1;
                if depth == 0 {
                    if let Some(start_pos) = start {
                        let candidate = &input[start_pos..=i];
                        if let Ok(value) = serde_json::from_str::<serde_json::Value>(candidate) {
                            let json = if candidate.contains('\n') {
                                serde_json::to_string(&value)
                            } else {
                                serde_json::to_string_pretty(&value)
                            }
                            .ok()?;

                            return Some(ToggleJsonResult {
                                json,
                                start_idx: start_pos + 1,
                                end_idx: i + 1,
                            });
                        }
                    }
                    start = None;
                }
            }
            _ => {}
        }
    }
    None
}
