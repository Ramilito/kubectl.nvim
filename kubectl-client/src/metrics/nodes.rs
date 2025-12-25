use std::{
    collections::HashMap,
    sync::{Arc, Mutex, OnceLock},
    time::Duration,
};

use k8s_metrics::{v1beta1 as metricsv1, QuantityExt};
use k8s_openapi::api::core::v1::Node;
use kube::{api, Api, Client, ResourceExt};
use tokio::{task::JoinHandle, time};
use tokio_util::sync::CancellationToken;
use tracing::warn;

use super::mark_node_stats_dirty;
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

pub type SharedNodeStats = Arc<Mutex<Vec<NodeStat>>>;

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
        let metrics_api: Api<metricsv1::NodeMetrics> = Api::all(client);

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
                        // capacity map: name → (cpu cores, mem bytes)
                        let mut cap: HashMap<String, (String,f64, i64)> = HashMap::new();
                        for n in node_list {
                            if let (Some(cpu_q), Some(mem_q)) = (
                                n.status
                                    .clone()
                                    .and_then(|s| s.capacity.unwrap().get("cpu").cloned()),
                                n.status
                                    .as_ref()
                                    .and_then(|s| s.capacity.clone().unwrap().get("memory").cloned()),
                            ) {
                                let cpu_cores = cpu_q.to_f64().unwrap_or(0.); // e.g. “4”
                                let mem_bytes = mem_q.to_memory().unwrap_or(0); // bytes
                                let status = get_status(&n);
                                cap.insert(n.name_any(), (status.value, cpu_cores, mem_bytes));
                            }
                        }

                        let mut out = Vec::new();
                        for m in metrics_list {
                            let name = m.metadata.name.unwrap_or_default();
                            if let Some((status, cap_cpu, cap_mem)) = cap.get(&name) {
                                let used_cpu = m.usage.cpu.to_f64().unwrap_or(0.);
                                let used_mem = m.usage.memory.to_memory().unwrap_or(0) as f64;
                                let cap_mem = *cap_mem as f64;

                                let cpu_pct = if *cap_cpu > 0. {
                                    (used_cpu / cap_cpu) * 100.0
                                } else {
                                    0.
                                };

                                let mem_pct = if cap_mem > 0. {
                                    (used_mem / cap_mem) * 100.
                                } else {
                                    0.
                                };

                                out.push(NodeStat {
                                    name,
                                    status: status.to_string(),
                                    cpu_pct,
                                    mem_pct,
                                });
                            }
                        }
                        *stats.lock().unwrap() = out;
                        // Signal that new data is available
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
