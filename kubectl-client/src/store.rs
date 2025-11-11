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
use std::collections::{HashMap, HashSet};
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

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub enum StoreKey {
    All { kind: String },
    Ns { kind: String, ns: String },
}

impl StoreKey {
    pub fn kind(&self) -> &str {
        match self {
            StoreKey::All { kind } => kind,
            StoreKey::Ns { kind, .. } => kind,
        }
    }
    pub fn ns(&self) -> Option<&str> {
        match self {
            StoreKey::All { .. } => None,
            StoreKey::Ns { ns, .. } => Some(ns.as_str()),
        }
    }
}

pub fn store_key(kind: &str, namespace: Option<&str>) -> StoreKey {
    match namespace {
        None => StoreKey::All {
            kind: kind.to_string(),
        },
        Some(ns) => StoreKey::Ns {
            kind: kind.to_string(),
            ns: ns.to_string(),
        },
    }
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

    if entry.all.is_some() {
        return Ok(());
    }

    match namespace {
        None => {
            for (_, e) in entry.by_ns.drain() {
                e.handle.abort();
            }
            let new_entry = start_watcher_for(client.clone(), gvk.clone(), None).await?;
            entry.all = Some(new_entry);
        }
        Some(ns) => {
            if entry.by_ns.contains_key(&ns) {
                return Ok(());
            }
            let new_entry =
                start_watcher_for(client.clone(), gvk.clone(), Some(ns.as_str())).await?;
            entry.by_ns.insert(ns, new_entry);
        }
    }

    Ok(())
}

#[tracing::instrument]
pub async fn get_by_key(key: &StoreKey) -> Result<Vec<DynamicObject>, mlua::Error> {
    let map = get_store_map().read().await;
    let state = match map.get(key.kind()) {
        Some(s) => s,
        None => return Ok(Vec::new()),
    };

    if let Some(all) = &state.all {
        let ns = key.ns().map(|s| s.to_string());
        let result: Vec<DynamicObject> = all
            .store
            .state()
            .par_iter()
            .filter(|arc_obj| {
                let obj = arc_obj.as_ref();
                if obj.namespace().is_none() {
                    return true;
                }
                match &ns {
                    Some(ns) => obj.namespace().as_deref() == Some(ns.as_str()),
                    None => true,
                }
            })
            .map(|arc_obj| arc_obj.as_ref().clone())
            .collect();
        return Ok(result);
    }

    match key {
        StoreKey::Ns { ns, .. } => {
            if let Some(entry) = state.by_ns.get(ns) {
                let result: Vec<DynamicObject> = entry
                    .store
                    .state()
                    .par_iter()
                    .map(|arc_obj| arc_obj.as_ref().clone())
                    .collect();
                return Ok(result);
            }
            return Ok(Vec::new());
        }
        StoreKey::All { .. } => {
            // Merge across all ns stores (dedup by (ns,name,uid)).
            let mut seen: HashSet<(String, String, String)> = HashSet::new();
            let mut out = Vec::new();
            for entry in state.by_ns.values() {
                for arc_obj in entry.store.state().iter() {
                    let obj = arc_obj.as_ref();
                    let key = (
                        obj.namespace().unwrap_or_default(),
                        obj.name_any(),
                        obj.uid().unwrap_or_default(),
                    );
                    if seen.insert(key) {
                        out.push(obj.clone());
                    }
                }
            }
            return Ok(out);
        }
    }
}

#[tracing::instrument]
pub async fn get_single_by_key(
    key: &StoreKey,
    name: &str,
) -> Result<Option<DynamicObject>, mlua::Error> {
    let map = get_store_map().read().await;
    let state = match map.get(key.kind()) {
        Some(s) => s,
        None => return Ok(None),
    };

    if let Some(all) = &state.all {
        let ns = key.ns().map(|s| s.to_string());
        let items = all.store.state();
        let found = items.into_iter().find(|arc_obj| {
            let obj = arc_obj.as_ref();
            obj.name_any() == name
                && match &ns {
                    Some(ns) => {
                        // cluster-scoped visible for any ns
                        obj.namespace().is_none() || obj.namespace().as_deref() == Some(ns.as_str())
                    }
                    None => true,
                }
        });
        return Ok(found.map(|arc_obj| arc_obj.as_ref().clone()));
    }

    match key {
        StoreKey::Ns { ns, .. } => {
            if let Some(entry) = state.by_ns.get(ns) {
                let items = entry.store.state();
                let found = items.into_iter().find(|arc_obj| {
                    let obj = arc_obj.as_ref();
                    obj.name_any() == name && obj.namespace().as_deref() == Some(ns.as_str())
                });
                return Ok(found.map(|arc_obj| arc_obj.as_ref().clone()));
            }
            Ok(None)
        }
        StoreKey::All { .. } => {
            // Search across all ns stores.
            for entry in state.by_ns.values() {
                if let Some(hit) = entry.store.state().iter().find_map(|arc_obj| {
                    let obj = arc_obj.as_ref();
                    (obj.name_any() == name).then(|| obj.clone())
                }) {
                    return Ok(Some(hit));
                }
            }
            Ok(None)
        }
    }
}

#[tracing::instrument]
pub async fn get(kind: &str, namespace: Option<String>) -> Result<Vec<DynamicObject>, mlua::Error> {
    let key = store_key(kind, namespace.as_deref());
    get_by_key(&key).await
}

#[tracing::instrument]
pub async fn get_single(
    kind: &str,
    namespace: Option<String>,
    name: &str,
) -> Result<Option<DynamicObject>, mlua::Error> {
    let key = store_key(kind, namespace.as_deref());
    get_single_by_key(&key, name).await
}
