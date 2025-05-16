use std::{
    sync::{Arc, Mutex},
    thread,
    time::Duration,
};

use k8s_metrics::v1beta1 as metricsv1;
use k8s_metrics::QuantityExt;
use kube::{api, Client};
use tokio::runtime::Runtime;
use tracing::warn;

/// One node’s metrics (still raw strings for now).
#[derive(Clone, Debug)]
pub struct NodeStat {
    pub name:   String,
    pub cpu:    String,
    pub memory: String,
}
pub type SharedStats = Arc<Mutex<Vec<NodeStat>>>;

pub fn spawn_node_collector(stats: SharedStats, client: Client) {
    thread::spawn(move || {
        let rt = Runtime::new().expect("create runtime for node collector");

        loop {
            let fetch = async {
                let lp = api::ListParams::default();
                api::Api::<metricsv1::NodeMetrics>::all(client.clone())
                    .list(&lp)
                    .await
                    .map(|l| l.items)
            };

            match rt.block_on(fetch) {
                Ok(items) => {
                    let mut out = Vec::new();
                    for m in items {
                        let name   = m.metadata.name.unwrap_or_default();
                        let cpu    = m.usage.cpu.to_f64().unwrap().to_string();
                        let memory = m.usage.memory.to_memory().unwrap().to_string();
                        out.push(NodeStat { name, cpu, memory });
                    }
                    *stats.lock().unwrap() = out;
                }
                Err(e) => warn!(error=%e, "node-metrics fetch failed"),
            }

            thread::sleep(Duration::from_secs(5));
        }
    });
}
