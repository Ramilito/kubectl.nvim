use k8s_openapi::serde_json;
use kube::api::{Api, DynamicObject, GroupVersionKind, ResourceExt};
use kube::discovery;
use mlua::prelude::*;
use mlua::Result as LuaResult;

use crate::structs::CmdEditArgs;
use crate::with_client;

#[tracing::instrument]
pub async fn edit_async(_lua: Lua, json: String) -> LuaResult<String> {
    let args: CmdEditArgs =
        serde_json::from_str(&json).map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;

    with_client(move |client| async move {
        let yaml_raw = std::fs::read_to_string(&args.path)
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
        let yaml_val: serde_yaml::Value = serde_yaml::from_str(&yaml_raw)
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;

        let obj: DynamicObject = serde_yaml::from_value(yaml_val)
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;

        let namespace = obj.metadata.namespace.as_deref();
        let gvk = obj
            .types
            .as_ref()
            .ok_or_else(|| mlua::Error::RuntimeError("Missing apiVersion/kind".into()))
            .and_then(|t| {
                GroupVersionKind::try_from(t).map_err(|e| mlua::Error::RuntimeError(e.to_string()))
            })?;

        let name = obj.name_any();

        let (ar, _caps) = discovery::pinned_kind(&client, &gvk)
            .await
            .map_err(|e| LuaError::RuntimeError(format!("Failed to discover resource: {e}")))?;

        let api: Api<DynamicObject> = if let Some(ns) = namespace {
            Api::namespaced_with(client.clone(), ns, &ar)
        } else {
            Api::all_with(client.clone(), &ar)
        };

        let mut live = api
            .get(&name)
            .await
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;

        live.managed_fields_mut().clear();

        let live_yaml =
            serde_yaml::to_string(&live).map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
        let edited_yaml =
            serde_yaml::to_string(&obj).map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;

        if live_yaml == edited_yaml {
            Ok(format!(
                "no changes detected for {:?}/{:?}",
                ar.plural, name
            ))
        } else {
            api.replace(&name, &Default::default(), &obj)
                .await
                .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
            Ok(format!("{}/{} edited", ar.plural, name))
        }
    })
}
