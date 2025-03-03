use kube::api::DynamicObject;
use std::collections::HashMap;
use std::sync::{LazyLock, RwLock};

static STORE: LazyLock<RwLock<HashMap<String, HashMap<Option<String>, HashMap<String, DynamicObject>>>>> =
    LazyLock::new(|| RwLock::new(HashMap::new()));

pub fn set(kind: &str, items: Vec<DynamicObject>) {
    let mut store = STORE.write().unwrap();
    let mut ns_map: HashMap<Option<String>, HashMap<String, DynamicObject>> = HashMap::new();
    for item in items {
        let ns = item.metadata.namespace.clone();
        let name = item.metadata.name.clone().unwrap_or_default();
        ns_map.entry(ns)
            .or_insert_with(HashMap::new)
            .insert(name, item);
    }
    store.insert(kind.to_string(), ns_map);
}

pub fn update(kind: &str, item: DynamicObject) {
    let mut store = STORE.write().unwrap();
    let ns_map = store.entry(kind.to_string()).or_insert_with(HashMap::new);
    let ns = item.metadata.namespace.clone();
    let name = item.metadata.name.clone().unwrap_or_default();
    ns_map.entry(ns)
        .or_insert_with(HashMap::new)
        .insert(name, item);
}

pub fn delete(kind: &str, item: &DynamicObject) {
    let mut store = STORE.write().unwrap();
    if let Some(ns_map) = store.get_mut(kind) {
        let ns = item.metadata.namespace.clone();
        let name = item.metadata.name.clone().unwrap_or_default();
        if let Some(name_map) = ns_map.get_mut(&ns) {
            name_map.remove(&name);
        }
    }
}

pub fn get(kind: &str, namespace: Option<String>) -> Option<Vec<DynamicObject>> {
    let store = STORE.read().unwrap();
    store.get(kind).map(|ns_map| {
        if let Some(ns) = namespace {
            ns_map.get(&Some(ns))
                .map(|name_map| name_map.values().cloned().collect())
                .unwrap_or_default()
        } else {
            ns_map.values()
                .flat_map(|name_map| name_map.values().cloned())
                .collect()
        }
    })
}
