use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, Mutex, OnceLock},
    time::Duration,
};

use k8s_metrics::{v1beta1 as metricsv1, QuantityExt};
use kube::{api, Api, Client};
use tokio::{task::JoinHandle, time};
use tokio_util::sync::CancellationToken;
use tracing::warn;

use crate::pod_stats;

pub const HISTORY_LEN: usize = 60; // ≈ 30 s @ 500 ms tick or 30 min @ 30 s tick

#[derive(Clone, Debug)]
pub struct PodStat {
    pub namespace: String,
    pub name: String,                    
    pub cpu_m: u64,                     
    pub mem_mi: u64,                   
    pub cpu_history: Vec<u64>,        
    pub mem_history: Vec<u64>,       
    pub containers: HashMap<String, ContainerSample>,
}

#[derive(Clone, Debug)]
pub struct ContainerSample {
    pub cpu_m: u64,
    pub mem_mi: u64,
}

impl PodStat {
    pub fn new(namespace: String, name: String) -> Self {
        Self {
            namespace,
            name,
            cpu_m: 0,
            mem_mi: 0,
            cpu_history: Vec::with_capacity(HISTORY_LEN),
            mem_history: Vec::with_capacity(HISTORY_LEN),
            containers: HashMap::new(),
        }
    }

    pub fn push_sample(&mut self, cpu_m: u64, mem_mi: u64) {
        self.cpu_m = cpu_m;
        self.mem_mi = mem_mi;

        if self.cpu_history.len() == HISTORY_LEN {
            self.cpu_history.pop(); // drop oldest
        }
        self.cpu_history.insert(0, cpu_m); // newest first

        if self.mem_history.len() == HISTORY_LEN {
            self.mem_history.pop();
        }
        self.mem_history.insert(0, mem_mi);
    }
}

pub type SharedPodStats = Arc<Mutex<Vec<PodStat>>>;
const POLL_INTERVAL: Duration = Duration::from_secs(45);

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
                        match metrics_api.list(&api::ListParams::default()).await {
                            Ok(metrics_list) => {
                                let mut seen = HashSet::<String>::with_capacity(metrics_list.items.len());
                                let mut guard = stats.lock().unwrap();

                                for m in metrics_list {
                                    let ns  = m.metadata.namespace.clone().unwrap_or_default();
                                    let pod = m.metadata.name.clone().unwrap_or_default();
                                    let key = format!("{ns}/{pod}");
                                    seen.insert(key.clone());

                                    /* ---- aggregate ---- */
                                    let mut agg_cpu = 0.0_f64;
                                    let mut agg_mem = 0_i64;

                                    /* tmp map for this tick's container samples */
                                    let mut c_map: HashMap<String, ContainerSample> = HashMap::new();

                                    for c in m.containers {
                                        let cpu_m  = (c.usage.cpu.to_f64().unwrap_or(0.0) * 1000.0).round() as u64;
                                        let mem_mi = (c.usage.memory.to_memory().unwrap_or(0).max(0) as u64)/(1024*1024);

                                        agg_cpu += c.usage.cpu.to_f64().unwrap_or(0.0);
                                        agg_mem += c.usage.memory.to_memory().unwrap_or(0);

                                        c_map.insert(c.name, ContainerSample { cpu_m, mem_mi });
                                    }

                                    let agg_cpu_m  = (agg_cpu * 1000.0).round() as u64;
                                    let agg_mem_mi = (agg_mem.max(0) as u64) / (1024*1024);

                                    /* ---- upsert pod row ---- */
                                    match guard.iter_mut().find(|p| p.namespace == ns && p.name == pod) {
                                        Some(p) => {
                                            p.push_sample(agg_cpu_m, agg_mem_mi);
                                            p.containers = c_map;
                                        }
                                        None => {
                                            let mut ps = PodStat::new(ns.clone(), pod.clone());
                                            ps.push_sample(agg_cpu_m, agg_mem_mi);
                                            ps.containers = c_map;
                                            guard.push(ps);
                                        }
                                    }
                                }

                                /* drop pods that vanished */
                                guard.retain(|p| seen.contains(&format!("{}/{}", p.namespace, p.name)));
                            }
                            Err(e) => warn!(error=%e, "failed to fetch pod metrics"),
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

pub fn spawn_pod_collector(client: Client) {
    let mut slot = collector_slot().lock().unwrap();
    if let Some(old) = slot.take() {
        old.shutdown();
    }
    *slot = Some(PodCollector::new(client));
}

pub fn shutdown_collectors() {
    let mut slot = collector_slot().lock().unwrap();
    if let Some(old) = slot.take() {
        old.shutdown();
    }
}
