use futures::{AsyncBufReadExt, TryStreamExt};
use k8s_openapi::api::core::v1::Pod;
use k8s_openapi::chrono::{Duration, Utc};
use kube::api::LogParams;
use kube::{Api, Client};
use mlua::{prelude::*, UserData, UserDataMethods};
use std::sync::{
    atomic::{AtomicBool, AtomicUsize, Ordering},
    Arc, Mutex,
};
use tokio::sync::mpsc;

use crate::{block_on, RUNTIME};

/// A streaming log session that follows pod logs in real-time.
/// Similar to Session in exec.rs but for log streaming.
pub struct LogSession {
    rx_out: Mutex<mpsc::UnboundedReceiver<String>>,
    open: Arc<AtomicBool>,
}

impl LogSession {
    #[tracing::instrument(skip(client))]
    pub fn new(
        client: Client,
        ns: String,
        pod_name: String,
        container: Option<String>,
        timestamps: bool,
        since: Option<String>,
        follow: bool,
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

        // Determine if we need container prefixes (multi-container)
        let use_prefix = containers.len() > 1;

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

    fn read_chunk(&self) -> LuaResult<Option<String>> {
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
            Ok(Some(lines.join("\n")))
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
        m.add_method("read_chunk", |_, this, ()| this.read_chunk());
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
pub fn log_session(
    _lua: &mlua::Lua,
    (ns, pod, container, timestamps, since, follow): (
        String,
        String,
        Option<String>,
        bool,
        Option<String>,
        bool,
    ),
) -> LuaResult<LogSession> {
    crate::with_stream_client(|client| async move {
        LogSession::new(client, ns, pod, container, timestamps, since, follow)
    })
}
