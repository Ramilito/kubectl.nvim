use k8s_openapi::api::core::v1::Node;
use kube::api::ListParams;
use kube::Api;
use serde::Deserialize;
use serde::Serialize;
use tracing::error;
use tracing::info;

use crate::node_stats;
use crate::with_client;

#[derive(Default, Serialize, Deserialize, Debug, Clone)]
pub struct Statusline {
    pub ready: u16,
    pub not_ready: u16,
}
pub fn get_statusline() -> Statusline {
    match with_client(|client| async move {
        let nodes: Api<Node> = Api::all(client);

        let mut ready = 0u16;
        let mut not_ready = 0u16;

        match nodes.list(&ListParams::default()).await {
            Ok(list) => {
                for n in list.items {
                    let is_ready = n
                        .status
                        .as_ref()
                        .and_then(|s| s.conditions.as_ref())
                        .map(|conds| {
                            conds
                                .iter()
                                .any(|c| c.type_ == "Ready" && c.status == "True")
                        })
                        .unwrap_or(false);

                    if is_ready {
                        ready += 1
                    } else {
                        not_ready += 1
                    }
                }
            }
            Err(err) => {
                error!("failed to list nodes: {}", err);
            }
        }

        for ns in node_stats().lock().unwrap().iter() {
            info!(?ns, "cached NodeStat");
        }

        Ok(Statusline { ready, not_ready })
    }) {
        Ok(s) => s,
        Err(e) => {
            error!("with_client error: {}", e);
            Statusline::default()
        }
    }
}
