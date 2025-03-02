use kube::{
    api::{Api, ApiResource, DynamicObject, ListParams},
    core::GroupVersionKind,
    Client,
};
use mlua::prelude::*;
use tokio::runtime::Runtime;

use crate::store;

pub fn fetch_resource(
    rt: &Runtime,
    client: &Client,
    resource: &str,
    group: Option<String>,
    version: Option<String>,
    name: Option<String>,
    namespace: Option<String>,
) -> Result<Vec<DynamicObject>, kube::Error> {
    let group_str = group.unwrap_or_default();
    let version_str = version.unwrap_or_else(|| "v1".to_string());
    let gvk = GroupVersionKind {
        group: group_str,
        version: version_str,
        kind: resource.to_string(),
    };
    let ar = ApiResource::from_gvk(&gvk);
    let api: Api<DynamicObject> = if let Some(ns) = namespace.clone() {
        Api::namespaced_with(client.clone(), &ns, &ar)
    } else {
        Api::all_with(client.clone(), &ar)
    };

    let items = rt.block_on(async {
        if let Some(n) = name {
            Ok(vec![api.get(&n).await?])
        } else {
            Ok(api.list(&ListParams::default()).await?.items)
        }
    })?;

    Ok(items)
}

/// Retrieves the resource(s), strips managedFields, and stores the result.
pub fn get_resource(
    rt: &Runtime,
    client: &Client,
    resource: String,
    group: Option<String>,
    version: Option<String>,
    name: Option<String>,
    namespace: Option<String>,
) -> LuaResult<String> {
    let mut items = fetch_resource(rt, client, &resource, group, version, name, namespace)
        .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
    for item in &mut items {
        crate::utils::strip_managed_fields(item);
    }
    store::set(&resource, items.clone());
    let json_str = k8s_openapi::serde_json::to_string(&items)
        .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
    Ok(json_str)
}
