use std::{
    collections::{HashMap, HashSet, VecDeque},
    sync::{Arc, Mutex, OnceLock},
    time::Duration,
};

use k8s_metrics::{v1beta1 as metricsv1, QuantityExt};
use kube::{api, Api, Client, ResourceExt};
use tokio::{task::JoinHandle, time};
use tokio_util::sync::CancellationToken;
use tracing::warn;

use super::mark_pod_stats_dirty;
use crate::{pod_stats, store};

pub const HISTORY_LEN: usize = 60; // ≈ 30 s @ 500 ms tick or 30 min @ 30 s tick

/// Key for pod stats: (namespace, name)
pub type PodKey = (String, String);

#[derive(Clone, Debug)]
pub struct PodStat {
    pub namespace: String,
    pub name: String,
    pub cpu_m: u64,
    pub mem_mi: u64,
    pub cpu_history: VecDeque<u64>,
    pub mem_history: VecDeque<u64>,
    pub containers: HashMap<String, ContainerSample>,
    /// CPU request in millicores (aggregated across containers)
    pub cpu_request_m: Option<u64>,
    /// CPU limit in millicores (aggregated across containers)
    pub cpu_limit_m: Option<u64>,
    /// Memory request in MiB (aggregated across containers)
    pub mem_request_mi: Option<u64>,
    /// Memory limit in MiB (aggregated across containers)
    pub mem_limit_mi: Option<u64>,
}

#[derive(Clone, Debug)]
pub struct ContainerSample {
    pub cpu_m: u64,
    pub mem_mi: u64,
}

/// Parsed resource requests/limits for a pod
#[derive(Clone, Debug, Default)]
pub struct PodResources {
    pub cpu_request_m: Option<u64>,
    pub cpu_limit_m: Option<u64>,
    pub mem_request_mi: Option<u64>,
    pub mem_limit_mi: Option<u64>,
}

/// Parse CPU quantity string (e.g., "100m", "0.5", "1") to millicores
fn parse_cpu_to_millicores(s: &str) -> Option<u64> {
    let s = s.trim();
    if s.ends_with('m') {
        s.trim_end_matches('m').parse::<u64>().ok()
    } else if s.ends_with('n') {
        // nanocores to millicores
        s.trim_end_matches('n')
            .parse::<u64>()
            .ok()
            .map(|n| n / 1_000_000)
    } else {
        // Cores to millicores
        s.parse::<f64>().ok().map(|c| (c * 1000.0) as u64)
    }
}

/// Parse memory quantity string (e.g., "128Mi", "1Gi", "1000000") to MiB
fn parse_memory_to_mib(s: &str) -> Option<u64> {
    let s = s.trim();
    if s.ends_with("Ki") {
        s.trim_end_matches("Ki")
            .parse::<u64>()
            .ok()
            .map(|k| k / 1024)
    } else if s.ends_with("Mi") {
        s.trim_end_matches("Mi").parse::<u64>().ok()
    } else if s.ends_with("Gi") {
        s.trim_end_matches("Gi")
            .parse::<u64>()
            .ok()
            .map(|g| g * 1024)
    } else if s.ends_with("Ti") {
        s.trim_end_matches("Ti")
            .parse::<u64>()
            .ok()
            .map(|t| t * 1024 * 1024)
    } else if s.ends_with('K') || s.ends_with('k') {
        s.trim_end_matches(['K', 'k'])
            .parse::<u64>()
            .ok()
            .map(|k| k * 1000 / (1024 * 1024))
    } else if s.ends_with('M') {
        s.trim_end_matches('M')
            .parse::<u64>()
            .ok()
            .map(|m| m * 1000 * 1000 / (1024 * 1024))
    } else if s.ends_with('G') {
        s.trim_end_matches('G')
            .parse::<u64>()
            .ok()
            .map(|g| g * 1000 * 1000 * 1000 / (1024 * 1024))
    } else {
        // Plain bytes
        s.parse::<u64>().ok().map(|b| b / (1024 * 1024))
    }
}

