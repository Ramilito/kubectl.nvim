use futures::{AsyncBufReadExt, TryStreamExt};
use k8s_openapi::api::core::v1::Pod;
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
                    follow: true,
                    container: Some(container_name),
                    // Start from now - only capture new logs, not historical
                    since_seconds: Some(1),
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

/// Creates a new log streaming session.
/// Streams start from "now" - only new log entries are captured.
/// For historical logs, use log_stream_async with the since parameter.
pub fn log_session(
    _lua: &mlua::Lua,
    (ns, pod, container, timestamps): (String, String, Option<String>, bool),
) -> LuaResult<LogSession> {
    crate::with_stream_client(|client| async move {
        LogSession::new(client, ns, pod, container, timestamps)
    })
}
