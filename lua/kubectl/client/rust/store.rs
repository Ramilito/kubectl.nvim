use futures::StreamExt;
use kube::runtime::reflector::store::Writer;
use kube::runtime::{watcher, WatchStreamExt};
use kube::{
    api::{Api, ApiResource, DynamicObject, GroupVersionKind, ResourceExt},
    Client,
};

use kube::runtime::reflector::Store;
use std::collections::HashMap;
use std::sync::{Arc, OnceLock};
use tokio::sync::RwLock;

type StoreMap = Arc<RwLock<HashMap<String, Store<DynamicObject>>>>;
static STORE_MAP: OnceLock<StoreMap> = OnceLock::new();

fn get_store_map() -> &'static Arc<RwLock<HashMap<String, Store<DynamicObject>>>> {
    STORE_MAP.get_or_init(|| Arc::new(RwLock::new(HashMap::new())))
}

pub async fn init_reflector_for_kind(
    client: Client,
    gvk: GroupVersionKind,
    namespace: Option<String>,
) -> Result<(), Box<dyn std::error::Error>> {
    let ar = ApiResource::from_gvk(&gvk);
    let api: Api<DynamicObject> = match namespace {
        Some(ns) => Api::namespaced_with(client.clone(), &ns, &ar),
        None => Api::all_with(client.clone(), &ar),
    };

    let config = watcher::Config::default();
    let writer: Writer<DynamicObject> = Writer::new(ar.clone());
    let reader: Store<DynamicObject> = writer.as_reader();

    let stream = watcher(api, config)
        .modify(|resource| {
            resource.managed_fields_mut().clear();
        })
        .reflect(writer);

    tokio::spawn(async move {
        stream.for_each(|_| futures::future::ready(())).await;
    });

    let mut map = get_store_map().write().await;
    let _ = reader.wait_until_ready().await;
    map.insert(gvk.kind.to_string(), reader);

    Ok(())
}

pub async fn get(kind: &str, namespace: Option<String>) -> Result<Vec<DynamicObject>, mlua::Error> {
    let map = get_store_map().read().await;
    let store = map
        .get(&kind.to_lowercase())
        .ok_or_else(|| mlua::Error::RuntimeError("No store found for kind".into()))?;
    let _ = store.wait_until_ready().await;

    let result: Vec<DynamicObject> = store
        .state()
        .iter()
        .filter(|arc_obj| {
            let obj = arc_obj.as_ref();
            match &namespace {
                Some(ns) => obj.namespace().as_deref() == Some(ns),
                None => true,
            }
        })
        .map(|arc_obj| arc_obj.as_ref().clone())
        .collect();

    Ok(result)
}

pub async fn get_single(
    kind: &str,
    namespace: Option<String>,
    name: &str,
) -> Result<Option<DynamicObject>, mlua::Error> {
    let map = get_store_map().read().await;

    let store = map
        .get(&kind.to_lowercase())
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
