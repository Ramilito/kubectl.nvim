use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    thread,
    time::Duration,
};

use k8s_metrics::v1beta1 as metricsv1;
use k8s_metrics::QuantityExt;
use k8s_openapi::api::core::v1::Node;
use kube::{api, Api, Client, ResourceExt};
use tokio::runtime::Runtime;
use tracing::{info, warn};

/// One node’s metrics as percentages (0–100).
#[derive(Clone, Debug)]
pub struct NodeStat {
    pub name: String,
    pub cpu_pct: f64,
    pub mem_pct: f64,
}
pub type SharedStats = Arc<Mutex<Vec<NodeStat>>>;

#[tracing::instrument(skip(client))]
pub fn spawn_node_collector(stats: SharedStats, client: Client) {
    thread::spawn(move || {
        let rt = Runtime::new().expect("create runtime for node collector");

        // helpers
        let node_api: Api<Node> = Api::all(client.clone());
        let metrics_api: Api<metricsv1::NodeMetrics> = Api::all(client.clone());

        loop {
            let fetch = async {
                let lp = api::ListParams::default();
                let caps_fut = node_api.list(&lp);
                let usage_fut = metrics_api.list(&lp);
                tokio::try_join!(caps_fut, usage_fut)
            };

            match rt.block_on(fetch) {
                Ok((node_list, metrics_list)) => {
                    // capacity map: name → (cpu cores, mem bytes)
                    let mut cap: HashMap<String, (f64, i64)> = HashMap::new();
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
                            cap.insert(n.name_any(), (cpu_cores, mem_bytes));
                        }
                    }

                    let mut out = Vec::new();
                    for m in metrics_list {
                        let name = m.metadata.name.unwrap_or_default();
                        if let Some((cap_cpu, cap_mem)) = cap.get(&name) {
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
                                cpu_pct,
                                mem_pct,
                            });
                        }
                    }
                    *stats.lock().unwrap() = out;
                }
                Err(e) => warn!(error=%e, "failed to fetch node metrics/capacity"),
            }

            thread::sleep(Duration::from_secs(5));
        }
    });
}
