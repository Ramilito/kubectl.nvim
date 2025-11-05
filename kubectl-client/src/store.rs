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

async fn cleanup_kind_except(kind: &str, keep_key: &str) {
    let prefix = format!("{kind}@");

    {
        let mut handles = get_handle_map().write().await;
        handles.retain(|k, h| {
            let keep = !k.starts_with(&prefix) || k == keep_key;
            if !keep {
                h.abort();
            }
            keep
        });
    }

    {
        let mut stores = get_store_map().write().await;
        stores.retain(|k, _| !k.starts_with(&prefix) || k == keep_key);
    }
}

async fn spawn_reflector_with_ar(
    client: Client,
    gvk: GroupVersionKind,
    ar: kube::api::ApiResource,
    namespace: Option<String>,
    requested_key: String,
) -> Result<(), Box<dyn std::error::Error>> {
    let api: kube::Api<kube::api::DynamicObject> = match namespace.as_deref() {
        Some(ns) => kube::Api::namespaced_with(client.clone(), ns, &ar),
        None => kube::Api::all_with(client.clone(), &ar),
    };

    let config = watcher::Config::default().page_size(10500).timeout(20);
    let writer: Writer<kube::api::DynamicObject> = Writer::new(ar.clone());
    let reader: Store<kube::api::DynamicObject> = writer.as_reader();

    let ar_api_version = ar.api_version.clone();
    let ar_kind = ar.kind.clone();
    let kind_for_emit = gvk.kind.clone();

    let stream = watcher(api, config)
        .modify(move |resource| {
            // If not available in your kube version, use: resource.metadata.managed_fields = None;
            resource.managed_fields_mut().clear();
            // If this indexing doesn't compile on your version, use: resource.data.insert("api_version".into(), json!(...));
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
                        payload["event"] = "MODIFIED".into();
                        payload["metadata"] =
                            serde_json::to_value(&obj.metadata).unwrap_or(serde_json::Value::Null);
                        if let Ok(payload) = serde_json::to_string(&payload) {
                            let _ = notify_named(kind_for_emit.clone(), payload);
                        }
                    }
                    Event::Delete(obj) => {
                        payload["event"] = "DELETED".into();
                        payload["metadata"] =
                            serde_json::to_value(&obj.metadata).unwrap_or(serde_json::Value::Null);
                        if let Ok(payload) = serde_json::to_string(&payload) {
                            let _ = notify_named(kind_for_emit.clone(), payload);
                        }
                    }
                    _ => {}
                }
                // If you don't want a second emit, remove this:
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

#[tracing::instrument(skip(client))]
pub async fn init_reflector_for_kind(
    client: Client,
    gvk: GroupVersionKind,
    namespace: Option<String>,
) -> Result<(), Box<dyn std::error::Error>> {
    use kube::discovery::{pinned_kind, Scope};

    let kind = gvk.kind.clone();
    let cluster_key = format!("{kind}@*");

    {
        let map = get_store_map().read().await;
        if map.contains_key(&cluster_key) {
            return Ok(());
        }
        if let Some(ns) = namespace.as_ref() {
            let requested_key = format!("{kind}@{ns}");
            if map.contains_key(&requested_key) {
                return Ok(());
            }
        }
    }
    let (ar, caps) = pinned_kind(&client, &gvk).await?;

    if namespace.is_none() {
        cleanup_kind_except(&kind, &cluster_key).await;
        return spawn_reflector_with_ar(client, gvk, ar, None, cluster_key).await;
    }

    match caps.scope {
        Scope::Cluster => {
            cleanup_kind_except(&kind, &cluster_key).await;
            spawn_reflector_with_ar(client, gvk, ar, None, cluster_key).await
        }
        Scope::Namespaced => {
            let requested_key = format!("{kind}@{}", namespace.as_deref().unwrap());
            spawn_reflector_with_ar(client, gvk, ar, namespace, requested_key).await
        }
    }
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
