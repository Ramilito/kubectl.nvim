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
use std::sync::{Arc, OnceLock, RwLock};
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use crate::event_queue::notify_named;

pub struct ReflectorData {
    pub store: Store<DynamicObject>,
    pub handle: JoinHandle<()>,
    pub cancel: CancellationToken,
}

/// Key: (kind, namespace) where None means all namespaces
type ReflectorKey = (String, Option<String>);
type StoreMap = Arc<RwLock<HashMap<ReflectorKey, ReflectorData>>>;

static STORE_MAP: OnceLock<StoreMap> = OnceLock::new();

fn store_map() -> &'static StoreMap {
    STORE_MAP.get_or_init(|| Arc::new(RwLock::new(HashMap::new())))
}

fn key(kind: &str, namespace: Option<&str>) -> ReflectorKey {
    (kind.to_string(), namespace.map(String::from))
}

#[tracing::instrument]
pub async fn shutdown_all_reflectors() {
    let Ok(mut map) = store_map().write() else {
        tracing::warn!("STORE_MAP lock poisoned during shutdown");
        return;
    };
    for ((kind, ns), data) in map.drain() {
        tracing::debug!(kind, ?ns, "Shutting down reflector");
        data.cancel.cancel();
        data.handle.abort();
    }
}

fn shutdown_namespaced_reflectors(map: &mut HashMap<ReflectorKey, ReflectorData>, kind: &str) {
    let to_remove: Vec<_> = map
        .keys()
        .filter(|(k, ns)| k == kind && ns.is_some())
        .cloned()
        .collect();

    for key in to_remove {
        if let Some(data) = map.remove(&key) {
            tracing::debug!(kind, ns = ?key.1, "Shutting down namespaced reflector");
            data.cancel.cancel();
            data.handle.abort();
        }
    }
}

#[tracing::instrument(skip(client))]
pub async fn init_reflector_for_kind(
    client: Client,
    gvk: GroupVersionKind,
    namespace: Option<String>,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut map = store_map()
        .write()
        .map_err(|_| "STORE_MAP lock poisoned")?;
    let kind = &gvk.kind;
    let requested_key = key(kind, namespace.as_deref());

    // Check if reflector already exists or can be reused
    let all_key = key(kind, None);
    if map.contains_key(&all_key) || map.contains_key(&requested_key) {
        return Ok(());
    }

    // Starting "All" reflector - shutdown redundant namespaced ones
    if namespace.is_none() {
        shutdown_namespaced_reflectors(&mut map, kind);
    }

    let (reflector, reader) = create_reflector(client, &gvk, namespace).await?;
    map.insert(requested_key, reflector);
    drop(map);

    // Wait for initial sync outside the lock
    let _ = reader.wait_until_ready().await;

    Ok(())
}

#[tracing::instrument(skip(client))]
async fn create_reflector(
    client: Client,
    gvk: &GroupVersionKind,
    namespace: Option<String>,
) -> Result<(ReflectorData, Store<DynamicObject>), Box<dyn std::error::Error>> {
    let ar = ApiResource::from_gvk(gvk);
    let api: Api<DynamicObject> = match &namespace {
        Some(ns) => Api::namespaced_with(client, ns, &ar),
        None => Api::all_with(client, &ar),
    };

    let config = watcher::Config::default().page_size(10500).timeout(20);
    let writer = Writer::new(ar.clone());
    let reader = writer.as_reader();

    let cancel = CancellationToken::new();
    let stream = build_watcher_stream(api, config, &ar, &gvk.kind, cancel.clone(), writer);

    let handle = tokio::spawn(async move {
        stream.for_each(|_| futures::future::ready(())).await;
    });

    let data = ReflectorData {
        store: reader.clone(),
        handle,
        cancel,
    };

    Ok((data, reader))
}

#[tracing::instrument(skip(api, config, ar, cancel, writer))]
fn build_watcher_stream(
    api: Api<DynamicObject>,
    config: watcher::Config,
    ar: &ApiResource,
    kind: &str,
    cancel: CancellationToken,
    writer: Writer<DynamicObject>,
) -> impl futures::Stream<Item = ()> {
    let api_version = ar.api_version.clone();
    let ar_kind = ar.kind.clone();
    let kind_for_events = kind.to_string();

    watcher(api, config)
        .modify(move |resource| {
            resource.managed_fields_mut().clear();
            resource.data["api_version"] = json!(api_version.clone());
            if resource.types.is_none() {
                resource.types = Some(TypeMeta {
                    kind: ar_kind.clone(),
                    api_version: api_version.clone(),
                });
            }
        })
        .default_backoff()
        .map(move |res| {
            if let Ok(event) = &res {
                emit_event(&kind_for_events, event);
            }
            res
        })
        .reflect(writer)
        .take_until(cancel.cancelled_owned())
        .map(|_| ())
}

#[tracing::instrument(skip(event))]
fn emit_event(kind: &str, event: &Event<DynamicObject>) {
    let (event_type, metadata) = match event {
        Event::Apply(obj) => ("MODIFIED", Some(&obj.metadata)),
        Event::Delete(obj) => ("DELETED", Some(&obj.metadata)),
        _ => return,
    };

    let payload = json!({
        "event": event_type,
        "metadata": metadata.and_then(|m| serde_json::to_value(m).ok())
    });

    if let Ok(payload_str) = serde_json::to_string(&payload) {
        let _ = notify_named(kind.to_string(), payload_str);
    }
}

#[tracing::instrument]
pub fn get(kind: &str, namespace: Option<String>) -> Result<Vec<DynamicObject>, mlua::Error> {
    let map = store_map()
        .read()
        .map_err(|_| mlua::Error::RuntimeError("STORE_MAP lock poisoned".into()))?;

    let data = map
        .get(&key(kind, None))
        .or_else(|| map.get(&key(kind, namespace.as_deref())));

    let Some(data) = data else {
        return Ok(Vec::new());
    };

    let result = data
        .store
        .state()
        .par_iter()
        .filter(|obj| matches_namespace(obj, namespace.as_deref()))
        .map(|obj| obj.as_ref().clone())
        .collect();

    Ok(result)
}

#[tracing::instrument]
pub fn get_single(
    kind: &str,
    namespace: Option<String>,
    name: &str,
) -> Result<Option<DynamicObject>, mlua::Error> {
    let map = store_map()
        .read()
        .map_err(|_| mlua::Error::RuntimeError("STORE_MAP lock poisoned".into()))?;

    let data = map
        .get(&key(kind, None))
        .or_else(|| map.get(&key(kind, namespace.as_deref())))
        .ok_or_else(|| mlua::Error::RuntimeError("No store found for kind".into()))?;

    let result = data
        .store
        .state()
        .iter()
        .find(|obj| obj.name_any() == name && matches_namespace(obj, namespace.as_deref()))
        .map(|obj| obj.as_ref().clone());

    Ok(result)
}

fn matches_namespace(obj: &DynamicObject, namespace: Option<&str>) -> bool {
    match (obj.namespace(), namespace) {
        (None, _) => true,                        // Cluster-scoped resources
        (_, None) => true,                        // "All" namespaces requested
        (Some(obj_ns), Some(ns)) => obj_ns == ns, // Specific namespace match
    }
}
