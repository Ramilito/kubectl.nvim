mod formatters;

use crate::store;
use crate::structs::GetSingleArgs;
use crate::with_client;
use formatters::format_resource;
use k8s_openapi::serde_json;
use kube::api::{Api, DynamicObject};
use kube::discovery::ApiResource;
use mlua::prelude::*;

/// Get hover content for a resource as markdown
#[tracing::instrument]
pub async fn get_hover_async(_lua: Lua, json: String) -> LuaResult<String> {
    let args: GetSingleArgs =
        serde_json::from_str(&json).map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;

    let kind = args.gvk.k.clone();

    with_client(move |client| async move {
        // Try cache first
        if let Some(obj) = store::get_single(&args.gvk.k, args.namespace.clone(), &args.name).await?
        {
            return Ok(format_resource(&kind, &obj));
        }

        // Fall back to API call
        let gvk = kube::api::GroupVersionKind {
            group: args.gvk.g.clone(),
            version: args.gvk.v.clone(),
            kind: args.gvk.k.clone(),
        };
        let ar = ApiResource::from_gvk(&gvk);

        let obj: DynamicObject = if let Some(ns) = &args.namespace {
            let api: Api<DynamicObject> = Api::namespaced_with(client.clone(), ns, &ar);
            api.get(&args.name).await.map_err(LuaError::external)?
        } else {
            let api: Api<DynamicObject> = Api::all_with(client.clone(), &ar);
            api.get(&args.name).await.map_err(LuaError::external)?
        };

        Ok(format_resource(&kind, &obj))
    })
}
