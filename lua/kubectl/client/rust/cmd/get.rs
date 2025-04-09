use http::Uri;
use k8s_openapi::{
    apiextensions_apiserver::pkg::apis::apiextensions::v1::CustomResourceDefinition,
    serde_json::{self, Value},
};
use kube::{
    api::{DynamicObject, ListParams, ResourceExt},
    config::Kubeconfig,
    core::GroupVersionKind,
    discovery::Discovery,
    Api, Config,
};
use mlua::prelude::*;
use mlua::Either;
use serde_json::{json, to_string};
use serde_json_path::JsonPath;
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

pub async fn get_fallback_resource_async(
    _lua: Lua,
    args: (String, Option<String>),
) -> LuaResult<String> {
    let (name, namespace) = args;

    let rt = RUNTIME.get_or_init(|| Runtime::new().expect("Failed to create Tokio runtime"));
    let client_guard = CLIENT_INSTANCE
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to acquire lock on client instance".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".into()))?;

    let fut = async move {
        let crd_api: Api<CustomResourceDefinition> = Api::all(client.clone());
        let crd = crd_api
            .get(&name.to_string())
            .await
            .map_err(LuaError::external)?;

        print!("HELLO");
        let group = crd.spec.group.clone();
        let kind = crd.spec.names.kind.clone();
        // // Choose the first served version; you can adjust this selection logic as needed.
        let version = crd
            .spec
            .versions
            .iter()
            .find(|v| v.served)
            .map(|v| v.name.clone())
            .ok_or_else(|| LuaError::external("No served version found in CRD"))?;

        // 3) Use discovery to resolve the API resource for the custom resource.
        let discovery = Discovery::new(client.clone())
            .run()
            .await
            .map_err(LuaError::external)?;

        let gvk = GroupVersionKind {
            group: group.clone(),
            version: version.clone(),
            kind: kind.clone(),
        };

        let (ar, caps) = discovery
            .resolve_gvk(&gvk)
            .ok_or_else(|| LuaError::external(format!("Unable to resolve GVK: {:?}", gvk)))?;

        let api: Api<DynamicObject> = dynamic_api(
            ar.clone(),
            caps,
            client.clone(),
            namespace.as_deref(),
            false,
        );

        let cr_list = api
            .list(&ListParams::default())
            .await
            .map_err(LuaError::external)?;

        let columns = crd
            .spec
            .versions
            .iter()
            .find(|v| v.name == version)
            .and_then(|v| v.additional_printer_columns.as_ref())
            .ok_or_else(|| LuaError::external("No additionalPrinterColumns found"))?;

        let mut results = Vec::new();

        for mut cr_item in cr_list.items {
            cr_item.managed_fields_mut().clear();
            // Convert the resource to JSON.
            let cr_value: Value = serde_json::to_value(&cr_item).map_err(LuaError::external)?;

            // Build a JSON object of extracted columns for this CR.
            let mut obj_map = serde_json::Map::new();
            // Optionally store the resource's name in the output as well:
            if let Some(n) = cr_item.metadata.name {
                obj_map.insert("name".into(), Value::String(n));
            }

            for col in columns {
                let path_str = fix_crd_path(&col.json_path);
                match JsonPath::parse(&path_str) {
                    Ok(path) => {
                        let matched = path.query(&cr_value).all();
                        if !matched.is_empty() {
                            obj_map.insert(col.name.to_lowercase().clone(), matched[0].clone());
                        } else {
                            obj_map.insert(col.name.clone(), Value::String("<none>".into()));
                        }
                    }
                    Err(_) => {
                        obj_map.insert(col.name.clone(), Value::String("<none>".into()));
                    }
                }
            }

            results.push(Value::Object(obj_map));
        }

        let mut headers: Vec<String> = Vec::new();
        headers.push("NAME".to_string());
        for col in columns {
            headers.push(col.name.to_uppercase());
        }

        let output = json!({
            "headers": headers,
            "rows": results
        });

        serde_json::to_string(&output).map_err(LuaError::external)
    };

    rt.block_on(fut)
}

fn fix_crd_path(raw: &str) -> String {
    if raw.starts_with('.') {
        format!("${}", raw)
    } else {
        raw.to_string()
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
