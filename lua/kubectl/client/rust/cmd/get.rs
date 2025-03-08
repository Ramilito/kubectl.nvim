use k8s_openapi::serde_json;
use kube::{
    api::{Api, DynamicObject, ResourceExt},
    core::GroupVersionKind,
    discovery::{Discovery, Scope},
    Client,
};
use mlua::prelude::*;
use tokio::runtime::Runtime;

use crate::{CLIENT_INSTANCE, RUNTIME};

use super::utils::resolve_api_resource;

#[derive(Clone, PartialEq, Eq, Debug)]
pub enum OutputMode {
    Pretty,
    Yaml,
}

impl OutputMode {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "yaml" => OutputMode::Yaml,
            _ => OutputMode::Pretty, // Default fallback
        }
    }
}

// Implement Default trait to allow `unwrap_or_default()`
impl Default for OutputMode {
    fn default() -> Self {
        Self::Pretty
    }
}

pub fn get_resource(
    rt: &Runtime,
    client: &Client,
    resource: String,
    group: Option<String>,
    version: Option<String>,
    name: Option<String>,
    namespace: Option<String>,
    output: OutputMode,
) -> LuaResult<String> {
    let fut = async move {
        let discovery = Discovery::new(client.clone())
            .run()
            .await
            .map_err(|e| mlua::Error::external(e))?;

        let (ar, caps) = if let (Some(g), Some(v)) = (group, version) {
            let gvk = GroupVersionKind {
                group: g,
                version: v,
                kind: resource.to_string(),
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
            if let Some((ar, caps)) = resolve_api_resource(&discovery, &resource) {
                (ar, caps)
            } else {
                return Err(mlua::Error::external(format!(
                    "Resource not found in cluster: {}",
                    resource
                )));
            }
        };

        let api = if caps.scope == Scope::Cluster {
            Api::<DynamicObject>::all_with(client.clone(), &ar)
        } else if let Some(ns) = &namespace {
            Api::<DynamicObject>::namespaced_with(client.clone(), ns, &ar)
        } else {
            Api::<DynamicObject>::default_namespaced_with(client.clone(), &ar)
        };

        if let Some(ref n) = name {
            let mut obj = api.get(n).await.map_err(|e| mlua::Error::external(e))?;
            obj.managed_fields_mut().clear();

            match output {
                OutputMode::Yaml => {
                    serde_yaml::to_string(&obj).map_err(|e| mlua::Error::external(e))
                }
                OutputMode::Pretty => {
                    serde_json::to_string(&obj).map_err(|e| mlua::Error::external(e))
                }
            }
        } else {
            serde_json::to_string("").map_err(|e| mlua::Error::external(e))
        }
    };

    rt.block_on(fut)
}

pub async fn get_async(
    _lua: Lua,
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

    let rt_guard = RUNTIME.lock().unwrap();
    let client_guard = CLIENT_INSTANCE.lock().unwrap();
    let rt = rt_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Runtime not initialized".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".into()))?;

    let output_mode = output
        .as_deref()
        .map(OutputMode::from_str)
        .unwrap_or_default();

    let result = get_resource(
        rt,
        client,
        kind,
        group,
        version,
        Some(name),
        namespace,
        output_mode,
    );
    Ok(result?)
}
