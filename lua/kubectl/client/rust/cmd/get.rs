use http::Uri;
use k8s_openapi::{
    apiextensions_apiserver::pkg::apis::apiextensions::v1::{
        CustomResourceDefinition, CustomResourceDefinitionVersion,
    },
    serde_json::{self},
};
use kube::{
    api::{DynamicObject, ResourceExt},
    config::Kubeconfig,
    core::GroupVersionKind,
    discovery::Discovery,
    Api, Config,
};
use mlua::prelude::*;
use mlua::Either;
use serde_json::{json, to_string};
use tokio::runtime::Runtime;

use super::utils::{dynamic_api, resolve_api_resource};
use crate::{store, CLIENT_INSTANCE, RUNTIME};

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
        String,
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
        } else if let Some((ar, caps)) = resolve_api_resource(&discovery, &kind) {
            (ar, caps)
        } else {
            return Err(mlua::Error::external(format!(
                "Resource not found in cluster: {}",
                kind
            )));
        };

        let api = dynamic_api(ar, caps, client.clone(), namespace.as_deref(), false);

        let mut obj = api.get(&name).await.map_err(mlua::Error::external)?;
        obj.managed_fields_mut().clear();

        Ok(OutputMode::Yaml.format(obj))
    };

    rt.block_on(fut)
}

pub async fn get_async(
    _lua: Lua,
    args: (String, Option<String>, String, Option<String>),
) -> LuaResult<String> {
    let (kind, namespace, name, output) = args;
    let output_mode = output
        .as_deref()
        .map(OutputMode::from_str)
        .unwrap_or_default();

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));

    let fut = async move {
        let obj = store::get_single(&kind, namespace, &name).await?;
        // TODO: remove the unwrap()
        Ok(output_mode.format(obj.unwrap()))
    };
    rt.block_on(fut)
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
        let config = Config::infer().await.map_err(LuaError::external)?;
        let base = config.cluster_url.to_string();
        let full_url_str = format!(
            "{}/{}",
            base.trim_end_matches('/'),
            path.trim_start_matches('/')
        );
        let full_url: Uri = full_url_str.parse().map_err(LuaError::external)?;

        let req = http::Request::get(full_url)
            .body(Vec::new())
            .map_err(LuaError::external)?;

        let text = client.request_text(req).await.map_err(LuaError::external)?;
        Ok(text)
    };
    rt.block_on(fut)
}

pub async fn get_raw_async(_lua: Lua, args: (String, Option<String>, bool)) -> LuaResult<String> {
    let (url, _name, is_fallback) = args;

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("Client not initialized".into()))?;

    let fut = async move {
        let mut req = http::Request::get(url)
            .body(Vec::new())
            .map_err(LuaError::external)?;
        if is_fallback {
            req.headers_mut().insert(
                http::header::ACCEPT,
                "application/json;as=Table;g=meta.k8s.io;v=v1"
                    .parse()
                    .unwrap(),
            );
        }

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

#[derive(serde::Serialize, Debug)]
struct FallbackResource {
    gvk: GroupVersionKind,
    plural: String,
    namespaced: bool,
    crd_name: String,
    short_names: Vec<String>,
}

pub async fn get_api_resources_async(_lua: mlua::Lua, _args: ()) -> mlua::Result<String> {
    let rt = RUNTIME
        .get_or_init(|| tokio::runtime::Runtime::new().expect("Failed to create Tokio runtime"));
    let client_guard = CLIENT_INSTANCE.lock().map_err(|_| {
        mlua::Error::RuntimeError("Failed to acquire lock on client instance".into())
    })?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".into()))?;

    let fut = async move {
        let crd_api: Api<CustomResourceDefinition> = Api::all(client.clone());

        let crds = crd_api
            .list(&Default::default())
            .await
            .map_err(|e| mlua::Error::RuntimeError(format!("Failed to list CRDs: {}", e)))?;

        let resources: Vec<FallbackResource> = crds
            .into_iter()
            .map(|crd| {
                let plural = crd.spec.names.plural;
                let namespaced = crd.spec.scope == "Namespaced";
                let short_names = crd.spec.names.short_names.unwrap_or_default();
                let preferred_version = crd
                    .spec
                    .versions
                    .iter()
                    .find(|v: &&CustomResourceDefinitionVersion| v.storage)
                    .map(|v| v.name.clone())
                    .unwrap_or_else(|| {
                        crd.spec
                            .versions
                            .first()
                            .map(|v| v.name.clone())
                            .unwrap_or_default()
                    });
                let crd_name = crd.metadata.name.unwrap_or_default();
                let gvk = GroupVersionKind {
                    group: crd.spec.group,
                    version: preferred_version,
                    kind: crd.spec.names.kind,
                };

                FallbackResource {
                    gvk,
                    plural,
                    namespaced,
                    crd_name,
                    short_names,
                }
            })
            .collect();

        serde_json::to_string(&resources)
            .map_err(|e| mlua::Error::RuntimeError(format!("JSON serialization error: {}", e)))
    };

    rt.block_on(fut)
}
