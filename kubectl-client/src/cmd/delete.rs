use k8s_openapi::serde_json;
use kube::{
    core::GroupVersionKind,
    discovery,
    runtime::{conditions::is_deleted, wait::await_condition},
    ResourceExt,
};
use mlua::{Either, Error as LuaError, Lua, Result as LuaResult};

use super::utils::dynamic_api;
use crate::{structs::CmdDeleteArgs, with_client};

pub async fn delete_async(_lua: Lua, json: String) -> LuaResult<String> {
    let args: CmdDeleteArgs = serde_json::from_str(&json).unwrap();

    with_client(move |client| async move {
        let gvk = GroupVersionKind::gvk(&args.gvk.g, &args.gvk.v, &args.gvk.k);
        let (ar, caps) = discovery::pinned_kind(&client, &gvk)
            .await
            .map_err(|e| LuaError::RuntimeError(format!("Failed to discover resource: {e}")))?;

        let api = dynamic_api(ar, caps, client.clone(), args.namespace.as_deref(), false);
        let deletion = api
            .delete(&args.name, &Default::default())
            .await
            .map_err(|e| LuaError::RuntimeError(format!("Delete failed: {e}")))?;

        if let Either::Left(pdel) = deletion {
            await_condition(api.clone(), &args.name, is_deleted(&pdel.uid().unwrap()))
                .await
                .map_err(|e| {
                    LuaError::RuntimeError(format!("Timed out waiting for deletion: {e}"))
                })?;
        }

        Ok("".to_string())
    })
}
