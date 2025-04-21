use k8s_openapi::serde_json;
use kube::{
    api::{DynamicObject, GroupVersionKind, ListParams, Patch, PatchParams},
    Discovery, ResourceExt,
};
use mlua::prelude::*;
use tokio::runtime::Runtime;

use crate::{CLIENT_INSTANCE, RUNTIME};

use super::utils::{dynamic_api, multidoc_deserialize, resolve_api_resource};

pub async fn delete_async(_lua: Lua, args: (String, String, Option<String>)) -> LuaResult<String> {
    let (kind, name, ns) = args;

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("Client not initialized".into()))?;
    let fut = async move {
        let discovery = Discovery::new(client.clone()).run().await;

        let (ar, caps) = if let (Some(g), Some(v)) = (group, version) {
            let gvk = GroupVersionKind {
                group: g,
                version: v,
                kind: kind.to_string(),
            };
            if let Some((ar, caps)) = discovery.resolve_gvk(&gvk) {
                (ar, caps)
            } else {
                return Err(mlua::Error::external(format!(
                    "Unable to discover resource by GVK: {:?}",
                    gvk
                )));
            }
        } else {
            if let Some((ar, caps)) = resolve_api_resource(&discovery, &kind) {
                (ar, caps)
            } else {
                return Err(mlua::Error::external(format!(
                    "Resource not found in cluster: {}",
                    kind
                )));
            }
        };

        let api = dynamic_api(ar, caps, client.clone(), ns.as_deref(), false);

        // if let Some(n) = &self.name {
        //     if let either::Either::Left(pdel) = api.delete(n, &Default::default()).await? {
        //         // await delete before returning
        //         await_condition(api, n, is_deleted(&pdel.uid().unwrap())).await?;
        //     }
        // } else {
        //     api.delete_collection(&Default::default(), &lp).await?;
        // }

        // Discovery::new(client.clone())
        //     .run()
        //     .await
        //     .map_err(|e| mlua::Error::external(e))

        Ok("called".to_string())
    };

    rt.block_on(fut)
}
