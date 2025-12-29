//! Data fetching for the Overview view.
//!
//! Provides functions to fetch cluster data from the store.

use kube::api::{DynamicObject, GroupVersionKind, ResourceExt};
use std::sync::OnceLock;
use tokio::{runtime::Handle, task};

use crate::{store, with_client};

/// Track whether we've initialized the overview reflectors.
static REFLECTORS_INIT: OnceLock<()> = OnceLock::new();

/// Namespace information for display.
#[derive(Clone)]
pub struct NamespaceInfo {
    pub name: String,
    pub status: String,
}

/// Event information for display.
#[derive(Clone)]
pub struct EventInfo {
    pub namespace: String,
    pub type_: String,
    pub reason: String,
    pub object: String,
    pub message: String,
    pub count: i32,
}

/// Cluster statistics for the info pane.
#[derive(Clone, Default)]
pub struct ClusterStats {
    pub node_count: usize,
    pub ready_node_count: usize,
    pub pod_count: usize,
    pub namespace_count: usize,
}

/// Runs an async function in a blocking context.
fn block_on<F: std::future::Future>(fut: F) -> F::Output {
    match Handle::try_current() {
        Ok(h) => task::block_in_place(|| h.block_on(fut)),
        Err(_) => {
            // Fallback - shouldn't happen in UI context
            panic!("No tokio runtime available");
        }
    }
}

/// Ensures reflectors for Namespace and Event are initialized.
fn ensure_reflectors() {
    REFLECTORS_INIT.get_or_init(|| {
        block_on(async {
            // Initialize Namespace reflector (core/v1)
            let ns_gvk = GroupVersionKind::gvk("", "v1", "Namespace");
            let _ = with_client(|client| async move {
                store::init_reflector_for_kind(client.clone(), ns_gvk, None).await.ok();
                Ok::<(), mlua::Error>(())
            });

            // Initialize Event reflector (events.k8s.io/v1)
            let event_gvk = GroupVersionKind::gvk("events.k8s.io", "v1", "Event");
            let _ = with_client(|client| async move {
                store::init_reflector_for_kind(client.clone(), event_gvk, None).await.ok();
                Ok::<(), mlua::Error>(())
            });

            // Initialize Pod reflector for stats (core/v1)
            let pod_gvk = GroupVersionKind::gvk("", "v1", "Pod");
            let _ = with_client(|client| async move {
                store::init_reflector_for_kind(client.clone(), pod_gvk, None).await.ok();
                Ok::<(), mlua::Error>(())
            });
        });
    });
}

/// Fetches all namespaces from the store.
pub fn fetch_namespaces() -> Vec<NamespaceInfo> {
    ensure_reflectors();
    let objects = block_on(async { store::get("Namespace", None).await.unwrap_or_default() });

    let mut namespaces: Vec<NamespaceInfo> = objects
        .iter()
        .map(|obj| {
            let name = obj.name_any();
            let status = extract_namespace_status(obj);
            NamespaceInfo { name, status }
        })
        .collect();

    // Sort by name
    namespaces.sort_by(|a, b| a.name.cmp(&b.name));
    namespaces
}

/// Fetches recent events from the store (Warning and Error only).
pub fn fetch_events() -> Vec<EventInfo> {
    ensure_reflectors();
    let objects = block_on(async { store::get("Event", None).await.unwrap_or_default() });

    let mut events: Vec<EventInfo> = objects
        .iter()
        .filter_map(|obj| extract_event_info(obj))
        // Only show Warning and Error events
        .filter(|ev| ev.type_ == "Warning" || ev.type_ == "Error")
        .collect();

    // Sort by count (descending) - most frequent events first
    events.sort_by(|a, b| b.count.cmp(&a.count));

    // Limit to most recent/frequent
    events.truncate(50);
    events
}

/// Fetches cluster statistics.
pub fn fetch_cluster_stats(node_count: usize, ready_node_count: usize) -> ClusterStats {
    ensure_reflectors();
    let pod_count =
        block_on(async { store::get("Pod", None).await.unwrap_or_default().len() });

    let namespace_count =
        block_on(async { store::get("Namespace", None).await.unwrap_or_default().len() });

    ClusterStats {
        node_count,
        ready_node_count,
        pod_count,
        namespace_count,
    }
}

/// Extracts namespace status from a DynamicObject.
fn extract_namespace_status(obj: &DynamicObject) -> String {
    obj.data
        .get("status")
        .and_then(|s| s.get("phase"))
        .and_then(|p| p.as_str())
        .unwrap_or("Unknown")
        .to_string()
}

/// Extracts event information from a DynamicObject.
fn extract_event_info(obj: &DynamicObject) -> Option<EventInfo> {
    let namespace = obj.namespace().unwrap_or_default();

    // Try new Event API format first (events.k8s.io/v1)
    let type_ = obj
        .data
        .get("type")
        .and_then(|v| v.as_str())
        .unwrap_or("Normal")
        .to_string();

    let reason = obj
        .data
        .get("reason")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    // Get the involved object
    let object = if let Some(regarding) = obj.data.get("regarding") {
        // New API format
        let kind = regarding.get("kind").and_then(|v| v.as_str()).unwrap_or("");
        let name = regarding.get("name").and_then(|v| v.as_str()).unwrap_or("");
        format!("{}/{}", kind, name)
    } else if let Some(involved) = obj.data.get("involvedObject") {
        // Old API format
        let kind = involved.get("kind").and_then(|v| v.as_str()).unwrap_or("");
        let name = involved.get("name").and_then(|v| v.as_str()).unwrap_or("");
        format!("{}/{}", kind, name)
    } else {
        "Unknown".to_string()
    };

    let message = obj
        .data
        .get("message")
        .or_else(|| obj.data.get("note"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    // Get count (new API uses series.count or deprecatedCount)
    let count = obj
        .data
        .get("count")
        .and_then(|v| v.as_i64())
        .or_else(|| {
            obj.data
                .get("series")
                .and_then(|s| s.get("count"))
                .and_then(|v| v.as_i64())
        })
        .or_else(|| {
            obj.data
                .get("deprecatedCount")
                .and_then(|v| v.as_i64())
        })
        .unwrap_or(1) as i32;

    Some(EventInfo {
        namespace,
        type_,
        reason,
        object,
        message,
        count,
    })
}
