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
use tracing::{span, Level};

use crate::event_queue::notify_named;

type StoreMap = Arc<RwLock<HashMap<String, Store<DynamicObject>>>>;
pub static STORE_MAP: OnceLock<StoreMap> = OnceLock::new();

pub fn get_store_map() -> &'static Arc<RwLock<HashMap<String, Store<DynamicObject>>>> {
    STORE_MAP.get_or_init(|| Arc::new(RwLock::new(HashMap::new())))
}

type StoreNamespaceMap = Arc<RwLock<HashMap<String, Option<String>>>>;
pub static STORE_NAMESPACE_MAP: OnceLock<StoreNamespaceMap> = OnceLock::new();

pub fn get_store_namespace_map() -> &'static StoreNamespaceMap {
    STORE_NAMESPACE_MAP.get_or_init(|| Arc::new(RwLock::new(HashMap::new())))
}
type KindKey = String;
type NamespaceKey = Option<String>; // None == ALL namespaces

#[derive(Debug)]
struct WatcherEntry {
    store: Store<DynamicObject>,
    task: JoinHandle<()>,
}

static WATCHER_MAP: OnceLock<RwLock<HashMap<(KindKey, NamespaceKey), WatcherEntry>>> =
    OnceLock::new();

fn get_watcher_map() -> &'static RwLock<HashMap<(KindKey, NamespaceKey), WatcherEntry>> {
    WATCHER_MAP.get_or_init(|| RwLock::new(HashMap::new()))
}

#[tracing::instrument(skip(client))]
pub async fn init_reflector_for_kind(
    client: Client,
    gvk: GroupVersionKind,
    namespace: Option<String>,
) -> Result<(), Box<dyn std::error::Error>> {
    use tracing::{span, Level};

    let kind_key = gvk.kind.clone();
    let requested_label = namespace.as_deref().unwrap_or("<all>");

    {
        let watcher_map = get_watcher_map().read().await;

        // Prefer an ALL-namespaces watcher if one exists for this kind
        if let Some(entry) = watcher_map.get(&(kind_key.clone(), None)) {
            let _span = span!(
                Level::INFO,
                "init_reflector_for_kind.store_hit",
                kind = %kind_key,
                current = "<all>",
                requested = requested_label,
            )
            .entered();

            // Update the "active" store + namespace for this kind
            {
                let mut map = get_store_map().write().await;
                map.insert(kind_key.clone(), entry.store.clone());
            }
            {
                let mut ns_map = get_store_namespace_map().write().await;
                ns_map.insert(kind_key.clone(), None);
            }

            return Ok(());
        }

        // Otherwise, see if there's an existing watcher for exactly this namespace
        if let Some(ns) = namespace.as_ref() {
            if let Some(entry) = watcher_map.get(&(kind_key.clone(), Some(ns.clone()))) {
                let _span = span!(
                    Level::INFO,
                    "init_reflector_for_kind.store_hit",
                    kind = %kind_key,
                    current = %ns,
                    requested = %ns,
                )
                .entered();

                {
                    let mut map = get_store_map().write().await;
                    map.insert(kind_key.clone(), entry.store.clone());
                }
                {
                    let mut ns_map = get_store_namespace_map().write().await;
                    ns_map.insert(kind_key.clone(), Some(ns.clone()));
                }

                return Ok(());
            }
        }

        let _span = span!(
            Level::INFO,
            "init_reflector_for_kind.store_miss",
            kind = %kind_key,
            current = "<none>",
            requested = requested_label,
        )
        .entered();
        // fall through and actually create a watcher
    }

    // 2) Build the watcher as you did before
    let ar = ApiResource::from_gvk(&gvk);
    let api: Api<DynamicObject> = match &namespace {
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
                if let Ok(payload) = serde_json::to_string(&payload) {
                    let _ = notify_named(kind_for_emit.clone(), payload);
                }
            }
            res
        })
        .reflect(writer);

    // Keep the JoinHandle so we can abort the watcher later
    let handle = tokio::spawn(async move {
        stream.for_each(|_| futures::future::ready(())).await;
    });

    {
        let _loading_span = span!(
            Level::INFO,
            "init_reflector_for_kind.watcher_initial_sync",
            kind = %kind_key,
            namespace = requested_label,
        )
        .entered();

        let _ = reader.wait_until_ready().await;
    }

    // 3) Register this watcher in the registry
    {
        let mut watcher_map = get_watcher_map().write().await;

        if namespace.is_none() {
            // We're creating an ALL-namespaces watcher.
            // Kill any existing per-namespace (or older ALL) watchers for this kind.
            let keys_to_remove: Vec<_> = watcher_map
                .keys()
                .filter(|(k, _)| k == &kind_key)
                .cloned()
                .collect();

            for key in keys_to_remove {
                if let Some(entry) = watcher_map.remove(&key) {
                    entry.task.abort();
                }
            }
        }

        watcher_map.insert(
            (kind_key.clone(), namespace.clone()),
            WatcherEntry {
                store: reader.clone(),
                task: handle,
            },
        );
    }

    // 4) Update the "active" store + namespace for this kind (same as before)
    {
        let mut map = get_store_map().write().await;
        map.insert(kind_key.clone(), reader);
    }
    {
        let mut ns_map = get_store_namespace_map().write().await;
        ns_map.insert(kind_key, namespace);
    }

    Ok(())
}

#[tracing::instrument]
pub async fn get(kind: &str, namespace: Option<String>) -> Result<Vec<DynamicObject>, mlua::Error> {
    let map = get_store_map().read().await;
    let store = match map.get(&kind.to_string()) {
        Some(store) => store,
        None => return Ok(Vec::new()),
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

    let store = map
        .get(&kind.to_string())
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
