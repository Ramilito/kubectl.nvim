use std::{
    collections::HashMap,
    sync::{Arc, Mutex, OnceLock},
    time::Duration,
};

use k8s_openapi::api::core::v1::Node;
use kube::{api, Api, Client, ResourceExt};
use tokio::{task::JoinHandle, time};
use tokio_util::sync::CancellationToken;
use tracing::warn;

use super::mark_node_stats_dirty;
use super::types::{parse_cpu_to_cores, parse_memory_to_bytes, NodeMetrics};
use crate::{node_stats, processors::node::get_status};

pub const POLL_INTERVAL: Duration = Duration::from_secs(30);

#[derive(Clone, Debug)]
pub struct NodeStat {
    pub name: String,
    pub status: String,
    pub cpu_pct: f64,
    pub mem_pct: f64,
}

impl NodeStat {
    pub fn new(name: String, status: String) -> Self {
        Self {
            name,
            status,
            cpu_pct: 0.0,
            mem_pct: 0.0,
        }
    }

    pub fn push_sample(&mut self, cpu_pct: f64, mem_pct: f64) {
        self.cpu_pct = cpu_pct;
        self.mem_pct = mem_pct;
    }
}

pub type SharedNodeStats = Arc<Mutex<HashMap<String, NodeStat>>>;

struct NodeCollector {
    handle: JoinHandle<()>,
    cancel: CancellationToken,
}

impl NodeCollector {
    #[tracing::instrument(skip(client))]
    fn new(client: Client) -> Self {
        let stats = node_stats().clone();
        let cancel = CancellationToken::new();
        let child = cancel.clone();

        let node_api: Api<Node> = Api::all(client.clone());
        let metrics_api: Api<NodeMetrics> = Api::all(client);

        let handle = tokio::spawn(async move {
            let mut tick = time::interval(POLL_INTERVAL);

            loop {
                tokio::select! {
                    _ = child.cancelled() => break,
                    _ = tick.tick() => {
                        let fetch = async {
                            let lp = api::ListParams::default();
                            tokio::try_join!(
                                node_api.list(&lp),
                                metrics_api.list(&lp)
                            )
                        };

                        match fetch.await {
                            Ok((node_list, metrics_list)) => {
                                // Build capacity map: name → (status, cpu cores, mem bytes)
                                let cap: HashMap<String, (String, f64, i64)> = node_list
                                    .into_iter()
                                    .filter_map(|n| {
                                        let status_ref = n.status.as_ref()?;
                                        let capacity = status_ref.capacity.as_ref()?;
                                        let cpu_q = capacity.get("cpu")?;
                                        let mem_q = capacity.get("memory")?;

                                        let cpu_cores = parse_cpu_to_cores(&cpu_q.0).unwrap_or(0.0);
                                        let mem_bytes = parse_memory_to_bytes(&mem_q.0).unwrap_or(0);
                                        let status = get_status(&n);
                                        Some((n.name_any(), (status.value, cpu_cores, mem_bytes)))
                                    })
                                    .collect();

                                // Build node stats map
                                let out: HashMap<String, NodeStat> = metrics_list
                                    .into_iter()
                                    .filter_map(|m| {
                                        let name = m.metadata.name?;
                                        let (status, cap_cpu, cap_mem) = cap.get(&name)?;

                                        let used_cpu = parse_cpu_to_cores(&m.usage.cpu.0).unwrap_or(0.0);
                                        let used_mem = parse_memory_to_bytes(&m.usage.memory.0).unwrap_or(0).max(0) as f64;
                                        let cap_mem_f = *cap_mem as f64;

                                        let cpu_pct = if *cap_cpu > 0.0 {
                                            (used_cpu / cap_cpu) * 100.0
                                        } else {
                                            0.0
                                        };

                                        let mem_pct = if cap_mem_f > 0.0 {
                                            (used_mem / cap_mem_f) * 100.0
                                        } else {
                                            0.0
                                        };

                                        Some((name.clone(), NodeStat {
                                            name,
                                            status: status.to_string(),
                                            cpu_pct,
                                            mem_pct,
                                        }))
                                    })
                                    .collect();

                                // Swap atomically with proper lock handling
                                match stats.lock() {
                                    Ok(mut guard) => *guard = out,
                                    Err(poisoned) => {
                                        warn!("poisoned node_stats lock, recovering");
                                        *poisoned.into_inner() = out;
                                    }
                                }
                                mark_node_stats_dirty();
                            }
                            Err(e) => warn!(error=%e, "failed to fetch node metrics/capacity"),
                        }
                    }
                }
            }
        });

        Self { handle, cancel }
    }

    fn shutdown(self) {
        self.cancel.cancel();
        self.handle.abort();
    }
}

impl Drop for NodeCollector {
    fn drop(&mut self) {
        self.cancel.cancel();
        self.handle.abort();
    }
}

/* ---------------------------------------------------------------------------
 *  Public spawn / shutdown helpers (match the pod helpers 1‑for‑1)
 * ------------------------------------------------------------------------ */

static COLLECTOR: OnceLock<Mutex<Option<NodeCollector>>> = OnceLock::new();
fn collector_slot() -> &'static Mutex<Option<NodeCollector>> {
    COLLECTOR.get_or_init(|| Mutex::new(None))
}

/// Start (or restart) the singleton node collector.
pub fn spawn_node_collector(client: Client) {
    let mut slot = collector_slot().lock().unwrap();
    if let Some(old) = slot.take() {
        old.shutdown();
    }
    *slot = Some(NodeCollector::new(client));
}

/// Stop it explicitly (e.g. from tests or a clean shutdown path).
pub fn shutdown_node_collector() {
    let mut slot = collector_slot().lock().unwrap();
    if let Some(old) = slot.take() {
        old.shutdown();
    }
}
