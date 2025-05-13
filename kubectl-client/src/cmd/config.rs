use k8s_openapi::{apimachinery::pkg::version::Info, serde_json};
use kube::config::Kubeconfig;
use mlua::prelude::*;
use serde::Serialize;

use crate::structs::GetMinifiedConfig;
use crate::with_client;
#[derive(Serialize)]
struct VersionBlock {
    #[serde(rename = "clientVersion")]
    client_version: Info,
    #[serde(rename = "serverVersion")]
    server_version: Info,
}

#[tracing::instrument]
pub async fn get_version_async(_lua: Lua, _json: Option<String>) -> LuaResult<String> {
    with_client(move |client| async move {
        let info = client
            .clone()
            .apiserver_version()
            .await
            .map_err(LuaError::external)?;

        let client_ver: Info = Info {
            major: "1".to_string(),
            minor: "32".to_string(),
            ..Default::default()
        };

        let server_ver: k8s_openapi::apimachinery::pkg::version::Info = info;

        let payload = VersionBlock {
            client_version: client_ver,
            server_version: server_ver,
        };

        let json_str = k8s_openapi::serde_json::to_string(&payload)
            .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
        Ok(json_str)
    })
}

#[tracing::instrument]
pub async fn get_minified_config_async(_lua: Lua, json: Option<String>) -> LuaResult<String> {
    let json_str = json.as_deref().unwrap_or("{}");
    let args: GetMinifiedConfig = k8s_openapi::serde_json::from_str(json_str)
        .map_err(|e| mlua::Error::external(format!("bad json: {e}")))?;

    let full = kube::config::Kubeconfig::read().map_err(LuaError::external)?;

    let ctx_name = args
        .ctx_override
        .clone()
        .or(full.current_context.clone())
        .ok_or_else(|| {
            LuaError::external("no context specified and no current-context in kubeconfig")
        })?;

    let named_ctx = full
        .contexts
        .iter()
        .find(|c| c.name == ctx_name)
        .ok_or_else(|| LuaError::external(format!("context '{ctx_name}' not found")))?;

    let ctx = named_ctx
        .context
        .as_ref()
        .ok_or_else(|| LuaError::external(format!("context '{ctx_name}' has no data")))?;

    let cluster = full
        .clusters
        .iter()
        .find(|c| c.name == ctx.cluster)
        .ok_or_else(|| LuaError::external(format!("cluster '{}' not found", ctx.cluster)))?;

    let user = ctx
        .user
        .as_ref()
        .and_then(|u| full.auth_infos.iter().find(|ai| ai.name == *u))
        .ok_or_else(|| LuaError::external(format!("user '{:?}' not found", ctx.user)))?;

    let slim = kube::config::Kubeconfig {
        clusters: vec![cluster.clone()],
        contexts: vec![named_ctx.clone()],
        auth_infos: vec![user.clone()],
        current_context: Some(ctx_name),
        ..Default::default()
    };
    serde_json::to_string(&slim).map_err(LuaError::external)
}

#[tracing::instrument]
pub fn get_config(lua: &Lua, args: ()) -> LuaResult<String> {
    futures::executor::block_on(get_config_async(lua.clone(), args))
}

#[tracing::instrument]
pub async fn get_config_async(_lua: Lua, _args: ()) -> LuaResult<String> {
    let config = Kubeconfig::read().expect("Failed to load kubeconfig");
    let json =
        serde_json::to_string(&config).unwrap_or_else(|e| format!("JSON formatting error: {}", e));

    Ok(json)
}
