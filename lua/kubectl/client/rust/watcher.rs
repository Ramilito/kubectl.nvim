use kube::core::GroupVersionKind;
use kube::runtime::watcher::{self, Event};
use kube::{
    api::{Api, ApiResource, DynamicObject},
    Client,
};
use mlua::prelude::*;
use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};
use tokio::runtime::Runtime;
use tokio::task::JoinHandle;

use futures::StreamExt;

use crate::resource::strip_managed_fields;
use crate::store;

static WATCHERS: LazyLock<Mutex<HashMap<String, JoinHandle<()>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Ensures that a watcher is running for the given resource kind.
/// If not already running, spawns a new watcher task that updates the store.
pub fn ensure_watcher(
    rt: &Runtime,
    client: &Client,
    resource: String,
    group: Option<String>,
    version: Option<String>,
    namespace: Option<String>,
) -> LuaResult<()> {
    let mut watchers = WATCHERS.lock().unwrap();
    if watchers.contains_key(&resource) {
        return Ok(());
    }

    let group_str = group.unwrap_or_default();
    let version_str = version.unwrap_or_else(|| "v1".to_string());
    let gvk = GroupVersionKind {
        group: group_str,
        version: version_str,
        kind: resource.clone(),
    };
    let ar = ApiResource::from_gvk(&gvk);
    let api: Api<DynamicObject> = if let Some(ns) = namespace.clone() {
        Api::namespaced_with(client.clone(), &ns, &ar)
    } else {
        Api::all_with(client.clone(), &ar)
    };

    let resource_clone = resource.clone();
    let handle: JoinHandle<()> = rt.spawn(async move {
        let config = watcher::Config::default();
        let mut stream = kube::runtime::watcher(api, config).boxed();
        while let Some(event) = stream.next().await {
            match event {
                Ok(Event::Apply(mut obj)) => {
                    strip_managed_fields(&mut obj);
                    store::update(&resource_clone, obj);
                }
                Ok(Event::Delete(mut obj)) => {
                    strip_managed_fields(&mut obj);
                    store::delete(&resource_clone, &obj);
                }
                _ => {}
            }
        }
    });
    watchers.insert(resource, handle);
    Ok(())
}
