use crate::store::watcher::watcher;
use std::collections::HashMap;
use std::sync::OnceLock;

use futures::StreamExt;
use k8s_openapi::serde_json::{self, json};
use kube::{
    api::{Api, ApiResource, DynamicObject, GroupVersionKind, ResourceExt, TypeMeta},
    discovery::{self, Scope},
    runtime::{
        reflector::{store::Writer, Store},
        watcher::{self, Event},
        WatchStreamExt,
    },
    Client,
};
use rayon::prelude::*;
use tokio::{sync::RwLock, task::JoinHandle};
use tracing::{span, Level};

use crate::event_queue::notify_named;

type AnyError = Box<dyn std::error::Error + Send + Sync + 'static>;

/// Key for a watcher: (kind, namespace). Namespace None means "all namespaces".
#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct WatchKey {
    kind: String,
    namespace: Option<String>,
}

impl WatchKey {
    fn all(kind: &str) -> Self {
        Self {
            kind: kind.to_string(),
            namespace: None,
        }
    }

    fn new(kind: &str, namespace: &Option<String>) -> Self {
        Self {
            kind: kind.to_string(),
            namespace: namespace.clone(),
        }
    }
}

/// Internal watcher state stored in the registry.
#[derive(Debug)]
struct WatcherState {
    store: Store<DynamicObject>,
    task: JoinHandle<()>,
}

/// Which watcher is currently "active" for a given `kind`.
#[derive(Clone, Debug)]
struct ActiveKindSelection {
    watcher_key: WatchKey,
}

/// Central registry holding all dynamic watchers and caches.
pub struct DynamicWatchRegistry {
    /// All live watchers keyed by (kind, namespace).
    watchers: RwLock<HashMap<WatchKey, WatcherState>>,
    /// "Active" watcher per kind exposed to consumers.
    active_by_kind: RwLock<HashMap<String, ActiveKindSelection>>,
    /// Discovery cache: GroupVersionKind -> (ApiResource, Scope).
    ar_cache: RwLock<HashMap<GroupVersionKind, (ApiResource, Scope)>>,
}

impl DynamicWatchRegistry {
    fn new() -> Self {
        Self {
            watchers: RwLock::new(HashMap::new()),
            active_by_kind: RwLock::new(HashMap::new()),
            ar_cache: RwLock::new(HashMap::new()),
        }
    }

