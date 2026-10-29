use std::{
    collections::HashMap,
    sync::{Arc, Mutex, OnceLock},
    time::Duration,
};

use k8s_openapi::api::core::v1::{Container, Node, Pod, PodSpec};
use kube::{api, Api, Client, ResourceExt};
use tokio::{task::JoinHandle, time};
use tokio_util::sync::CancellationToken;
use tracing::warn;

use super::{
    mark_node_stats_dirty,
    pods::{parse_cpu_to_millicores, parse_memory_to_mib},
};
use crate::{node_stats, processors::node::get_status};
use k8s_metrics::{v1beta1::NodeMetrics, QuantityExt};

pub const POLL_INTERVAL: Duration = Duration::from_secs(30);

#[derive(Clone, Debug)]
pub struct NodeStat {
    pub name: String,
    pub status: String,
    pub cpu_pct: f64,
    pub mem_pct: f64,
    /// Pod requests and limits as percentages of allocatable resources.
    pub allocation: Option<NodeAllocation>,
}

impl NodeStat {
    pub fn new(name: String, status: String) -> Self {
        Self {
            name,
            status,
            cpu_pct: 0.0,
            mem_pct: 0.0,
            allocation: None,
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
        let metrics_api: Api<NodeMetrics> = Api::all(client.clone());
        let pod_api: Api<Pod> = Api::all(client);

        let handle = tokio::spawn(async move {
            let mut tick = time::interval(POLL_INTERVAL);

            loop {
                tokio::select! {
                    _ = child.cancelled() => break,
                    _ = tick.tick() => {
                        let lp = api::ListParams::default();
                        let (metrics_result, pods_result) = tokio::join!(
                            async { tokio::try_join!(node_api.list(&lp), metrics_api.list(&lp)) },
                            pod_api.list(&lp),
                        );
                        let pods = match pods_result {
                            Ok(list) => Some(list.items),
                            Err(error) => {
                                warn!(%error, "failed to fetch node allocations");
                                None
                            }
                        };

                        match metrics_result {
                            Ok((node_list, metrics_list)) => {
                                let out = build_node_stats(node_list.items, metrics_list.items, pods);

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

/// Requests and limits, expressed as percentages in a node snapshot.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct ResourceAllocation {
    pub requests: f64,
    pub limits: f64,
}

impl ResourceAllocation {
    fn percent_of(self, allocatable: f64) -> Self {
        Self {
            requests: percentage(self.requests, allocatable),
            limits: percentage(self.limits, allocatable),
        }
    }

    fn for_pod(spec: &PodSpec, resource: &str, parse: fn(&str) -> Option<u64>) -> Self {
        let quantity = |container: &Container, limits| {
            let Some(resources) = &container.resources else {
                return 0;
            };
            let quantities = if limits {
                &resources.limits
            } else {
                &resources.requests
            };
            quantities
                .as_ref()
                .and_then(|values| values.get(resource))
                .and_then(|value| parse(&value.0))
                .unwrap_or(0)
        };
        Self {
            requests: effective_resource(spec, |container| quantity(container, false)) as f64,
            limits: effective_resource(spec, |container| quantity(container, true)) as f64,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct NodeAllocation {
    pub cpu: ResourceAllocation,
    pub mem: ResourceAllocation,
}

fn percentage(value: f64, total: f64) -> f64 {
    if total > 0.0 {
        value / total * 100.0
    } else {
        0.0
    }
}

/// Build one snapshot; a successful empty pod list means zero allocation, while a
/// failed pod list leaves allocation unavailable without discarding usage metrics.
fn build_node_stats(
    nodes: Vec<Node>,
    metrics: Vec<NodeMetrics>,
    pods: Option<Vec<Pod>>,
) -> HashMap<String, NodeStat> {
    let allocations = pods.as_ref().map(|pods| sum_by_node(pods));
    let nodes: HashMap<_, _> = nodes
        .into_iter()
        .map(|node| (node.name_any(), node))
        .collect();
    metrics
        .into_iter()
        .filter_map(|metrics| {
            let name = metrics.metadata.name?;
            let node = nodes.get(&name)?;
            let status = node.status.as_ref()?;
            let allocatable = status.allocatable.as_ref().or(status.capacity.as_ref())?;
            let cpu = allocatable.get("cpu")?.to_f64().unwrap_or(0.0);
            let mem = allocatable.get("memory")?.to_memory().unwrap_or(0) as f64;
            let allocation = allocations.as_ref().map(|totals| {
                let total = totals.get(name.as_str()).copied().unwrap_or_default();
                NodeAllocation {
                    cpu: total.cpu.percent_of(cpu * 1000.0),
                    mem: total.mem.percent_of(mem / 1_048_576.0),
                }
            });
            Some((
                name.clone(),
                NodeStat {
                    name,
                    status: get_status(node).value,
                    cpu_pct: percentage(metrics.usage.cpu.to_f64().unwrap_or(0.0), cpu),
                    mem_pct: percentage(
                        metrics.usage.memory.to_memory().unwrap_or(0).max(0) as f64,
                        mem,
                    ),
                    allocation,
                },
            ))
        })
        .collect()
}

/// Totals use millicores and MiB until converted to percentages in the snapshot.
fn sum_by_node(pods: &[Pod]) -> HashMap<&str, NodeAllocation> {
    let mut totals: HashMap<&str, NodeAllocation> = HashMap::new();
    for pod in pods {
        let Some(spec) = &pod.spec else { continue };
        let Some(node) = spec.node_name.as_deref().filter(|name| !name.is_empty()) else {
            continue;
        };
        if matches!(
            pod.status
                .as_ref()
                .and_then(|status| status.phase.as_deref()),
            Some("Succeeded" | "Failed")
        ) {
            continue;
        }
        let total = totals.entry(node).or_default();
        let cpu = ResourceAllocation::for_pod(spec, "cpu", parse_cpu_to_millicores);
        let mem = ResourceAllocation::for_pod(spec, "memory", parse_memory_to_mib);
        total.cpu.requests += cpu.requests;
        total.cpu.limits += cpu.limits;
        total.mem.requests += mem.requests;
        total.mem.limits += mem.limits;
    }
    totals
}

/// Account for concurrent app containers and sidecars, or the peak init phase.
fn effective_resource(spec: &PodSpec, quantity: impl Fn(&Container) -> u64) -> u64 {
    let mut sidecars = 0;
    let mut init_peak = 0;
    for container in spec.init_containers.iter().flatten() {
        let value = quantity(container);
        if container.restart_policy.as_deref() == Some("Always") {
            sidecars += value;
        } else {
            init_peak = init_peak.max(sidecars + value);
        }
    }
    (spec.containers.iter().map(quantity).sum::<u64>() + sidecars).max(init_peak)
}

#[cfg(test)]
mod tests {
    use super::*;
    use k8s_openapi::serde_json::{from_value, json};

    fn node(name: &str, cpu: &str, memory: &str) -> Node {
        from_value(json!({
            "metadata": {"name": name},
            "status": {
                "allocatable": {"cpu": cpu, "memory": memory},
                "capacity": {"cpu": "8", "memory": "8Gi"},
            },
        }))
        .unwrap()
    }

    fn metrics(name: &str) -> NodeMetrics {
        from_value(json!({
            "metadata": {"name": name},
            "timestamp": "2026-01-01T00:00:00Z",
            "window": "30s",
            "usage": {"cpu": "500m", "memory": "256Mi"},
        }))
        .unwrap()
    }

    #[test]
    fn node_allocations_include_active_pods_and_peak_init_resources() {
        let one_cpu = json!({"name": "app", "resources": {"requests": {"cpu": "1"}}});
        let pods = from_value(json!([
            // App CPU plus the sidecar totals 350m. Memory peaks during init:
            // 512Mi for init plus the already-running 64Mi sidecar.
            {
                "spec": {
                    "nodeName": "n1",
                    "containers": [
                        {"name": "app", "resources": {
                            "requests": {"cpu": "100m", "memory": "128Mi"},
                            "limits": {"cpu": "1", "memory": "256Mi"},
                        }},
                        {"name": "worker", "resources": {"requests": {"cpu": "200m"}}},
                    ],
                    "initContainers": [
                        {
                            "name": "sidecar",
                            "restartPolicy": "Always",
                            "resources": {"requests": {"cpu": "50m", "memory": "64Mi"}},
                        },
                        {"name": "init", "resources": {"requests": {"memory": "512Mi"}}},
                    ],
                },
                "status": {"phase": "Running"},
            },
            {"spec": {"nodeName": "n1", "containers": [one_cpu]}, "status": {"phase": "Running"}},
            {"spec": {"nodeName": "n2", "containers": [one_cpu]}, "status": {"phase": "Pending"}},
            {"spec": {"nodeName": "n1", "containers": [one_cpu]}, "status": {"phase": "Succeeded"}},
            {"spec": {"nodeName": "n1", "containers": [one_cpu]}, "status": {"phase": "Failed"}},
            {"spec": {"containers": [one_cpu]}, "status": {"phase": "Pending"}},
        ]))
        .unwrap();
        let stats = build_node_stats(
            vec![node("n1", "2", "1Gi"), node("n2", "4", "2Gi")],
            vec![metrics("n1"), metrics("n2")],
            Some(pods),
        );

        assert_eq!(
            stats["n1"].allocation,
            Some(NodeAllocation {
                cpu: ResourceAllocation {
                    requests: 67.5,
                    limits: 50.0
                },
                mem: ResourceAllocation {
                    requests: 56.25,
                    limits: 25.0
                },
            })
        );
        assert_eq!(
            stats["n2"].allocation,
            Some(NodeAllocation {
                cpu: ResourceAllocation {
                    requests: 25.0,
                    limits: 0.0
                },
                mem: ResourceAllocation::default(),
            })
        );
        assert_eq!((stats["n1"].cpu_pct, stats["n1"].mem_pct), (25.0, 25.0));
    }

    #[test]
    fn empty_pod_list_shows_zero_allocation_but_failed_fetch_keeps_usage() {
        for (pods, expected) in [
            (Some(vec![]), Some(NodeAllocation::default())),
            (None, None),
        ] {
            let stats = build_node_stats(vec![node("n1", "2", "1Gi")], vec![metrics("n1")], pods);
            assert_eq!(stats["n1"].allocation, expected);
            assert_eq!((stats["n1"].cpu_pct, stats["n1"].mem_pct), (25.0, 25.0));
        }
    }

    #[test]
    fn allocations_allow_overcommit_and_handle_zero_capacity() {
        let pods = from_value(json!([
            {"spec": {"nodeName": "n1", "containers": [{"name": "app", "resources": {
                "requests": {"cpu": "1500m", "memory": "1536Mi"},
                "limits": {"cpu": "2", "memory": "2Gi"},
            }}]}}
        ]))
        .unwrap();
        let stats = build_node_stats(
            vec![node("n1", "1", "1Gi"), node("n2", "0", "0")],
            vec![metrics("n1"), metrics("n2")],
            Some(pods),
        );
        assert_eq!(
            stats["n1"].allocation,
            Some(NodeAllocation {
                cpu: ResourceAllocation {
                    requests: 150.0,
                    limits: 200.0
                },
                mem: ResourceAllocation {
                    requests: 150.0,
                    limits: 200.0
                },
            })
        );
        assert_eq!(stats["n2"].allocation, Some(NodeAllocation::default()));
        assert_eq!((stats["n2"].cpu_pct, stats["n2"].mem_pct), (0.0, 0.0));
    }
}
