use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    thread,
    time::Duration,
};

use k8s_metrics::v1beta1 as metricsv1;
use k8s_metrics::QuantityExt;
use k8s_openapi::api::core::v1::Pod;
use kube::{api, Api, Client, ResourceExt};
use tokio::runtime::Runtime;
use tracing::{info, warn};

/// One pod’s metrics as percentages (0–100) of its *requested* resources.
///
/// ── cpu_pct is relative to the summed `resources.requests.cpu`
/// ── mem_pct is relative to the summed `resources.requests.memory`
///
/// If a container / pod has **no requests**, we fall back to `limits`;
/// if neither is present the percentage is reported as 0.
#[derive(Clone, Debug)]
pub struct PodStat {
    pub namespace: String,
    pub name: String,
    pub cpu_pct: f64,
    pub mem_pct: f64,
}
pub type SharedPodStats = Arc<Mutex<Vec<PodStat>>>;

#[tracing::instrument(skip(client))]
pub fn spawn_pod_collector(stats: SharedPodStats, client: Client) {
    thread::spawn(move || {
        let rt = Runtime::new().expect("create runtime for pod collector");

        // helpers
        let pod_api: Api<Pod> = Api::all(client.clone());
        let metrics_api: Api<metricsv1::PodMetrics> = Api::all(client.clone());

        loop {
            let fetch = async {
                let lp = api::ListParams::default();
                tokio::try_join!(pod_api.list(&lp), metrics_api.list(&lp))
            };

            match rt.block_on(fetch) {
                Ok((pod_list, metrics_list)) => {
                    // Map: (namespace, pod) → (cpu request cores, mem request bytes)
                    let mut reqs: HashMap<(String, String), (f64, i64)> = HashMap::new();

                    for p in pod_list {
                        let ns = p.namespace().unwrap_or_default();
                        let name = p.name_any();

                        // sum over all containers
                        let (mut req_cpu, mut req_mem) = (0.0_f64, 0_i64);
                        if let Some(spec) = p.spec {
                            for c in spec.containers {
                                if let Some(res) = c.resources {
                                    // Prefer requests; fall back to limits
                                    if let Some(cpu_q) = res
                                        .requests
                                        .as_ref()
                                        .and_then(|m| m.get("cpu"))
                                        .cloned()
                                        .or_else(|| {
                                            res.limits.as_ref().and_then(|m| m.get("cpu")).cloned()
                                        })
                                    {
                                        req_cpu += cpu_q.to_f64().unwrap_or(0.0);
                                    }
                                    if let Some(mem_q) = res
                                        .requests
                                        .as_ref()
                                        .and_then(|m| m.get("memory"))
                                        .cloned()
                                        .or_else(|| {
                                            res.limits
                                                .as_ref()
                                                .and_then(|m| m.get("memory"))
                                                .cloned()
                                        })
                                    {
                                        req_mem += mem_q.to_memory().unwrap_or(0);
                                    }
                                }
                            }
                        }
                        reqs.insert((ns, name), (req_cpu, req_mem));
                    }

                    // Build output
                    let mut out = Vec::with_capacity(metrics_list.items.len());
                    for m in metrics_list {
                        let ns = m.metadata.namespace.clone().unwrap_or_default();
                        let name = m.metadata.name.clone().unwrap_or_default();
                        let key = (ns.clone(), name.clone());

                        // Sum usage across all containers
                        let (mut used_cpu, mut used_mem) = (0.0_f64, 0_i64);
                        for c in m.containers {
                            used_cpu += c.usage.cpu.to_f64().unwrap_or(0.0);
                            used_mem += c.usage.memory.to_memory().unwrap_or(0);
                        }

                        let (req_cpu, req_mem) = reqs.get(&key).cloned().unwrap_or((0.0, 0));
                        let cpu_pct = if req_cpu > 0.0 {
                            (used_cpu / req_cpu) * 100.0
                        } else {
                            0.0
                        };
                        let mem_pct = if req_mem > 0 {
                            (used_mem as f64 / req_mem as f64) * 100.0
                        } else {
                            0.0
                        };

                        out.push(PodStat {
                            namespace: ns,
                            name,
                            cpu_pct,
                            mem_pct,
                        });
                    }

                    *stats.lock().unwrap() = out;
                    info!(count=?stats.lock().unwrap().len(), "pod stats updated");
                }
                Err(e) => warn!(error=%e, "failed to fetch pod metrics/requests"),
            }

            thread::sleep(Duration::from_secs(5));
        }
    });
}
