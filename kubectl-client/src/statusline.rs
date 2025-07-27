use serde::Deserialize;
use serde::Serialize;

use crate::metrics::nodes::NodeStat;
use crate::node_stats;

#[derive(Default, Serialize, Deserialize, Debug, Clone)]
pub struct Statusline {
    pub ready: u16,
    pub not_ready: u16,
    pub cpu_pct: u16,
    pub mem_pct: u16,
}
pub fn get_statusline() -> Statusline {
    let snapshot: Vec<NodeStat> = { node_stats().lock().unwrap().clone() };

    if snapshot.is_empty() {
        return Statusline::default();
    }

    let (ready, not_ready, cpu_sum, mem_sum) = snapshot.iter().fold(
        (0u16, 0u16, 0.0f64, 0.0f64),
        |(mut rdy, mut nrd, mut cpu, mut mem), ns| {
            cpu += ns.cpu_pct;
            mem += ns.mem_pct;
            if ns.status == "Ready" {
                rdy += 1;
            } else {
                nrd += 1;
            }
            (rdy, nrd, cpu, mem)
        },
    );

    let n = snapshot.len() as f64;

    Statusline {
        ready,
        not_ready,
        cpu_pct: (cpu_sum / n) as u16,
        mem_pct: (mem_sum / n) as u16,
    }
}
