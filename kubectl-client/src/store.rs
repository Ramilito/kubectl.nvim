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

use kube::discovery::{self, Scope};
use kube::runtime::reflector::Store;
use std::collections::HashMap;
use std::sync::{Arc, OnceLock};
use tokio::sync::RwLock;
use tokio::task::JoinHandle;
use tracing::{span, Level};

use crate::event_queue::notify_named;

pub type StoreMap = Arc<RwLock<HashMap<String, Store<DynamicObject>>>>;
pub static STORE_MAP: OnceLock<StoreMap> = OnceLock::new();

pub fn get_store_map() -> &'static StoreMap {
    STORE_MAP.get_or_init(|| Arc::new(RwLock::new(HashMap::new())))
}

pub type NamespaceMap = Arc<RwLock<HashMap<String, Option<String>>>>;
static STORE_NAMESPACE_MAP: OnceLock<NamespaceMap> = OnceLock::new();

pub fn get_store_namespace_map() -> &'static NamespaceMap {
    STORE_NAMESPACE_MAP.get_or_init(|| Arc::new(RwLock::new(HashMap::new())))
}

/// Key for a watcher: (kind, namespace). Namespace None means "all namespaces".
#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct WatchKey {
    kind: String,
    namespace: Option<String>,
}

impl WatchKey {
    fn new(kind: &str, namespace: &Option<String>) -> Self {
        Self {
            kind: kind.to_string(),
            namespace: namespace.clone(),
        }
    }

    fn all(kind: &str) -> Self {
        Self {
            kind: kind.to_string(),
            namespace: None,
        }
    }
}

/// Internal watcher state stored in the registry.
#[derive(Debug)]
pub struct WatcherState {
    store: Store<DynamicObject>,
    task: JoinHandle<()>,
}

/// Global registry for all live watchers, keyed by (kind, namespace).
type WatcherMap = Arc<RwLock<HashMap<WatchKey, WatcherState>>>;
static WATCHER_MAP: OnceLock<WatcherMap> = OnceLock::new();

pub fn get_watcher_map() -> &'static WatcherMap {
    WATCHER_MAP.get_or_init(|| Arc::new(RwLock::new(HashMap::new())))
}

/// Cache: GroupVersionKind -> (ApiResource, Scope) discovered via pinned_kind.
type ArCache = Arc<RwLock<HashMap<GroupVersionKind, (ApiResource, Scope)>>>;
static AR_CACHE: OnceLock<ArCache> = OnceLock::new();

fn get_ar_cache() -> &'static ArCache {
    AR_CACHE.get_or_init(|| Arc::new(RwLock::new(HashMap::new())))
}

/// Resolve ApiResource and Scope for a GVK using discovery::pinned_kind, but
/// cache the result so we only pay discovery cost once per kind.
async fn resolve_ar_and_scope(
    client: Client,
    gvk: &GroupVersionKind,
) -> Result<(ApiResource, Scope), Box<dyn std::error::Error>> {
    // Fast path: in-memory cache
    {
        let cache = get_ar_cache().read().await;
        if let Some((ar, scope)) = cache.get(gvk) {
            return Ok((ar.clone(), scope.clone()));
        }
    }

    // Slow path: pinned_kind against apiserver
    let (ar, caps) = discovery::pinned_kind(&client, gvk).await?;
    let scope = caps.scope.clone();

    {
        let mut cache = get_ar_cache().write().await;
        cache.insert(gvk.clone(), (ar.clone(), scope.clone()));
    }

    Ok((ar, scope))
}

/// Abort all live watchers and clear all stores/namespace bookkeeping.
/// Intended to be called when changing kube context, or on shutdown.
#[tracing::instrument]
pub async fn shutdown_store() {
    // Abort all watcher tasks
    {
        let mut watchers = get_watcher_map().write().await;
        for (_, state) in watchers.drain() {
            state.task.abort();
        }
    }

    // Clear visible stores
    {
        let mut stores = get_store_map().write().await;
        stores.clear();
    }

    // Clear namespace bookkeeping
    {
        let mut ns_map = get_store_namespace_map().write().await;
        ns_map.clear();
    }
}

