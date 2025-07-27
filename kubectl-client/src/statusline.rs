use k8s_openapi::api::core::v1::Node;
use kube::api::ListParams;
use kube::Api;
use mlua::prelude::*;
use serde::Deserialize;
use serde::Serialize;
use tracing::info;

use crate::metrics::nodes::NodeStat;
use crate::node_stats;
use crate::with_client;

#[derive(Default, Serialize, Deserialize)]
pub struct Statusline {
    pub ready: u16,
    pub not_ready: u16,
}

pub fn get_statusline() -> LuaResult<Statusline> {
    with_client(move |client| async move {
        let nodes: Api<Node> = Api::all(client.clone());
        let result = nodes.list(&ListParams::default()).await;
        let node_snapshot: Vec<NodeStat> = { node_stats().lock().unwrap().clone() };

        for (idx, ns) in node_snapshot.iter().enumerate() {
            info!("in gest statusline, {:?}", ns);
        }

        let test = Statusline {
            ready: 10,
            not_ready: 10,
        };

        match result {
            Ok(..) => Ok(test),
            Err(err) => Ok(Statusline::default()),
        }
    })
}
