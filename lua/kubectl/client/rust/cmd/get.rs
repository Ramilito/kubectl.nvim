use k8s_openapi::serde_json;
use kube::{
    api::{DynamicObject, ResourceExt},
    core::GroupVersionKind,
    discovery::Discovery,
    Client,
};
use mlua::prelude::*;
use tokio::runtime::Runtime;

use crate::{store::get_single, CLIENT_INSTANCE, RUNTIME};

use super::utils::{dynamic_api, resolve_api_resource};

#[derive(Clone, PartialEq, Eq, Debug)]
pub enum OutputMode {
    Pretty,
    Yaml,
}

impl OutputMode {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "yaml" => OutputMode::Yaml,
            _ => OutputMode::Pretty,
        }
    }
    pub fn format(&self, obj: DynamicObject) -> String {
        match self {
            OutputMode::Yaml => serde_yaml::to_string(&obj)
                .unwrap_or_else(|e| format!("YAML formatting error: {}", e)),
            OutputMode::Pretty => serde_json::to_string_pretty(&obj)
                .unwrap_or_else(|e| format!("Pretty formatting error: {}", e)),
        }
    }
}

impl Default for OutputMode {
    fn default() -> Self {
        Self::Pretty
    }
}

fn get_resource(
    rt: &Runtime,
    client: &Client,
    resource: String,
    group: Option<String>,
    version: Option<String>,
    name: Option<String>,
    namespace: Option<String>,
) -> LuaResult<DynamicObject> {
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

        let api = dynamic_api(ar, caps, client.clone(), namespace.as_deref(), false);

        if let Some(ref n) = name {
            let mut obj = api.get(n).await.map_err(|e| mlua::Error::external(e))?;
            obj.managed_fields_mut().clear();

            Ok(obj)
        } else {
            Err(mlua::Error::external("test"))
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

    let output_mode = output
        .as_deref()
        .map(OutputMode::from_str)
        .unwrap_or_default();

    if let Some(found) = get_single(&kind, namespace.clone(), &name) {
        return Ok(output_mode.format(found));
    }
    let rt_guard = RUNTIME.lock().unwrap();
    let client_guard = CLIENT_INSTANCE.lock().unwrap();
    let rt = rt_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Runtime not initialized".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".into()))?;

    let result = get_resource(rt, client, kind, group, version, Some(name), namespace);

    Ok(output_mode.format(result?))
}
