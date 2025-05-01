use kube::{
    core::GroupVersionKind,
    discovery,
    runtime::{conditions::is_deleted, wait::await_condition},
    ResourceExt,
};
use mlua::{Either, Error as LuaError, Lua, Result as LuaResult};
use tokio::runtime::Runtime;

use crate::{CLIENT_INSTANCE, RUNTIME};

use super::utils::dynamic_api;

pub async fn delete_async(
    _lua: Lua,
    args: (String, String, String, Option<String>, String),
) -> LuaResult<String> {
    let (kind, group, version, namespace, name) = args;

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    let client = {
        let guard = CLIENT_INSTANCE.lock().map_err(|_| {
            LuaError::RuntimeError("Failed to acquire lock on client instance".into())
        })?;
        guard
            .as_ref()
            .ok_or_else(|| LuaError::RuntimeError("Client not initialized".into()))?
            .clone()
    };

    let fut = async move {
        let gvk = GroupVersionKind::gvk(&group, &version, &kind);
        let (ar, caps) = discovery::pinned_kind(&client, &gvk)
            .await
            .map_err(|e| LuaError::RuntimeError(format!("Failed to discover resource: {e}")))?;

        let api = dynamic_api(ar, caps, client.clone(), namespace.as_deref(), false);
        let deletion = api
            .delete(&name, &Default::default())
            .await
            .map_err(|e| LuaError::RuntimeError(format!("Delete failed: {e}")))?;

        if let Either::Left(pdel) = deletion {
            await_condition(api.clone(), &name, is_deleted(&pdel.uid().unwrap()))
                .await
                .map_err(|e| {
                    LuaError::RuntimeError(format!("Timed out waiting for deletion: {e}"))
                })?;
        }

        Ok("".to_string())
    };

    rt.block_on(fut)
}
