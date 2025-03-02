use kube::api::DynamicObject;
use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};

static STORE: LazyLock<Mutex<HashMap<String, Vec<DynamicObject>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

pub fn set(kind: &str, items: Vec<DynamicObject>) {
    let mut store = STORE.lock().unwrap();
    store.insert(kind.to_string(), items);
}

pub fn update(kind: &str, item: DynamicObject) {
    let mut store = STORE.lock().unwrap();
    if let Some(items) = store.get_mut(kind) {
        let name = item.metadata.name.clone().unwrap_or_default();
        if let Some(pos) = items
            .iter()
            .position(|obj| obj.metadata.name.as_ref() == Some(&name))
        {
            items[pos] = item;
        } else {
            items.push(item);
        }
    }
}

pub fn delete(kind: &str, item: &DynamicObject) {
    let mut store = STORE.lock().unwrap();
    if let Some(items) = store.get_mut(kind) {
        let name = item.metadata.name.clone().unwrap_or_default();
        items.retain(|obj| obj.metadata.name.as_ref() != Some(&name));
    }
}

pub fn get(kind: &str, namespace: Option<String>) -> Option<Vec<DynamicObject>> {
    let store = STORE.lock().unwrap();
    store.get(kind).map(|items| {
        if let Some(ns) = namespace {
            items
                .iter()
                .filter(|item| item.metadata.namespace.as_ref() == Some(&ns))
                .cloned()
                .collect()
        } else {
            items.clone()
        }
    })
}

pub fn to_json(kind: &str, namespace: Option<String>) -> Option<String> {
    get(kind, namespace).and_then(|items| serde_json::to_string(&items).ok())
}
