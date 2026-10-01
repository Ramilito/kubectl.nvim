use std::{
    collections::HashMap,
    sync::{Arc, Mutex, OnceLock},
    time::Duration,
};

use k8s_openapi::{api::core::v1::Node, serde_json::Value};
use kube::{api, Api, Client, ResourceExt};
use tokio::{task::JoinHandle, time};
use tokio_util::sync::CancellationToken;
use tracing::warn;

use super::{
    mark_node_stats_dirty,
    pods::{parse_cpu_to_millicores, parse_memory_to_mib},
};
use crate::{node_stats, processors::node::get_status, store};
use k8s_metrics::{v1beta1::NodeMetrics, QuantityExt};

pub const POLL_INTERVAL: Duration = Duration::from_secs(30);

#[derive(Clone, Debug)]
pub struct NodeStat {
    pub name: String,
    pub status: String,
    pub cpu_pct: f64,
    pub mem_pct: f64,
    /// Allocatable CPU in cores
    pub cpu_allocatable: f64,
    /// Allocatable memory in bytes
    pub mem_allocatable: f64,
}

impl NodeStat {
    pub fn new(name: String, status: String) -> Self {
        Self {
            name,
            status,
            cpu_pct: 0.0,
            mem_pct: 0.0,
            cpu_allocatable: 0.0,
            mem_allocatable: 0.0,
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
                                // Build allocatable (else capacity) map: name → (status, cpu cores, mem bytes)
                                let cap: HashMap<String, (String, f64, i64)> = node_list
                                    .into_iter()
                                    .filter_map(|n| {
                                        let status_ref = n.status.as_ref()?;
                                        let capacity = status_ref.allocatable.as_ref().or(status_ref.capacity.as_ref())?;
                                        let cpu_q = capacity.get("cpu")?;
                                        let mem_q = capacity.get("memory")?;

                                        let cpu_cores = cpu_q.to_f64().unwrap_or(0.0);
                                        let mem_bytes = mem_q.to_memory().unwrap_or(0);
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

                                        let used_cpu = m.usage.cpu.to_f64().unwrap_or(0.0);
                                        let used_mem = m.usage.memory.to_memory().unwrap_or(0).max(0) as f64;
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
                                            cpu_allocatable: *cap_cpu,
                                            mem_allocatable: cap_mem_f,
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

/// A node's pod requests and limits as % of its allocatable: `(requests, limits)`.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct NodeAllocation {
    pub cpu: (f64, f64),
    pub mem: (f64, f64),
}

/// Per-node pod requests/limits from the cluster-wide pod store, like `kubectl describe node`'s
/// "Allocated resources". `None` until the store holds pods.
pub fn node_allocations(nodes: &[NodeStat]) -> Option<HashMap<String, NodeAllocation>> {
    // The initial list is swapped into the store in one step, so non-empty means loaded.
    let pods = store::get("Pod", None).ok().filter(|p| !p.is_empty())?;
    let totals = sum_by_node(pods.iter().map(|p| &p.data));
    let pct = |v: u64, of: f64| if of > 0.0 { v as f64 / of * 100.0 } else { 0.0 };
    let allocations = nodes
        .iter()
        .map(|n| {
            let t = totals.get(n.name.as_str()).copied().unwrap_or_default();
            let (cpu_m, mem_mi) = (n.cpu_allocatable * 1000.0, n.mem_allocatable / 1_048_576.0);
            let cpu = (pct(t[0], cpu_m), pct(t[1], cpu_m));
            let mem = (pct(t[2], mem_mi), pct(t[3], mem_mi));
            (n.name.clone(), NodeAllocation { cpu, mem })
        })
        .collect();
    Some(allocations)
}

/// Sums pod requests/limits per node as `[cpu req, cpu limit]` (millicores) then
/// `[mem req, mem limit]` (MiB), skipping Succeeded/Failed and unscheduled pods.
fn sum_by_node<'a>(pods: impl Iterator<Item = &'a Value>) -> HashMap<&'a str, [u64; 4]> {
    let mut by_node: HashMap<&str, [u64; 4]> = HashMap::new();
    for pod in pods {
        let node = pod["spec"]["nodeName"].as_str().unwrap_or_default();
        let phase = pod["status"]["phase"].as_str();
        if node.is_empty() || matches!(phase, Some("Succeeded" | "Failed")) {
            continue;
        }
        let totals = [
            effective(pod, "requests", "cpu"),
            effective(pod, "limits", "cpu"),
            effective(pod, "requests", "memory"),
            effective(pod, "limits", "memory"),
        ];
        for (sum, v) in by_node.entry(node).or_default().iter_mut().zip(totals) {
            *sum += v;
        }
    }
    by_node
}

/// A pod's effective request/limit of one resource, as the scheduler counts it: containers plus
/// sidecars (`restartPolicy: Always` init containers), or the largest regular init container plus
/// the sidecars before it if that is bigger.
fn effective(pod: &Value, kind: &str, res: &str) -> u64 {
    let parse = match res {
        "cpu" => parse_cpu_to_millicores,
        _ => parse_memory_to_mib,
    };
    let value = |c: &Value| {
        let quantity = c["resources"][kind][res].as_str();
        quantity.and_then(parse).unwrap_or(0)
    };
    let list = |key: &str| pod["spec"][key].as_array().into_iter().flatten();
    let (sidecars, init_peak) = list("initContainers").fold((0, 0), |(side, peak), c| {
        if c["restartPolicy"] == "Always" {
            (side + value(c), peak)
        } else {
            (side, peak.max(side + value(c)))
        }
    });
    (list("containers").map(value).sum::<u64>() + sidecars).max(init_peak)
}

#[cfg(test)]
mod tests {
    use super::*;
    use k8s_openapi::serde_json::json;

    #[test]
    fn sums_pod_requests_and_limits_per_node() {
        let one_cpu = json!({"resources": {"requests": {"cpu": "1"}}});
        let pods = [
            // Two containers plus a 50m sidecar: 100m + 200m + 50m cpu. The 512Mi init container
            // starts after the 64Mi sidecar, so memory is 512Mi + 64Mi, more than 128Mi + 64Mi.
            json!({
                "spec": {
                    "nodeName": "n1",
                    "containers": [
                        {"resources": {
                            "requests": {"cpu": "100m", "memory": "128Mi"},
                            "limits": {"cpu": "1", "memory": "256Mi"},
                        }},
                        {"resources": {"requests": {"cpu": "200m"}}},
                    ],
                    "initContainers": [
                        {
                            "restartPolicy": "Always",
                            "resources": {"requests": {"cpu": "50m", "memory": "64Mi"}},
                        },
                        {"resources": {"requests": {"memory": "512Mi"}}},
                    ],
                },
                "status": {"phase": "Running"},
            }),
            json!({"spec": {"nodeName": "n1", "containers": [one_cpu]}, "status": {"phase": "Running"}}),
            // Ignored: completed, and not scheduled yet.
            json!({"spec": {"nodeName": "n1", "containers": [one_cpu]}, "status": {"phase": "Succeeded"}}),
            json!({"spec": {"containers": [one_cpu]}, "status": {"phase": "Pending"}}),
        ];
        // [cpu req (m), cpu limit (m), mem req (Mi), mem limit (Mi)]
        let expected = HashMap::from([("n1", [1350, 1000, 576, 256])]);
        assert_eq!(sum_by_node(pods.iter()), expected);
    }
}
