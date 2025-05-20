use std::{
    collections::HashSet,
    sync::{Arc, Mutex},
    thread,
    time::Duration,
};

use k8s_metrics::v1beta1 as metricsv1;
use k8s_metrics::QuantityExt;
use kube::{api, Api, Client};
use tokio::runtime::Runtime;
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
}

impl PodStat {
    /// create an *empty* history; call `push_sample` immediately afterwards
    pub fn new(namespace: String, name: String) -> Self {
        Self {
            namespace,
            name,
            cpu_m: 0,
            mem_mi: 0,
            cpu_history: Vec::with_capacity(HISTORY_LEN),
            mem_history: Vec::with_capacity(HISTORY_LEN),
        }
    }

    pub fn push_sample(&mut self, cpu_m: u64, mem_mi: u64) {
        self.cpu_m = cpu_m;
        self.mem_mi = mem_mi;

        if self.cpu_history.len() == HISTORY_LEN {
            self.cpu_history.pop(); // drop the oldest *tail*
        }
        self.cpu_history.insert(0, cpu_m); // ① newest point at index 0

        if self.mem_history.len() == HISTORY_LEN {
            self.mem_history.pop();
        }
        self.mem_history.insert(0, mem_mi); // ② idem for memory
    }
}

pub type SharedPodStats = Arc<Mutex<Vec<PodStat>>>;

#[tracing::instrument(skip(client))]
pub fn spawn_pod_collector(client: Client) {
    let stats = pod_stats().clone();

    thread::spawn(move || {
        let rt = Runtime::new().expect("create runtime for pod collector");
        let metrics_api: Api<metricsv1::PodMetrics> = Api::all(client);

        loop {
            let fetch = async {
                let lp = api::ListParams::default();
                metrics_api.list(&lp).await
            };

            match rt.block_on(fetch) {
                Ok(metrics_list) => {
                    let mut seen: HashSet<String> =
                        HashSet::with_capacity(metrics_list.items.len());
                    let mut guard = stats.lock().unwrap();

                    for m in metrics_list {
                        let ns = m.metadata.namespace.clone().unwrap_or_default();
                        let name = m.metadata.name.clone().unwrap_or_default();
                        let key = format!("{ns}/{name}");
                        seen.insert(key.clone());

                        /* sum usage over all containers in the pod ---------------- */
                        let mut used_cpu_cores = 0.0_f64;
                        let mut used_mem_bytes = 0_i64;
                        for c in m.containers {
                            used_cpu_cores += c.usage.cpu.to_f64().unwrap_or(0.0);
                            used_mem_bytes += c.usage.memory.to_memory().unwrap_or(0);
                        }
                        let cpu_m = (used_cpu_cores * 1000.0).round() as u64; // cores → m
                        let mem_mi = (used_mem_bytes.max(0) as u64) / (1024 * 1024); // bytes → MiB

                        /* find-or-create the PodStat and update its history -------- */
                        match guard
                            .iter_mut()
                            .find(|p| p.namespace == ns && p.name == name)
                        {
                            Some(p) => p.push_sample(cpu_m, mem_mi),
                            None => {
                                let mut p = PodStat::new(ns, name);
                                p.push_sample(cpu_m, mem_mi);
                                guard.push(p);
                            }
                        }
                    }

                    guard.retain(|p| seen.contains(&format!("{}/{}", p.namespace, p.name)));
                }

                Err(e) => warn!(error = %e, "failed to fetch pod metrics"),
            }

            thread::sleep(Duration::from_secs(45));
        }
    });
}