/// Extract aggregated resources from a pod's DynamicObject
fn extract_pod_resources(pod: &kube::api::DynamicObject) -> PodResources {
    let mut resources = PodResources::default();

    // Navigate: spec.containers[].resources.{requests,limits}.{cpu,memory}
    let spec = match pod.data.get("spec") {
        Some(s) => s,
        None => return resources,
    };

    let containers = match spec.get("containers").and_then(|c| c.as_array()) {
        Some(c) => c,
        None => return resources,
    };

    let mut total_cpu_req: u64 = 0;
    let mut total_cpu_lim: u64 = 0;
    let mut total_mem_req: u64 = 0;
    let mut total_mem_lim: u64 = 0;
    let mut has_cpu_req = false;
    let mut has_cpu_lim = false;
    let mut has_mem_req = false;
    let mut has_mem_lim = false;

    for container in containers {
        if let Some(res) = container.get("resources") {
            // Requests
            if let Some(requests) = res.get("requests") {
                if let Some(cpu) = requests.get("cpu").and_then(|v| v.as_str()) {
                    if let Some(m) = parse_cpu_to_millicores(cpu) {
                        total_cpu_req += m;
                        has_cpu_req = true;
                    }
                }
                if let Some(mem) = requests.get("memory").and_then(|v| v.as_str()) {
                    if let Some(mi) = parse_memory_to_mib(mem) {
                        total_mem_req += mi;
                        has_mem_req = true;
                    }
                }
            }
            // Limits
            if let Some(limits) = res.get("limits") {
                if let Some(cpu) = limits.get("cpu").and_then(|v| v.as_str()) {
                    if let Some(m) = parse_cpu_to_millicores(cpu) {
                        total_cpu_lim += m;
                        has_cpu_lim = true;
                    }
                }
                if let Some(mem) = limits.get("memory").and_then(|v| v.as_str()) {
                    if let Some(mi) = parse_memory_to_mib(mem) {
                        total_mem_lim += mi;
                        has_mem_lim = true;
                    }
                }
            }
        }
    }

    if has_cpu_req {
        resources.cpu_request_m = Some(total_cpu_req);
    }
    if has_cpu_lim {
        resources.cpu_limit_m = Some(total_cpu_lim);
    }
    if has_mem_req {
        resources.mem_request_mi = Some(total_mem_req);
    }
    if has_mem_lim {
        resources.mem_limit_mi = Some(total_mem_lim);
    }

    resources
}

impl PodStat {
    #[tracing::instrument]
    pub fn new(namespace: String, name: String) -> Self {
        Self {
            namespace,
            name,
            cpu_m: 0,
            mem_mi: 0,
            cpu_history: VecDeque::with_capacity(HISTORY_LEN),
            mem_history: VecDeque::with_capacity(HISTORY_LEN),
            containers: HashMap::new(),
            cpu_request_m: None,
            cpu_limit_m: None,
            mem_request_mi: None,
            mem_limit_mi: None,
        }
    }

    /// Update resource requests/limits from pod spec
    pub fn update_resources(&mut self, resources: PodResources) {
        self.cpu_request_m = resources.cpu_request_m;
        self.cpu_limit_m = resources.cpu_limit_m;
        self.mem_request_mi = resources.mem_request_mi;
        self.mem_limit_mi = resources.mem_limit_mi;
    }

    /// Pushes a new sample to the history.
    /// History is stored oldest-first (index 0 = oldest, last = newest)
    /// for efficient slice access during rendering.
    #[tracing::instrument]
    pub fn push_sample(&mut self, cpu_m: u64, mem_mi: u64) {
        self.cpu_m = cpu_m;
        self.mem_mi = mem_mi;

        // Remove oldest (front) if at capacity
        if self.cpu_history.len() == HISTORY_LEN {
            self.cpu_history.pop_front();
        }
        // Add newest to back
        self.cpu_history.push_back(cpu_m);

        if self.mem_history.len() == HISTORY_LEN {
            self.mem_history.pop_front();
        }
        self.mem_history.push_back(mem_mi);
    }

    pub fn key(&self) -> PodKey {
        (self.namespace.clone(), self.name.clone())
    }
}

pub type SharedPodStats = Arc<Mutex<HashMap<PodKey, PodStat>>>;
const POLL_INTERVAL: Duration = Duration::from_secs(30);

struct PodCollector {
    handle: JoinHandle<()>,
    cancel: CancellationToken,
}

