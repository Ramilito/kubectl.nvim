use http::Uri;
use k8s_openapi::serde_json::{self};
use kube::{
    api::{ApiResource, DynamicObject, ListParams, ResourceExt, TypeMeta},
    config::Kubeconfig,
    core::GroupVersionKind,
    discovery::{ApiCapabilities, Discovery, Scope},
    error::DiscoveryError,
    Api, Client, Config, Error,
};
use log::info;
use mlua::prelude::*;
use mlua::Either;
use serde::Serialize;
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

pub async fn get_resources_async(
    client: &Client,
    kind: String,
    group: Option<String>,
    version: Option<String>,
    namespace: Option<String>,
) -> Result<Vec<DynamicObject>, Error> {
    let discovery = Discovery::new(client.clone()).run().await?;

    let (ar, caps) = if let (Some(g), Some(v)) = (group, version) {
        let gvk = GroupVersionKind {
            group: g,
            version: v,
            kind: kind.clone(),
        };
        if let Some((ar, caps)) = discovery.resolve_gvk(&gvk) {
            (ar, caps)
        } else {
            return Err(Error::Discovery(DiscoveryError::MissingResource(format!(
                "Unable to discover resource by GVK: {:?}",
                gvk
            ))));
        }
    } else if let Some((ar, caps)) = resolve_api_resource(&discovery, &kind) {
        (ar, caps)
    } else {
        return Err(Error::Discovery(DiscoveryError::MissingResource(format!(
            "Resource not found in cluster: {kind}"
        ))));
    };
    let ar_api_version = ar.version.clone();
    let ar_kind = ar.kind.clone();
    let api = dynamic_api(ar, caps, client.clone(), namespace.as_deref(), true);
    let mut list = api.list(&ListParams::default()).await?;

    for obj in &mut list.items {
        if obj.types.is_none() {
            obj.types = Some(TypeMeta {
                kind: ar_kind.clone(),
                api_version: ar_api_version.clone(),
            });
        }
        obj.managed_fields_mut().clear();
    }

    Ok(list.items)
}

pub async fn get_resource_async(
    client: &Client,
    kind: String,
    group: Option<String>,
    version: Option<String>,
    name: String,
    namespace: Option<String>,
    output: Option<String>,
) -> LuaResult<String> {
    let output_mode = output
        .as_deref()
        .map(OutputMode::from_str)
        .unwrap_or_default();
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

    Ok(output_mode.format(obj))
}

pub async fn get_single_async(
    _lua: Lua,
    args: (String, Option<String>, String, Option<String>),
) -> LuaResult<String> {
    let (kind, namespace, name, output) = args;

    let output_mode = output
        .as_deref()
        .map(OutputMode::from_str)
        .unwrap_or_default();

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".into()))?;

    let fut = async move {
        if let Some(found) = store::get_single(&kind, namespace.clone(), &name).await? {
            return Ok(output_mode.format(found));
        }
        let result = get_resource_async(client, kind, None, None, name, namespace, output);

        result.await
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

#[derive(Serialize, Debug)]
struct FallbackResource {
    gvk: GroupVersionKind,
    plural: String,
    namespaced: bool,
    // short_names: Vec<String>,
    crd_name: String,
}

impl FallbackResource {
    fn from_ar_cap(ar: &ApiResource, cap: &ApiCapabilities) -> Self {
        let crd_name = if ar.group.is_empty() {
            ar.plural.clone()
        } else {
            format!("{}.{}", ar.plural, ar.group)
        };
        FallbackResource {
            gvk: GroupVersionKind {
                group: ar.group.clone(),
                version: ar.version.clone(),
                kind: ar.kind.clone(),
            },
            plural: ar.plural.clone(),
            namespaced: cap.scope == Scope::Namespaced,
            // short_names: ar.short_names.clone(),
            crd_name,
        }
    }
}

pub async fn get_api_resources_async(_lua: Lua, _args: ()) -> LuaResult<String> {
    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| LuaError::RuntimeError("Client not initialized".into()))?;
    let fut = async move {
        let discovery = Discovery::new(client.clone())
            .exclude(&[r#"metrics.k8s.io"#, r#"events.k8s.io"#])
            .run()
            .await
            .map_err(|e| mlua::Error::RuntimeError(format!("Discovery error: {}", e)))?;

        let mut resources = Vec::new();
        for group in discovery.groups() {
            group.resources_by_stability().iter().for_each(|(ar, cap)| {
                if ar.plural != "componentstatuses" && (cap.supports_operation("list")) {
                    resources.push(FallbackResource::from_ar_cap(ar, cap));
                }
            });
        }
        serde_json::to_string(&resources)
            .map_err(|e| mlua::Error::RuntimeError(format!("JSON serialization error: {}", e)))
    };

    rt.block_on(fut)
}
