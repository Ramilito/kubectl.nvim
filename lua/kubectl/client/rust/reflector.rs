use futures::StreamExt;
use kube::{
    api::{Api, ApiResource, DynamicObject, GroupVersionKind, ListParams, ResourceExt},
    runtime::{
        reflector::{self, store::Writer},
        watcher, WatchStreamExt,
    },
    Client,
};
use std::collections::HashMap;
use std::sync::{Arc, OnceLock};
use tokio::sync::RwLock;

static STORE_MAP: OnceLock<Arc<RwLock<HashMap<String, reflector::Store<DynamicObject>>>>> =
    OnceLock::new();

fn get_store_map() -> &'static Arc<RwLock<HashMap<String, reflector::Store<DynamicObject>>>> {
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

    let writer = Writer::new(ar.clone());
    let reader = writer.as_reader();
    // let rf = reflector(writer, watcher(api, config));


    // let rf = reflector(writer, watcher(api, config));

    tokio::spawn(async move {
        // rf.for_each(|_| futures::future::ready(())).await;
    });

    let mut map = get_store_map().write().await;
    map.insert(gvk.kind.to_lowercase(), reader);

    Ok(())
}
//
// pub async fn get(kind: &str, namespace: Option<String>) -> Vec<DynamicObject> {
//     let map = get_store_map().read().await;
//     if let Some(store) = map.get(&kind.to_lowercase()) {
//         store
//             .state()
//             .iter()
//             .filter(|obj| match &namespace {
//                 Some(ns) => obj.namespace().as_deref() == Some(ns),
//                 None => true,
//             })
//             .cloned()
//             .collect()
//     } else {
//         vec![]
//     }
// }
//
// pub async fn get_single(kind: &str, namespace: Option<String>, name: &str) -> Option<DynamicObject> {
//     let map = get_store_map().read().await;
//     map.get(&kind.to_lowercase()).and_then(|store| {
//         store
//             .state()
//             .iter()
//             .find(|obj| {
//                 obj.name_any() == name && match &namespace {
//                     Some(ns) => obj.namespace().as_deref() == Some(ns),
//                     None => true,
//                 }
//             })
//             .cloned()
//     })
// }