impl PodCollector {
    #[tracing::instrument(skip(client))]
    fn new(client: Client) -> Self {
        let stats = pod_stats().clone();
        let cancel = CancellationToken::new();
        let child = cancel.clone();

        let metrics_api: Api<metricsv1::PodMetrics> = Api::all(client);

        let handle = tokio::spawn(async move {
            let mut tick = time::interval(POLL_INTERVAL);

            loop {
                tokio::select! {
                    _ = child.cancelled() => break,
                    _ = tick.tick() => {
                        // Batch fetch: get metrics and all pod specs in parallel
                        let metrics_result = metrics_api.list(&api::ListParams::default()).await;
                        let pods_result = store::get("Pod", None).await;

                        let metrics_list = match metrics_result {
                            Ok(list) => list,
                            Err(e) => {
                                warn!(error=%e, "failed to fetch pod metrics");
                                continue;
                            }
                        };

                        // Build pod resources lookup map: (namespace, name) -> PodResources
                        let pod_resources_map: HashMap<PodKey, PodResources> = pods_result
                            .unwrap_or_default()
                            .into_iter()
                            .map(|pod| {
                                let ns = pod.namespace().unwrap_or_default();
                                let name = pod.name_any();
                                let resources = extract_pod_resources(&pod);
                                ((ns, name), resources)
                            })
                            .collect();

                        // Take a snapshot of current stats outside the lock
                        let mut current_stats = {
                            match stats.lock() {
                                Ok(guard) => guard.clone(),
                                Err(poisoned) => {
                                    warn!("poisoned pod_stats lock in collector, recovering");
                                    poisoned.into_inner().clone()
                                }
                            }
                        };

                        // Track which pods we've seen this tick (HashSet for O(1) lookup)
                        let mut seen_keys: HashSet<PodKey> = HashSet::with_capacity(metrics_list.items.len());

                        // Process all metrics outside the lock
                        for m in metrics_list {
                            let ns = m.metadata.namespace.clone().unwrap_or_default();
                            let pod = m.metadata.name.clone().unwrap_or_default();
                            let key: PodKey = (ns.clone(), pod.clone());
                            seen_keys.insert(key.clone());

                            // Aggregate container metrics
                            let mut agg_cpu = 0.0_f64;
                            let mut agg_mem = 0_u64;
                            let mut c_map: HashMap<String, ContainerSample> = HashMap::with_capacity(m.containers.len());

                            for c in m.containers {
                                let cpu_m = (c.usage.cpu.to_f64().unwrap_or(0.0) * 1000.0).round() as u64;
                                let mem_bytes = c.usage.memory.to_memory().unwrap_or(0).max(0) as u64;
                                let mem_mi = mem_bytes / (1024 * 1024);

                                agg_cpu += c.usage.cpu.to_f64().unwrap_or(0.0);
                                agg_mem += mem_bytes;

                                c_map.insert(c.name, ContainerSample { cpu_m, mem_mi });
                            }

                            let agg_cpu_m = (agg_cpu * 1000.0).round() as u64;
                            let agg_mem_mi = agg_mem / (1024 * 1024);

                            // Look up pre-fetched resources (O(1) instead of async call per pod)
                            let resources = pod_resources_map
                                .get(&key)
                                .cloned()
                                .unwrap_or_default();

                            // Upsert pod row
                            current_stats
                                .entry(key)
                                .and_modify(|p| {
                                    p.push_sample(agg_cpu_m, agg_mem_mi);
                                    p.containers = c_map.clone();
                                    p.update_resources(resources.clone());
                                })
                                .or_insert_with(|| {
                                    let mut ps = PodStat::new(ns, pod);
                                    ps.push_sample(agg_cpu_m, agg_mem_mi);
                                    ps.containers = c_map;
                                    ps.update_resources(resources);
                                    ps
                                });
                        }

                        // Remove pods that vanished (O(1) lookup with HashSet)
                        current_stats.retain(|k, _| seen_keys.contains(k));

                        // Swap atomically - minimal lock time
                        match stats.lock() {
                            Ok(mut guard) => *guard = current_stats,
                            Err(poisoned) => {
                                warn!("poisoned pod_stats lock during update, recovering");
                                *poisoned.into_inner() = current_stats;
                            }
                        }
                        // Signal that new data is available
                        mark_pod_stats_dirty();
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

impl Drop for PodCollector {
    fn drop(&mut self) {
        self.cancel.cancel();
        self.handle.abort();
    }
}

static COLLECTOR: OnceLock<Mutex<Option<PodCollector>>> = OnceLock::new();
fn collector_slot() -> &'static Mutex<Option<PodCollector>> {
    COLLECTOR.get_or_init(|| Mutex::new(None))
}

#[tracing::instrument(skip(client))]
pub fn spawn_pod_collector(client: Client) {
    let mut slot = collector_slot().lock().unwrap();
    if let Some(old) = slot.take() {
        old.shutdown();
    }
    *slot = Some(PodCollector::new(client));
}

pub fn shutdown_pod_collector() {
    let mut slot = collector_slot().lock().unwrap();
    if let Some(old) = slot.take() {
        old.shutdown();
    }
}
