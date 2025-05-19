use std::{
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

#[derive(Clone, Debug)]
pub struct PodStat {
    pub namespace: String,
    pub name: String,
    pub cpu_m: u64,
    pub mem_mi: u64,
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
                    let mut out = Vec::with_capacity(metrics_list.items.len());

                    for m in metrics_list {
                        let ns = m.metadata.namespace.clone().unwrap_or_default();
                        let name = m.metadata.name.clone().unwrap_or_default();

                        // sum usage over all containers
                        let mut used_cpu_cores = 0.0_f64;
                        let mut used_mem_bytes = 0_i64;
                        for c in m.containers {
                            used_cpu_cores += c.usage.cpu.to_f64().unwrap_or(0.0);
                            used_mem_bytes += c.usage.memory.to_memory().unwrap_or(0);
                        }

                        let cpu_m = (used_cpu_cores * 1000.0).round() as u64; // cores → m
                        let mem_mi = (used_mem_bytes.max(0) as u64) / (1024 * 1024); // bytes → MiB

                        out.push(PodStat {
                            namespace: ns,
                            name,
                            cpu_m,
                            mem_mi,
                        });
                    }

                    /* overwrite the shared vec with the fresh snapshot */
                    *stats.lock().unwrap() = out;
                }
                Err(e) => warn!(error = %e, "failed to fetch pod metrics"),
            }

            thread::sleep(Duration::from_secs(5));
        }
    });
}