#[tracing::instrument(skip(client))]
pub async fn init_reflector_for_kind(
    client: Client,
    gvk: GroupVersionKind,
    namespace: Option<String>,
) -> Result<(), Box<dyn std::error::Error>> {
    let kind_key = gvk.kind.clone();
    let requested_ns = namespace.clone();

    // 0. Resolve ApiResource + Scope for this GVK via pinned_kind (+ cache)
    let (ar, scope) = resolve_ar_and_scope(client.clone(), &gvk).await?;

    // For cluster-scoped kinds, ignore any requested namespace entirely.
    let effective_ns: Option<String> = match scope {
        Scope::Cluster => None,
        Scope::Namespaced => requested_ns.clone(),
    };

    // === 1. Reuse existing watchers, keyed by (kind, effective_ns) ===
    {
        let watchers = get_watcher_map().read().await;

        // 1a. If an ALL-namespaces watcher exists for this kind, it's a hit
        //     for any request (namespaced or not).
        if let Some(state) = watchers.get(&WatchKey::all(&kind_key)) {
            let _span = span!(
                Level::INFO,
                "init_reflector_for_kind.store_hit",
                kind = %kind_key,
                current = "<all>",
                requested = requested_ns.as_deref().unwrap_or("<all>"),
            )
            .entered();

            {
                let mut stores = get_store_map().write().await;
                stores.insert(kind_key.clone(), state.store.clone());
            }
            {
                let mut ns_map = get_store_namespace_map().write().await;
                ns_map.insert(kind_key.clone(), effective_ns.clone());
            }

            return Ok(());
        }

        // 1b. Exact match on (kind, effective_ns)?
        if let Some(state) = watchers.get(&WatchKey::new(&kind_key, &effective_ns)) {
            let current = effective_ns.as_deref().unwrap_or("<all>");
            let _span = span!(
                Level::INFO,
                "init_reflector_for_kind.store_hit",
                kind = %kind_key,
                current = %current,
                requested = %current,
            )
            .entered();

            {
                let mut stores = get_store_map().write().await;
                stores.insert(kind_key.clone(), state.store.clone());
            }
            {
                let mut ns_map = get_store_namespace_map().write().await;
                ns_map.insert(kind_key.clone(), effective_ns.clone());
            }

            return Ok(());
        }

        let _span = span!(
            Level::INFO,
            "init_reflector_for_kind.store_miss",
            kind = %kind_key,
            current = "<none>",
            requested = requested_ns.as_deref().unwrap_or("<all>"),
        )
        .entered();
    }

    // === 2. If this is a namespaced kind and we’re creating an ALL-ns
    //        watcher, tear down per-namespace watchers of the same kind. ===
    if matches!(scope, Scope::Namespaced) && effective_ns.is_none() {
        let mut watchers = get_watcher_map().write().await;
        let mut to_remove = Vec::new();

        for (key, state) in watchers.iter() {
            if key.kind == kind_key && key.namespace.is_some() {
                state.task.abort();
                to_remove.push(key.clone());
            }
        }

        for key in to_remove {
            watchers.remove(&key);
        }
    }

    // === 3. Create Api using *effective* namespace ===
    let api: Api<DynamicObject> = match &effective_ns {
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
            // Strip noisy fields & normalize
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
                // Keep original behaviour of sending payload once more
                if let Ok(payload) = serde_json::to_string(&payload) {
                    let _ = notify_named(kind_for_emit.clone(), payload);
                }
            }
            res
        })
        .reflect(writer);

    let task = tokio::spawn(async move {
        stream.for_each(|_| futures::future::ready(())).await;
    });

    {
        let _loading_span = span!(
            Level::INFO,
            "init_reflector_for_kind.watcher_initial_sync",
            kind = %kind_key,
            namespace = effective_ns.as_deref().unwrap_or("<all>"),
        )
        .entered();

        let _ = reader.wait_until_ready().await;
    }

    let key = WatchKey::new(&kind_key, &effective_ns);

    {
        let mut watchers = get_watcher_map().write().await;
        watchers.insert(
            key,
            WatcherState {
                store: reader.clone(),
                task,
            },
        );
    }

    {
        let mut stores = get_store_map().write().await;
        stores.insert(kind_key.clone(), reader);
    }
    {
        let mut ns_map = get_store_namespace_map().write().await;
        ns_map.insert(kind_key, effective_ns);
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
            // Cluster-scoped resources have no namespace; always include them
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
