use futures::StreamExt;
use k8s_openapi::serde_json::{self, json};
use kube::{
    api::{Api, ApiResource, DynamicObject, GroupVersionKind, ResourceExt},
    discovery::Scope,
    runtime::{
        reflector::{store::Writer, Store},
        watcher,
        watcher::Event,
        WatchStreamExt,
    },
    Client,
};
use rayon::prelude::*;

use std::collections::HashMap;
use std::sync::{Arc, OnceLock};
use tokio::sync::RwLock;

use crate::event_queue::notify_named;

type StoreMap = Arc<RwLock<HashMap<String, Store<DynamicObject>>>>;
pub static STORE_MAP: OnceLock<StoreMap> = OnceLock::new();

pub fn get_store_map() -> &'static StoreMap {
    STORE_MAP.get_or_init(|| Arc::new(RwLock::new(HashMap::new())))
}

type HandleMap = Arc<RwLock<HashMap<String, tokio::task::JoinHandle<()>>>>;
pub static HANDLE_MAP: OnceLock<HandleMap> = OnceLock::new();

fn get_handle_map() -> &'static HandleMap {
    HANDLE_MAP.get_or_init(|| Arc::new(RwLock::new(HashMap::new())))
}

fn scoped_key(kind: &str, ns: &Option<String>, scope: Scope) -> String {
    match scope {
        Scope::Cluster => format!("{kind}@*"),
        Scope::Namespaced => format!("{kind}@{}", ns.clone().unwrap_or_else(|| "*".into())),
    }
}

#[tracing::instrument(skip(client))]
pub async fn init_reflector_for_kind(
    client: Client,
    gvk: GroupVersionKind,
    namespace: Option<String>,
) -> Result<(), Box<dyn std::error::Error>> {
    let kind = gvk.kind.clone();

    let (_ar, caps) = kube::discovery::pinned_kind(&client.clone(), &gvk).await?;
    let scope = caps.scope.clone();

    let requested_key = scoped_key(&kind, &namespace, scope.clone());
    let cluster_key = scoped_key(&kind, &None, scope.clone());

    {
        let map = get_store_map().read().await;

        if map.contains_key(&cluster_key) {
            return Ok(());
        }
        if map.contains_key(&requested_key) {
            return Ok(());
        }
    }
    if matches!(scope, Scope::Cluster)
        || (matches!(scope, Scope::Namespaced) && namespace.is_none())
    {
        let mut stores = get_store_map().write().await;
        let mut handles = get_handle_map().write().await;

        let prefix = format!("{kind}@");
        let keys_to_remove: Vec<String> = stores
            .keys()
            .filter(|k| k.starts_with(&prefix) && **k != cluster_key)
            .cloned()
            .collect();

        for k in keys_to_remove {
            stores.remove(&k);
            if let Some(h) = handles.remove(&k) {
                h.abort();
            }
        }
        drop(stores);
        drop(handles);
    }

    let ar = ApiResource::from_gvk(&gvk);
    let api: Api<DynamicObject> = match (scope.clone(), namespace.as_deref()) {
        (Scope::Namespaced, Some(ns)) => Api::namespaced_with(client.clone(), ns, &ar),
        _ => Api::all_with(client.clone(), &ar),
    };

    let config = watcher::Config::default().page_size(10500).timeout(20);
    let writer: Writer<DynamicObject> = Writer::new(ar.clone());
    let reader: Store<DynamicObject> = writer.as_reader();

    let ar_api_version = ar.api_version.clone();
    let ar_kind = ar.kind.clone();
    let kind_for_emit = gvk.kind.clone();

    let stream = watcher(api, config)
        .modify(move |resource| {
            resource.managed_fields_mut().clear();
            resource.data["api_version"] = json!(ar_api_version.clone());
            if resource.types.is_none() {
                resource.types = Some(kube::api::TypeMeta {
                    kind: ar_kind.clone(),
                    api_version: ar_api_version.clone(),
                });
            }
        })
        .default_backoff()
        .map(move |res| {
            if let Ok(event) = res.as_ref() {
                let mut payload = json!({"event": "", "metadata": ""});
                match event {
                    Event::Apply(obj) => {
                        payload["event"] = serde_json::Value::from("MODIFIED");
                        payload["metadata"] =
                            serde_json::to_value(&obj.metadata).unwrap_or(serde_json::Value::Null);

                        if let Ok(payload) = serde_json::to_string(&payload) {
                            let _ = notify_named(kind_for_emit.clone(), payload);
                        }
                    }
                    Event::Delete(obj) => {
                        payload["event"] = serde_json::Value::from("DELETED");
                        payload["metadata"] =
                            serde_json::to_value(&obj.metadata).unwrap_or(serde_json::Value::Null);

                        if let Ok(payload) = serde_json::to_string(&payload) {
                            let _ = notify_named(kind_for_emit.clone(), payload);
                        }
                    }
                    _ => {}
                }
                if let Ok(payload) = serde_json::to_string(&payload) {
                    let _ = notify_named(kind_for_emit.clone(), payload);
                }
            }
            res
        })
        .reflect(writer);

    let join = tokio::spawn(async move {
        stream.for_each(|_| futures::future::ready(())).await;
    });

    let _ = reader.wait_until_ready().await;

    {
        let mut stores = get_store_map().write().await;
        stores.insert(requested_key.clone(), reader);
    }
    {
        let mut handles = get_handle_map().write().await;
        handles.insert(requested_key, join);
    }

    Ok(())
}

#[tracing::instrument]
pub async fn get(kind: &str, namespace: Option<String>) -> Result<Vec<DynamicObject>, mlua::Error> {
    let map = get_store_map().read().await;

    let key_ns = format!("{kind}@{}", namespace.clone().unwrap_or_else(|| "*".into()));
    let key_all = format!("{kind}@*");

    let store = map.get(&key_ns).or_else(|| map.get(&key_all));
    let Some(store) = store else {
        return Ok(Vec::new());
    };

    let result: Vec<DynamicObject> = store
        .state()
        .par_iter()
        .filter(|arc_obj| {
            let obj = arc_obj.as_ref();
            if obj.namespace().is_none() {
                return true;
            }
            match &namespace {
                Some(ns) => obj.namespace().as_deref() == Some(ns.as_str()),
                None => true,
            }
        })
        .map(|arc_obj| arc_obj.as_ref().clone())
        .collect();

    Ok(result)
}

#[tracing::instrument]
pub async fn get_single(
    kind: &str,
    namespace: Option<String>,
    name: &str,
) -> Result<Option<DynamicObject>, mlua::Error> {
    let map = get_store_map().read().await;

    let key_ns = format!("{kind}@{}", namespace.clone().unwrap_or_else(|| "*".into()));
    let key_all = format!("{kind}@*");

    let store = map
        .get(&key_ns)
        .or_else(|| map.get(&key_all))
        .ok_or_else(|| mlua::Error::RuntimeError("No store found for kind".into()))?;

    let result = store
        .state()
        .iter()
        .find(|arc_obj| {
            let obj = arc_obj.as_ref();
            obj.name_any() == name
                && match &namespace {
                    Some(ns) => obj.namespace().as_deref() == Some(ns),
                    None => true,
                }
        })
        .map(|arc_obj| arc_obj.as_ref().clone());

    Ok(result)
}
