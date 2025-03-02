use kube::{Client, api::{DynamicObject, Api, ListParams, ApiResource}};
use kube::core::GroupVersionKind;
use mlua::prelude::*;
use tokio::runtime::Runtime;

use crate::{watcher, store};

/// Remove managedFields from the object.
pub fn strip_managed_fields(obj: &mut DynamicObject) {
    obj.metadata.managed_fields = None;
}

/// Fetch the requested resource(s) from the Kubernetes API.
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

/// Main function to get a resource. It fetches the resources,
/// strips managedFields, stores them, and ensures a watcher is running.
pub fn get_resource(
    rt: &Runtime,
    client: &Client,
    resource: String,
    group: Option<String>,
    version: Option<String>,
    name: Option<String>,
    namespace: Option<String>,
) -> LuaResult<String> {
    let mut items = fetch_resource(rt, client, &resource, group.clone(), version.clone(), name, namespace.clone())
        .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
    
    for item in &mut items {
        strip_managed_fields(item);
    }
    
    store::set(&resource, items.clone());
    // Ensure the watcher is started for this resource kind.
    watcher::ensure_watcher(rt, client, resource.clone(), group, version, namespace)?;
    
    let json_str = k8s_openapi::serde_json::to_string(&items)
        .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
    Ok(json_str)
}
