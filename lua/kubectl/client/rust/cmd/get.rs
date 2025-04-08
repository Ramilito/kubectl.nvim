use http::Uri;
use k8s_openapi::serde_json;
use kube::{
    api::{DynamicObject, ResourceExt},
    config::Kubeconfig,
    core::GroupVersionKind,
    discovery::Discovery,
    Config,
};
use mlua::prelude::*;
use mlua::Either;
use serde_json::{json, to_string};
use tokio::runtime::Runtime;

use super::utils::{dynamic_api, resolve_api_resource};
use crate::{store::get_single, CLIENT_INSTANCE, RUNTIME};

#[derive(Clone, PartialEq, Eq, Debug)]
pub enum OutputMode {
    Pretty,
    Yaml,
    Json,
}

impl OutputMode {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "yaml" => OutputMode::Yaml,
            "json" => OutputMode::Json,
            _ => OutputMode::Pretty,
        }
    }
    pub fn format(&self, obj: DynamicObject) -> String {
        match self {
            OutputMode::Yaml => serde_yaml::to_string(&obj)
                .unwrap_or_else(|e| format!("YAML formatting error: {}", e)),
            OutputMode::Pretty => serde_json::to_string_pretty(&obj)
                .unwrap_or_else(|e| format!("Pretty formatting error: {}", e)),
            OutputMode::Json => serde_json::to_string(&obj)
                .unwrap_or_else(|e| format!("JSON formatting error: {}", e)),
        }
    }
}

impl Default for OutputMode {
    fn default() -> Self {
        Self::Pretty
    }
}

pub async fn get_resource_async(
    _lua: Lua,
    args: (
        String,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
    ),
) -> LuaResult<String> {
    let (kind, group, version, name, namespace) = args;

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".into()))?;

    let fut = async move {
        let discovery = Discovery::new(client.clone())
            .run()
            .await
            .map_err(mlua::Error::external)?;

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

        let api = dynamic_api(ar, caps, client.clone(), namespace.as_deref(), false);

        if let Some(ref n) = name {
            let mut obj = api.get(n).await.map_err(mlua::Error::external)?;
            obj.managed_fields_mut().clear();

            Ok(OutputMode::Yaml.format(obj))
        } else {
            Err(mlua::Error::external("test"))
        }
    };

    rt.block_on(fut)
}

pub async fn get_async(
    lua: Lua,
    args: (
        String,
        Option<String>,
        String,
        Option<String>,
        Option<String>,
        Option<String>,
    ),
) -> LuaResult<String> {
    let (kind, namespace, name, group, version, output) = args;
    let output_mode = output
        .as_deref()
        .map(OutputMode::from_str)
        .unwrap_or_default();

    if let Some(found) = get_single(&kind, namespace.clone(), &name) {
        return Ok(output_mode.format(found));
    }

    let result = get_resource_async(lua, (kind, group, version, Some(name), namespace));

    result.await
}

pub fn get_config(lua: &Lua, args: ()) -> LuaResult<String> {
    futures::executor::block_on(get_config_async(lua.clone(), args))
}

pub async fn get_config_async(_lua: Lua, _args: ()) -> LuaResult<String> {
    let config = Kubeconfig::read().expect("Failed to load kubeconfig");
    let json =
        serde_json::to_string(&config).unwrap_or_else(|e| format!("JSON formatting error: {}", e));

    Ok(json)
}

pub async fn get_server_raw_async(_lua: Lua, args: String) -> LuaResult<String> {
    let path = args;

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("Client not initialized".into()))?;

    let fut = async move {
        let config = Config::infer().await.map_err(|e| LuaError::external(e))?;
        let base = config.cluster_url.to_string();
        let full_url_str = format!(
            "{}/{}",
            base.trim_end_matches('/'),
            path.trim_start_matches('/')
        );
        let full_url: Uri = full_url_str.parse().map_err(|e| LuaError::external(e))?;

        let req = http::Request::get(full_url)
            .body(Vec::new())
            .map_err(|e| LuaError::external(e))?;

        let text = client
            .request_text(req)
            .await
            .map_err(|e| LuaError::external(e))?;
        Ok(text)
    };
    rt.block_on(fut)
}

pub async fn get_raw_async(_lua: Lua, args: (String, Option<String>)) -> LuaResult<String> {
    let (url, _name) = args;

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("Client not initialized".into()))?;

    let fut = async move {
        let req = http::Request::get(url)
            .body(Vec::new())
            .map_err(|e| LuaError::external(e))?;

        let res = client.request_status::<serde_json::Value>(req).await;
        match res {
            Ok(either) => match either {
                Either::Left(resp) => {
                    let json = to_string(&resp).map_err(LuaError::external)?;
                    Ok(json)
                }
                Either::Right(status) => {
                    let err_json = to_string(&json!({
                        "error": format!("HTTP error: {:?}", status),
                        "status": status.code,
                    }))
                    .map_err(LuaError::external)?;
                    Ok(err_json)
                }
            },
            Err(e) => {
                let err_json = to_string(&json!({
                    "error": e.to_string(),
                    "status": null,
                }))
                .map_err(LuaError::external)?;
                Ok(err_json)
            }
        }
    };

    rt.block_on(fut)
}
