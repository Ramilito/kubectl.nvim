use k8s_openapi::api::core::v1::Node;
use kube::api::Api;
use mlua::{Error as LuaError, Lua, Result as LuaResult};
use tokio::runtime::Runtime;

use crate::{CLIENT_INSTANCE, RUNTIME};

pub fn uncordon(_lua: &Lua, args: String) -> LuaResult<String> {
    let name = args;
    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));

    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("Client not initialized".into()))?
        .clone();

    let fut = async move {
        let node: Api<Node> = Api::all(client.clone());
        let result = node.uncordon(&name).await;

        match result {
            Ok(..) => Ok(format!("Successfully uncordoned node '{}'", name)),
            Err(err) => Ok(format!("Failed to uncordon '{}': {:?}", name, err).to_string()),
        }
    };

    rt.block_on(fut)
}

pub fn cordon(_lua: &Lua, args: String) -> LuaResult<String> {
    let name = args;
    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));

    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("Client not initialized".into()))?
        .clone();

    let fut = async move {
        let node: Api<Node> = Api::all(client.clone());
        let result = node.cordon(&name).await;

        match result {
            Ok(..) => Ok(format!("Successfully cordoned node '{}'", name)),
            Err(err) => Ok(format!("Failed to cordone '{}': {:?}", name, err).to_string()),
        }
    };

    rt.block_on(fut)
}
