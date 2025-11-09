use futures::StreamExt;
use k8s_openapi::serde_json::{self, json};
use kube::api::TypeMeta;
use kube::runtime::reflector::store::Writer;
use kube::runtime::watcher::Event;
use kube::runtime::{watcher, WatchStreamExt};
use kube::{
    api::{Api, ApiResource, DynamicObject, GroupVersionKind, ResourceExt},
    Client,
};
use rayon::prelude::*;

use kube::runtime::reflector::Store;
use std::collections::HashMap;
use std::sync::{Arc, OnceLock};
use tokio::sync::RwLock;
use tokio::task::JoinHandle;

use crate::event_queue::notify_named;

struct WatchEntry {
    store: Store<DynamicObject>,
    handle: JoinHandle<()>,
}

pub struct KindState {
    all: Option<WatchEntry>,
    by_ns: HashMap<String, WatchEntry>,
}

type StoreMap = Arc<RwLock<HashMap<String, KindState>>>;
pub static STORE_MAP: OnceLock<StoreMap> = OnceLock::new();

pub fn get_store_map() -> &'static Arc<RwLock<HashMap<String, KindState>>> {
    STORE_MAP.get_or_init(|| Arc::new(RwLock::new(HashMap::new())))
}

async fn start_watcher_for(
    client: Client,
    gvk: GroupVersionKind,
    namespace: Option<&str>,
) -> Result<WatchEntry, Box<dyn std::error::Error>> {
    let ar = ApiResource::from_gvk(&gvk);

    let api: Api<DynamicObject> = match namespace {
        Some(ns) => Api::namespaced_with(client.clone(), ns, &ar),
        None => Api::all_with(client.clone(), &ar),
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
                resource.types = Some(TypeMeta {
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
            }
            res
        })
        .reflect(writer);

    let handle = tokio::spawn(async move {
        stream.for_each(|_| futures::future::ready(())).await;
    });

    let _ = reader.wait_until_ready().await;

    Ok(WatchEntry {
        store: reader,
        handle,
    })
}

#[tracing::instrument(skip(client))]
pub async fn init_reflector_for_kind(
    client: Client,
    gvk: GroupVersionKind,
    namespace: Option<String>,
) -> Result<(), Box<dyn std::error::Error>> {
    let kind_key = gvk.kind.clone();

    let mut map = get_store_map().write().await;
    let entry = map.entry(kind_key.clone()).or_insert_with(|| KindState {
        all: None,
        by_ns: HashMap::new(),
    });

    // Fast path: if an "all-namespaces" watcher already exists, it covers any request.
    if entry.all.is_some() {
        return Ok(());
    }

    match namespace {
        None => {
            // Switching to all namespaces: dispose of any existing ns-scoped watchers.
            for (_ns, e) in entry.by_ns.drain() {
                e.handle.abort();
            }
            // Start the single all-namespaces watcher.
            let new_entry = start_watcher_for(client.clone(), gvk.clone(), None).await?;
            entry.all = Some(new_entry);
        }
        Some(ns) => {
            // If a watcher for this ns already exists, do nothing.
            if entry.by_ns.contains_key(&ns) {
                return Ok(());
            }
            // Otherwise start a new namespaced watcher (only valid if no "all" watcher exists).
            let new_entry =
                start_watcher_for(client.clone(), gvk.clone(), Some(ns.as_str())).await?;
            entry.by_ns.insert(ns, new_entry);
        }
    }

    Ok(())
}

#[tracing::instrument]
pub async fn get(kind: &str, namespace: Option<String>) -> Result<Vec<DynamicObject>, mlua::Error> {
    let map = get_store_map().read().await;
    let state = match map.get(kind) {
        Some(s) => s,
        None => return Ok(Vec::new()),
    };

    // Prefer the "all" watcher when present (fast, no extra watchers needed).
    if let Some(all) = &state.all {
        let result: Vec<DynamicObject> = all
            .store
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
        return Ok(result);
    }

    // Otherwise, we are in "by-ns" mode.
    match namespace.as_deref() {
        // Specific ns: use that store if available, else (rare) merge everything and filter.
        Some(ns) => {
            if let Some(entry) = state.by_ns.get(ns) {
                let result: Vec<DynamicObject> = entry
                    .store
                    .state()
                    .par_iter()
                    .map(|arc_obj| arc_obj.as_ref().clone())
                    .collect();
                return Ok(result);
            }
        }
        None => {
            // No ns requested and we don't have an "all" watcher: merge across all known ns watchers.
        }
    }

    // Fallback: merge across all ns stores (dedup by (ns,name,uid)).
    let mut seen = std::collections::HashSet::new();
    let mut out = Vec::new();
    for entry in state.by_ns.values() {
        for arc_obj in entry.store.state().iter() {
            let obj = arc_obj.as_ref();
            // key: (ns, name, uid)
            let key = (
                obj.namespace().unwrap_or_default(),
                obj.name_any(),
                obj.uid().unwrap_or_default(),
            );
            if seen.insert(key)
                && namespace
                    .as_deref()
                    .is_none_or(|ns| obj.namespace().as_deref() == Some(ns))
            {
                out.push(obj.clone());
            }
        }
    }
    Ok(out)
}

#[tracing::instrument]
pub async fn get_single(
    kind: &str,
    namespace: Option<String>,
    name: &str,
) -> Result<Option<DynamicObject>, mlua::Error> {
    let map = get_store_map().read().await;
    let state = match map.get(kind) {
        Some(s) => s,
        None => return Ok(None),
    };

    // Prefer the "all" watcher when present.
    if let Some(all) = &state.all {
        // 1) Bind the temporary so it outlives the iterator/closure.
        let items = all.store.state(); // Vec<Arc<DynamicObject>>
                                       // 2) Search the owned Vec (no borrowed-from-temporary).
        let found = items.into_iter().find(|arc_obj| {
            let obj = arc_obj.as_ref();
            obj.name_any() == name
                && match &namespace {
                    Some(ns) => obj.namespace().as_deref() == Some(ns.as_str()),
                    None => true,
                }
        });
        // 3) Map Arc<DynamicObject> -> DynamicObject by cloning the inner value.
        return Ok(found.map(|arc_obj| arc_obj.as_ref().clone()));
    }

    // Otherwise, look in the relevant ns store first (if specified).
    if let Some(ns) = namespace.as_deref() {
        if let Some(entry) = state.by_ns.get(ns) {
            let items = entry.store.state(); // Vec<Arc<DynamicObject>>
            let found = items.into_iter().find(|arc_obj| {
                let obj = arc_obj.as_ref();
                obj.name_any() == name && obj.namespace().as_deref() == Some(ns)
            });
            return Ok(found.map(|arc_obj| arc_obj.as_ref().clone()));
        }
    }

    // Fallback: scan all ns stores.
    for entry in state.by_ns.values() {
        if let Some(found) = entry.store.state().iter().find_map(|arc_obj| {
            let obj = arc_obj.as_ref();
            (obj.name_any() == name
                && namespace
                    .as_deref()
                    .is_none_or(|ns| obj.namespace().as_deref() == Some(ns)))
            .then(|| obj.clone())
        }) {
            return Ok(Some(found));
        }
    }

    Ok(None)
}
