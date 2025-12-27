use futures::{AsyncBufReadExt, TryStreamExt};
use k8s_openapi::api::core::v1::Pod;
use k8s_openapi::chrono::{Duration, Utc};
use kube::api::LogParams;
use kube::{Api, Client};
use mlua::{prelude::*, UserData, UserDataMethods};
use regex::Regex;
use std::sync::{
    atomic::{AtomicBool, AtomicUsize, Ordering},
    Arc, Mutex, OnceLock,
};
use tokio::sync::mpsc;

use crate::{block_on, RUNTIME};

/// A highlight mark for a portion of a log line.
#[derive(Debug, Clone)]
pub struct LogMark {
    /// Line offset within the chunk (0-indexed)
    pub line_offset: u16,
    /// Start column (byte offset)
    pub start_col: u16,
    /// End column (byte offset, exclusive)
    pub end_col: u16,
    /// Highlight group name
    pub hl_group: String,
}

/// A chunk of log lines with optional highlight marks.
#[derive(Debug, Clone, Default)]
pub struct LogChunk {
    /// The log lines
    pub lines: Vec<String>,
    /// Highlight marks for the lines
    pub marks: Vec<LogMark>,
}

/// Compiled regex patterns for log parsing
struct LogPatterns {
    /// Kubernetes timestamp: 2024-01-15T10:30:45.123456789Z
    timestamp: Regex,
    /// Log levels: ERROR, WARN, INFO, DEBUG, TRACE (case insensitive)
    level_error: Regex,
    level_warn: Regex,
    level_info: Regex,
    level_debug: Regex,
    /// Container prefix: [container-name]
    container_prefix: Regex,
}

static LOG_PATTERNS: OnceLock<LogPatterns> = OnceLock::new();

fn get_patterns() -> &'static LogPatterns {
    LOG_PATTERNS.get_or_init(|| LogPatterns {
        timestamp: Regex::new(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z?\s?").unwrap(),
        level_error: Regex::new(r"(?i)\b(ERROR|FATAL|PANIC|CRITICAL)\b").unwrap(),
        level_warn: Regex::new(r"(?i)\b(WARN|WARNING)\b").unwrap(),
        level_info: Regex::new(r"(?i)\bINFO\b").unwrap(),
        level_debug: Regex::new(r"(?i)\b(DEBUG|TRACE)\b").unwrap(),
        container_prefix: Regex::new(r"^\[([^\]]+)\]\s").unwrap(),
    })
}

/// Parse a single log line and extract highlight marks.
fn parse_log_line(line: &str, line_offset: u16) -> Vec<LogMark> {
    let patterns = get_patterns();
    let mut marks = Vec::new();
    let mut offset: usize = 0;

    // Check for container prefix first: [container-name]
    if let Some(m) = patterns.container_prefix.find(line) {
        let end = m.end();
        marks.push(LogMark {
            line_offset,
            start_col: 0,
            end_col: end as u16,
            hl_group: "KubectlPending".to_string(), // Magenta for container
        });
        offset = end;
    }

    // Check for timestamp
    let rest = &line[offset..];
    if let Some(m) = patterns.timestamp.find(rest) {
        let start = m.start();
        let end = m.end();
        marks.push(LogMark {
            line_offset,
            start_col: (offset + start) as u16,
            end_col: (offset + end) as u16,
            hl_group: "KubectlGray".to_string(),
        });
    }

    // Check for log levels (search entire line after prefix)
    if let Some(m) = patterns.level_error.find(rest) {
        let start = m.start();
        let end = m.end();
        marks.push(LogMark {
            line_offset,
            start_col: (offset + start) as u16,
            end_col: (offset + end) as u16,
            hl_group: "KubectlError".to_string(),
        });
    } else if let Some(m) = patterns.level_warn.find(rest) {
        let start = m.start();
        let end = m.end();
        marks.push(LogMark {
            line_offset,
            start_col: (offset + start) as u16,
            end_col: (offset + end) as u16,
            hl_group: "KubectlWarning".to_string(),
        });
    } else if let Some(m) = patterns.level_info.find(rest) {
        let start = m.start();
        let end = m.end();
        marks.push(LogMark {
            line_offset,
            start_col: (offset + start) as u16,
            end_col: (offset + end) as u16,
            hl_group: "KubectlInfo".to_string(),
        });
    } else if let Some(m) = patterns.level_debug.find(rest) {
        let start = m.start();
        let end = m.end();
        marks.push(LogMark {
            line_offset,
            start_col: (offset + start) as u16,
            end_col: (offset + end) as u16,
            hl_group: "KubectlDebug".to_string(),
        });
    }

    marks
}

/// A streaming log session that follows pod logs in real-time.
/// Similar to Session in exec.rs but for log streaming.
pub struct LogSession {
    rx_out: Mutex<mpsc::UnboundedReceiver<String>>,
    open: Arc<AtomicBool>,
}