    /// Global singleton registry.
    fn global() -> &'static DynamicWatchRegistry {
        static REGISTRY: OnceLock<DynamicWatchRegistry> = OnceLock::new();
        REGISTRY.get_or_init(DynamicWatchRegistry::new)
    }

    /// Resolve ApiResource and Scope for a GVK, with caching.
    async fn resolve_ar_and_scope(
        &self,
        client: Client,
        gvk: &GroupVersionKind,
    ) -> Result<(ApiResource, Scope), AnyError> {
        // Fast path: in-memory cache.
        {
            let cache = self.ar_cache.read().await;
            if let Some((ar, scope)) = cache.get(gvk) {
                return Ok((ar.clone(), scope.clone()));
            }
        }

        // Slow path: discovery against the apiserver.
        let (ar, caps) = discovery::pinned_kind(&client, gvk).await?;
        let scope = caps.scope.clone();

        {
            let mut cache = self.ar_cache.write().await;
            cache.insert(gvk.clone(), (ar.clone(), scope.clone()));
        }

        Ok((ar, scope))
    }

    /// Compute the effective namespace based on scope and requested namespace.
    fn effective_namespace(scope: &Scope, requested_ns: &Option<String>) -> Option<String> {
        match scope {
            Scope::Cluster => None,
            Scope::Namespaced => requested_ns.clone(),
        }
    }

    /// Try to reuse an existing watcher.
    ///
    /// Returns: (store, watcher_key) if one is found.
    async fn maybe_reuse_existing_watcher(
        &self,
        kind: &str,
        effective_ns: &Option<String>,
        requested_ns: &Option<String>,
    ) -> Option<(Store<DynamicObject>, WatchKey)> {
        let watchers = self.watchers.read().await;

        // 1a. Prefer an ALL-namespaces watcher for this kind.
        if let Some(state) = watchers.get(&WatchKey::all(kind)) {
            tracing::info!(
                kind = %kind,
                current = "<all>",
                requested = %requested_ns.as_deref().unwrap_or("<all>"),
                "reusing existing all-namespaces watcher"
            );

            return Some((state.store.clone(), WatchKey::all(kind)));
        }

        // 1b. Exact match on (kind, effective_ns)?
        if let Some(state) = watchers.get(&WatchKey::new(kind, effective_ns)) {
            let current = effective_ns.as_deref().unwrap_or("<all>");
            tracing::info!(
                kind = %kind,
                current = %current,
                requested = %current,
                "reusing existing namespaced watcher"
            );

            return Some((state.store.clone(), WatchKey::new(kind, effective_ns)));
        }

        tracing::info!(
            kind = %kind,
            current = "<none>",
            requested = %requested_ns.as_deref().unwrap_or("<all>"),
            "no existing watcher found; creating a new one"
        );

        None
    }

    /// For namespaced kinds, if we are about to create an "all namespaces" watcher,
    /// clean up all per-namespace watchers of the same kind.
    async fn cleanup_namespaced_watchers_for_kind(&self, kind: &str) {
        let mut watchers = self.watchers.write().await;

        watchers.retain(|key, state| {
            let keep = !(key.kind == kind && key.namespace.is_some());
            if !keep {
                state.task.abort();
            }
            keep
        });
    }

    /// Register which watcher is currently "active" for a kind.
    async fn set_active_selection(&self, kind: String, watcher_key: WatchKey) {
        let selection = ActiveKindSelection { watcher_key };

        let mut active = self.active_by_kind.write().await;
        active.insert(kind, selection);
    }

    /// Fetch the active store for a given kind, if there is one.
    async fn active_store_for_kind(&self, kind: &str) -> Option<Store<DynamicObject>> {
        let selection = {
            let active = self.active_by_kind.read().await;
            active.get(kind).cloned()
        }?;

        let watchers = self.watchers.read().await;
        let state = watchers.get(&selection.watcher_key)?;

        Some(state.store.clone())
    }

    /// Reset all watchers and caches.
    async fn reset(&self) {
        {
            let mut watchers = self.watchers.write().await;
            for (_, state) in watchers.drain() {
                state.task.abort();
            }
        }

        {
            let mut active = self.active_by_kind.write().await;
            active.clear();
        }

        {
            let mut cache = self.ar_cache.write().await;
            cache.clear();
        }
    }

    async fn ensure_reflector_for_kind(
        &self,
        client: Client,
        gvk: GroupVersionKind,
        requested_namespace: Option<String>,
    ) -> Result<(), AnyError> {
        let kind_key = gvk.kind.clone();

        // 0. Resolve ApiResource + Scope via discovery (with cache).
        let (ar, scope) = self.resolve_ar_and_scope(client.clone(), &gvk).await?;
        let effective_ns = Self::effective_namespace(&scope, &requested_namespace);

        // 1. Try to re-use an existing watcher.
        if let Some((existing_store, watcher_key)) = self
            .maybe_reuse_existing_watcher(&kind_key, &effective_ns, &requested_namespace)
            .await
        {
            // Only need to expose it as "active" for this kind.
            self.set_active_selection(kind_key, watcher_key).await;

            // `existing_store` isn't directly used here, but the act of reusing ensures
            // `get` / `get_single` see a consistent active watcher.
            drop(existing_store);

            return Ok(());
        }

        // 2. If this is a namespaced kind and we’re creating an ALL-ns watcher,
        //    tear down per-namespace watchers of the same kind.
        if matches!(scope, Scope::Namespaced) && effective_ns.is_none() {
            self.cleanup_namespaced_watchers_for_kind(&kind_key).await;
        }

        // 3. Create Api using *effective* namespace.
        let api = make_dynamic_api(client.clone(), &ar, effective_ns.as_deref());

        // 4. Spawn watcher and reflector task.
        let (store, task) = spawn_watcher_task(api, ar, gvk.kind.clone());

        {
            let _loading_span = span!(
                Level::INFO,
                "init_reflector_for_kind.watcher_initial_sync",
                kind = %kind_key,
                namespace = effective_ns.as_deref().unwrap_or("<all>"),
            )
            .entered();

            let _ = store.wait_until_ready().await;
        }

        // 5. Register watcher in the global registry.
        let watcher_key = WatchKey::new(&kind_key, &effective_ns);
        {
            let mut watchers = self.watchers.write().await;
            watchers.insert(
                watcher_key.clone(),
                WatcherState {
                    store: store.clone(),
                    task,
                },
            );
        }

        // 6. Expose the active selection for this kind.
        self.set_active_selection(kind_key, watcher_key).await;

        Ok(())
    }
}

/// Build the `Api` for the given resource and effective namespace.
fn make_dynamic_api(
    client: Client,
    ar: &ApiResource,
    namespace: Option<&str>,
) -> Api<DynamicObject> {
    match namespace {
        Some(ns) => Api::namespaced_with(client, ns, ar),
        None => Api::all_with(client, ar),
    }
}

