use futures::StreamExt;
use k8s_openapi::serde_json::json;
use kube::api::TypeMeta;
use kube::runtime::reflector::store::Writer;
use kube::runtime::{watcher, WatchStreamExt};
use kube::{
    api::{Api, ApiResource, DynamicObject, GroupVersionKind, ResourceExt},
    Client,
};
use rayon::prelude::*;

use kube::runtime::reflector::Store;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::RwLock;
use tokio::task::JoinHandle;
use tracing::info;

pub struct StoreEntry {
    reader: Store<DynamicObject>,
    task: JoinHandle<()>,
    last_event: Arc<AtomicU64>, // updated on every item
}

pub static STORE_MAP: OnceLock<Arc<RwLock<HashMap<String, StoreEntry>>>> = OnceLock::new();
const STALE_AFTER_SECS: u64 = 30;

pub fn get_store_map() -> Arc<RwLock<HashMap<String, StoreEntry>>> {
    STORE_MAP
        .get_or_init(|| Arc::new(RwLock::new(HashMap::new())))
        .clone()
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
}

#[tracing::instrument(skip(client))]
pub async fn init_reflector_for_kind(
    client: Client,
    gvk: GroupVersionKind,
    namespace: Option<String>,
) -> Result<(), Box<dyn std::error::Error>> {
    let store_map = get_store_map();
    {
        let map = store_map.read().await;
        if let Some(e) = map.get(&gvk.kind) {
            let healthy = !e.task.is_finished()
                && (now() - e.last_event.load(Ordering::Relaxed) <= STALE_AFTER_SECS);
            if healthy {
                info!("watcher is healthy");
                return Ok(());
            } else {
                info!("resetting watcher");
            }
        }
    }


    let ar = ApiResource::from_gvk(&gvk);
    let api: Api<DynamicObject> = match namespace {
        Some(ns) => Api::namespaced_with(client.clone(), &ns, &ar),
        None => Api::all_with(client.clone(), &ar),
    };

    let config = watcher::Config::default().page_size(10500).timeout(20);
    let writer: Writer<DynamicObject> = Writer::new(ar.clone());
    let reader: Store<DynamicObject> = writer.as_reader();

    let ar_api_version = ar.api_version.clone();
    let ar_kind = ar.kind.clone();

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
        .reflect(writer);

    let last_event = Arc::new(AtomicU64::new(now()));
    let le = last_event.clone();
    let handle = tokio::spawn(async move {
        stream
            .for_each(move |_res| {
                le.store(now(), Ordering::Relaxed);
                futures::future::ready(())
            })
            .await;
    });

    let _ = reader.wait_until_ready().await;

    {
        let mut map = store_map.write().await;
        if let Some(old) = map.insert(
            gvk.kind.clone(),
            StoreEntry {
                reader,
                task: handle,
                last_event,
            },
        ) {
            old.task.abort();
        }
    }

    Ok(())
}

#[tracing::instrument]
pub async fn get(kind: &str, namespace: Option<String>) -> Result<Vec<DynamicObject>, mlua::Error> {
    let store_map = get_store_map();
    let map = store_map.read().await;
    let store = match map.get(&kind.to_string()) {
        Some(store) => store,
        None => return Ok(Vec::new()),
    };

    let result: Vec<DynamicObject> = store
        .reader
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
    let store_map = get_store_map();
    let map = store_map.read().await;

    let store = map
        .get(&kind.to_string())
        .ok_or_else(|| mlua::Error::RuntimeError("No store found for kind".into()))?;

    let result = store
        .reader
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
