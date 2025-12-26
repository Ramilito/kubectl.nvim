use chrono::DateTime;
use chrono::Duration;
use chrono::Utc;
use k8s_openapi::api::core::v1::Event;
use kube::api::ListParams;
use kube::Api;
use kube::Client;
use mlua::Error;
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
    pub crit_events: u32,
}
pub async fn get_statusline(client: Client) -> Result<Statusline, Error> {
    let snapshot: Vec<NodeStat> = {
        node_stats()
            .lock()
            .map(|guard| guard.values().cloned().collect())
            .unwrap_or_default()
    };

    if snapshot.is_empty() {
        return Ok(Statusline::default());
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

    let events_api: Api<Event> = Api::all(client);
    let lp = ListParams::default().fields("type=Warning");

    let cutoff: DateTime<Utc> = Utc::now() - Duration::hours(1);

    let mut crit_events = 0_u32;
    for e in events_api
        .list(&lp)
        .await
        .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?
    {
        let ts = e
            .event_time
            .as_ref()
            .map(|t| t.0)
            .or_else(|| e.last_timestamp.as_ref().map(|t| t.0));

        if let Some(ts) = ts {
            if ts > cutoff {
                crit_events += 1;
            }
        }
    }

    Ok(Statusline {
        ready,
        not_ready,
        cpu_pct: (cpu_sum / n) as u16,
        mem_pct: (mem_sum / n) as u16,
        crit_events,
    })
}
