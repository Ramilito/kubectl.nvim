pub mod nodes;
pub mod pods;

use std::sync::atomic::{AtomicBool, Ordering};

/// Dirty flags for metrics - set when collectors update data, cleared after UI renders
static POD_STATS_DIRTY: AtomicBool = AtomicBool::new(true);
static NODE_STATS_DIRTY: AtomicBool = AtomicBool::new(true);

/// Marks pod stats as dirty (new data available). Called by the pod collector.
pub fn mark_pod_stats_dirty() {
    POD_STATS_DIRTY.store(true, Ordering::Release);
}

/// Marks node stats as dirty (new data available). Called by the node collector.
pub fn mark_node_stats_dirty() {
    NODE_STATS_DIRTY.store(true, Ordering::Release);
}

/// Checks if metrics data has changed since last render.
/// Returns true and clears the flag if dirty, false otherwise.
pub fn take_metrics_dirty() -> bool {
    let pod_dirty = POD_STATS_DIRTY.swap(false, Ordering::AcqRel);
    let node_dirty = NODE_STATS_DIRTY.swap(false, Ordering::AcqRel);
    pod_dirty || node_dirty
}