impl LogSession {
    #[tracing::instrument(skip(client))]
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        client: Client,
        ns: String,
        pod_name: String,
        container: Option<String>,
        timestamps: bool,
        since: Option<String>,
        follow: bool,
        previous: bool,
        prefix: Option<bool>,
    ) -> LuaResult<Self> {
        let (tx, rx) = mpsc::unbounded_channel::<String>();
        let open = Arc::new(AtomicBool::new(true));
        let active_count = Arc::new(AtomicUsize::new(0));

        let rt = RUNTIME
            .get()
            .ok_or_else(|| LuaError::runtime("Tokio runtime not initialized"))?;

        // Get pod to find containers
        let pods: Api<Pod> = Api::namespaced(client.clone(), &ns);
        let pod = block_on(async { pods.get(&pod_name).await })
            .map_err(|e| LuaError::external(format!("Failed to get pod {}: {}", pod_name, e)))?;

        let spec = pod
            .spec
            .ok_or_else(|| LuaError::external("Pod has no spec"))?;

        // Collect containers to stream
        let mut containers: Vec<String> = spec.containers.iter().map(|c| c.name.clone()).collect();
        if let Some(init) = spec.init_containers {
            containers.extend(init.iter().map(|c| c.name.clone()));
        }

        // Filter to specific container if requested
        if let Some(ref target) = container {
            containers.retain(|c| c == target);
            if containers.is_empty() {
                return Err(LuaError::external(format!(
                    "Container '{}' not found in pod '{}'",
                    target, pod_name
                )));
            }
        }

        if containers.is_empty() {
            return Err(LuaError::external("No containers in pod"));
        }

        // Parse since duration
        let since_time = since
            .as_deref()
            .and_then(parse_duration)
            .map(|d| Utc::now() - d);

        // If following with no since, use since_seconds=1 to start from "now"
        // If not following, since_time controls the history (None = all logs)
        let since_seconds = if follow && since_time.is_none() {
            Some(1)
        } else {
            None
        };

        // Determine if we need container prefixes
        // If prefix is explicitly set, use that; otherwise auto-detect (multi-container)
        let use_prefix = prefix.unwrap_or(containers.len() > 1);

        // Spawn a streaming task for each container
        for container_name in containers {
            let tx = tx.clone();
            let open = open.clone();
            let active_count = active_count.clone();
            let pods = pods.clone();
            let pod_name = pod_name.clone();
            let container_name_for_prefix = container_name.clone();

            active_count.fetch_add(1, Ordering::SeqCst);

            rt.spawn(async move {
                let lp = LogParams {
                    follow,
                    container: Some(container_name),
                    since_time,
                    since_seconds,
                    timestamps,
                    previous,
                    ..LogParams::default()
                };

                let stream_result = pods.log_stream(&pod_name, &lp).await;
                let stream = match stream_result {
                    Ok(s) => s,
                    Err(e) => {
                        let _ = tx.send(format!("[{}] Error: {}", container_name_for_prefix, e));
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
                                format!("[{}] {}", container_name_for_prefix, line)
                            } else {
                                line
                            };
                            if tx.send(formatted).is_err() {
                                break;
                            }
                        }
                        Ok(None) => {
                            // Stream ended
                            break;
                        }
                        Err(e) => {
                            let _ = tx.send(format!("[{}] Stream error: {}", container_name_for_prefix, e));
                            break;
                        }
                    }
                }

                decrement_and_check(&active_count, &open);
            });
        }

        Ok(LogSession {
            rx_out: Mutex::new(rx),
            open,
        })
    }

    fn read_chunk(&self) -> LuaResult<Option<LogChunk>> {
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
            // Parse each line for highlights
            let mut marks = Vec::new();
            for (i, line) in lines.iter().enumerate() {
                marks.extend(parse_log_line(line, i as u16));
            }

            Ok(Some(LogChunk { lines, marks }))
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
        m.add_method("read_chunk", |lua, this, ()| {
            match this.read_chunk()? {
                Some(chunk) => {
                    let tbl = lua.create_table()?;

                    // Lines array
                    let lines = lua.create_table()?;
                    for (i, line) in chunk.lines.iter().enumerate() {
                        lines.set(i + 1, line.as_str())?;
                    }
                    tbl.set("lines", lines)?;

                    // Marks array
                    let marks = lua.create_table()?;
                    for (i, mark) in chunk.marks.iter().enumerate() {
                        let mark_tbl = lua.create_table()?;
                        mark_tbl.set("line_offset", mark.line_offset)?;
                        mark_tbl.set("start_col", mark.start_col)?;
                        mark_tbl.set("end_col", mark.end_col)?;
                        mark_tbl.set("hl_group", mark.hl_group.as_str())?;
                        marks.set(i + 1, mark_tbl)?;
                    }
                    tbl.set("marks", marks)?;

                    Ok(Some(tbl))
                }
                None => Ok(None),
            }
        });
        m.add_method("open", |_, this, ()| Ok(this.is_open()));
        m.add_method("close", |_, this, ()| {
            this.close();
            Ok(())
        });
    }
}

/// Creates a new log session.
/// - `since`: Duration like "5m", "1h" for historical logs. None with follow=false means all logs.
/// - `follow`: If true, streams continuously. If false, one-shot fetch then closes.
/// - `previous`: If true, fetch logs from the previous container instance.
/// - `prefix`: If Some(true), always add container prefix; if Some(false), never; if None, auto-detect.
#[allow(clippy::too_many_arguments)]
pub fn log_session(
    _lua: &mlua::Lua,
    (ns, pod, container, timestamps, since, follow, previous, prefix): (
        String,
        String,
        Option<String>,
        bool,
        Option<String>,
        bool,
        bool,
        Option<bool>,
    ),
) -> LuaResult<LogSession> {
    crate::with_stream_client(|client| async move {
        LogSession::new(
            client, ns, pod, container, timestamps, since, follow, previous, prefix,
        )
    })
}