/// Spawn the watcher task, returning the store and its task handle.
///
/// This encapsulates:
/// - watcher config
/// - normalization ("modify")
/// - event payload emission
/// - store reflection
fn spawn_watcher_task(
    api: Api<DynamicObject>,
    ar: ApiResource,
    kind_for_emit: String,
) -> (Store<DynamicObject>, JoinHandle<()>) {
    let config = watcher::Config::default().page_size(10_500).timeout(20);

    let writer: Writer<DynamicObject> = Writer::new(ar.clone());
    let store: Store<DynamicObject> = writer.as_reader();

    let ar_api_version = ar.api_version.clone();
    let ar_kind = ar.kind.clone();

    let stream = watcher(api, config)
        .modify(move |resource| {
            // Strip noisy fields & normalize.
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
                let mut payload = json!({ "event": "", "metadata": "" });

                match event {
                    Event::Apply(obj) => {
                        payload["event"] = serde_json::Value::from("MODIFIED");
                        payload["metadata"] =
                            serde_json::to_value(&obj.metadata).unwrap_or(serde_json::Value::Null);

                        if let Ok(payload_str) = serde_json::to_string(&payload) {
                            let _ = notify_named(kind_for_emit.clone(), payload_str);
                        }
                    }
                    Event::Delete(obj) => {
                        payload["event"] = serde_json::Value::from("DELETED");
                        payload["metadata"] =
                            serde_json::to_value(&obj.metadata).unwrap_or(serde_json::Value::Null);

                        if let Ok(payload_str) = serde_json::to_string(&payload) {
                            let _ = notify_named(kind_for_emit.clone(), payload_str);
                        }
                    }
                    _ => {}
                }

                // Keep original behaviour of sending payload once more.
                if let Ok(payload_str) = serde_json::to_string(&payload) {
                    let _ = notify_named(kind_for_emit.clone(), payload_str);
                }
            }

            res
        })
        .reflect(writer);

    let task = tokio::spawn(async move {
        // Drive the stream so the reflector keeps updating the store.
        stream.for_each(|_| futures::future::ready(())).await;
    });

    (store, task)
}

/// Utility: does this object match the requested namespace filter?
///
/// - Cluster-scoped resources (no namespace) are **always** included.
/// - If `namespace` is Some, only objects in that namespace are included.
/// - If `namespace` is None, all namespaced objects are included.
fn namespace_matches(obj: &DynamicObject, namespace: &Option<String>) -> bool {
    if obj.namespace().is_none() {
        // Cluster-scoped; always visible.
        return true;
    }

    match namespace {
        Some(ns) => obj.namespace().as_deref() == Some(ns.as_str()),
        None => true,
    }
}

/// Abort all live watchers and clear all stores/namespace bookkeeping.
/// Intended to be called when changing kube context, or on shutdown.
#[tracing::instrument]
pub async fn reset_all_reflectors() {
    DynamicWatchRegistry::global().reset().await;
}

#[tracing::instrument(skip(client))]
pub async fn init_reflector_for_kind(
    client: Client,
    gvk: GroupVersionKind,
    namespace: Option<String>,
) -> Result<(), AnyError> {
    DynamicWatchRegistry::global()
        .ensure_reflector_for_kind(client, gvk, namespace)
        .await
}

/// Get all objects for a given `kind`, optionally filtered by namespace.
///
/// If no active store exists for this kind, returns an empty Vec.
#[tracing::instrument]
pub async fn get(kind: &str, namespace: Option<String>) -> Result<Vec<DynamicObject>, mlua::Error> {
    let registry = DynamicWatchRegistry::global();

    let store = match registry.active_store_for_kind(kind).await {
        Some(store) => store,
        None => return Ok(Vec::new()),
    };

    let result: Vec<DynamicObject> = store
        .state()
        .par_iter()
        .filter_map(|arc_obj| {
            let obj = arc_obj.as_ref();
            if namespace_matches(obj, &namespace) {
                Some(obj.clone())
            } else {
                None
            }
        })
        .collect();

    Ok(result)
}

/// Get a single object by name for a given `kind` and optional namespace.
///
/// If no active store exists for this kind, you get a Lua runtime error
/// (`"No store found for kind"`), just like before.
#[tracing::instrument]
pub async fn get_single(
    kind: &str,
    namespace: Option<String>,
    name: &str,
) -> Result<Option<DynamicObject>, mlua::Error> {
    let registry = DynamicWatchRegistry::global();

    let store = registry
        .active_store_for_kind(kind)
        .await
        .ok_or_else(|| mlua::Error::RuntimeError("No store found for kind".into()))?;

    let result = store.state().iter().find_map(|arc_obj| {
        let obj = arc_obj.as_ref();
        if obj.name_any() == name && namespace_matches(obj, &namespace) {
            Some(obj.clone())
        } else {
            None
        }
    });

    Ok(result)
}
