use k8s_openapi::api::core::v1::Node;
use kube::api::Api;
use mlua::{Lua, Result as LuaResult};

use crate::with_client;

pub fn uncordon(_lua: &Lua, args: String) -> LuaResult<String> {
    let name = args;
    with_client(move |client| async move {
        let nodes: Api<Node> = Api::all(client.clone());
        let result = nodes.uncordon(&name).await;

        match result {
            Ok(..) => Ok(format!("Successfully uncordoned node '{}'", name)),
            Err(err) => Ok(format!("Failed to uncordon '{}': {:?}", name, err).to_string()),
        }
    })
}

pub fn cordon(_lua: &Lua, args: String) -> LuaResult<String> {
    let name = args;
    with_client(move |client| async move {
        let nodes: Api<Node> = Api::all(client.clone());
        let result = nodes.cordon(&name).await;

        match result {
            Ok(..) => Ok(format!("Successfully cordoned node '{}'", name)),
            Err(err) => Ok(format!("Failed to cordone '{}': {:?}", name, err).to_string()),
        }
    })
}
