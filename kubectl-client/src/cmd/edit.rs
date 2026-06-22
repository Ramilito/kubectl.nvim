use k8s_openapi::serde_json;
use kube::api::{Api, DynamicObject, GroupVersionKind, PostParams, ResourceExt};
use kube::core::Status;
use kube::discovery;
use mlua::prelude::*;
use mlua::Result as LuaResult;

use crate::structs::CmdEditArgs;
use crate::with_client;

const FIELD_MANAGER: &str = "kubectl-edit-lua";

#[tracing::instrument]
pub async fn edit_async(_lua: Lua, json: String) -> LuaResult<String> {
    let args: CmdEditArgs =
        serde_json::from_str(&json).map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;

    with_client(move |client| async move {
        let edited_raw = std::fs::read_to_string(&args.path)
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
        let edited_yaml: serde_yaml::Value = serde_yaml::from_str(&edited_raw)
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
        let mut obj: DynamicObject = serde_yaml::from_value(edited_yaml)
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
        obj.metadata.managed_fields = None;
        if let Some(data) = obj.data.as_object_mut() {
            data.remove("status");
        }

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

        let mut simulated = match api.replace(&name, &put_params(true), &obj).await {
            Ok(o) => o,
            Err(kube::Error::Api(ae)) => {
                return Err(mlua::Error::RuntimeError(fmt_api_err(&ar.plural, &name, &ae)))
            }
            Err(e) => return Err(mlua::Error::RuntimeError(e.to_string())),
        };

        let mut edited = obj.clone();
        clear_volatile(&mut live);
        clear_volatile(&mut simulated);
        clear_volatile(&mut edited);

        if live == simulated {
            if edited == live {
                return Ok(format!("no changes detected for {}/{}", ar.plural, name));
            }
            return Ok(format!(
                "no effective change for {}/{}: the server kept the current value (defaulted, immutable, or status field)",
                ar.plural, name
            ));
        }

        match api.replace(&name, &put_params(false), &obj).await {
            Ok(_) => Ok(format!("{}/{} edited", ar.kind, name)),
            Err(kube::Error::Api(ae)) => {
                Err(mlua::Error::RuntimeError(fmt_api_err(&ar.plural, &name, &ae)))
            }
            Err(e) => Err(mlua::Error::RuntimeError(e.to_string())),
        }
    })
}

fn put_params(dry_run: bool) -> PostParams {
    PostParams {
        dry_run,
        field_manager: Some(FIELD_MANAGER.into()),
    }
}

fn fmt_api_err(plural: &str, name: &str, s: &Status) -> String {
    let mut out = if s.is_conflict() {
        format!("conflict: {plural}/{name} changed on the server since you opened it — re-open (ge) and re-apply")
    } else if s.is_not_found() {
        format!("{plural}/{name} no longer exists (deleted while editing); nothing applied")
    } else if s.is_invalid() {
        format!("{plural}/{name} rejected as invalid: {}", s.message)
    } else if s.is_forbidden() {
        format!("{plural}/{name} forbidden: {}", s.message)
    } else {
        format!("failed to edit {plural}/{name}: {}", s.message)
    };
    if let Some(details) = &s.details {
        for cause in &details.causes {
            if !cause.field.is_empty() {
                out.push_str(&format!("\n  - {}: {}", cause.field, cause.message));
            }
        }
    }
    out
}

fn clear_volatile(o: &mut DynamicObject) {
    o.metadata.managed_fields = None;
    o.metadata.resource_version = None;
    o.metadata.generation = None;
    if let Some(data) = o.data.as_object_mut() {
        data.remove("status");
    }
}
