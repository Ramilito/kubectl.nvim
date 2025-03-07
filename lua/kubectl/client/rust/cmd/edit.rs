use k8s_openapi::serde_json;
use kube::{
    api::{Api, DynamicObject, ResourceExt},
    core::GroupVersionKind,
    discovery::{Discovery, Scope},
    Client,
};
use mlua::prelude::*;
use tokio::runtime::Runtime;

use super::utils::resolve_api_resource;
pub fn edit_resource(
    rt: &Runtime,
    client: &Client,
    resource: String,
    group: Option<String>,
    version: Option<String>,
    name: Option<String>,
    namespace: Option<String>,
    content: String,
) -> LuaResult<String> {
    let fut = async move {
        let data: DynamicObject = serde_yaml::from_str(&content).expect("Not valid yaml");
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
            let _obj = api
                .replace(n, &Default::default(), &data)
                .await
                .map_err(|e| mlua::Error::external(e));

            serde_json::to_string("").map_err(|e| mlua::Error::external(e))
        } else {
            Err(mlua::Error::external("NO"))
        }
    };

    rt.block_on(fut)
}
