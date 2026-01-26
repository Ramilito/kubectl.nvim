use k8s_openapi::serde_json::{self, Value};
use mlua::prelude::*;
use serde::Serialize;
use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};

use super::tree::{RelationRef, Resource, Tree};

/// Global storage for lineage trees indexed by deterministic key (cluster name)
/// Uses idempotent storage - same key overwrites previous entry, no accumulation
static LINEAGE_TREES: LazyLock<Mutex<HashMap<String, Tree>>> = LazyLock::new(|| Mutex::new(HashMap::new()));

/// Serializable version of TreeNode for JSON output
#[derive(Debug, Serialize, serde::Deserialize)]
struct SerializableNode {
    key: String,
    kind: String,
    name: String,
    ns: Option<String>,
    children_keys: Vec<String>,
    leaf_keys: Vec<String>,
    parent_key: Option<String>,
    is_orphan: bool,
    resource: SerializableResource,
}

#[derive(Debug, Serialize, serde::Deserialize)]
struct SerializableResource {
    kind: String,
    name: String,
    ns: Option<String>,
    is_orphan: bool,
}

impl SerializableNode {
    fn from_resource_and_edges(
        resource: &Resource,
        key: String,
        children_keys: Vec<String>,
        leaf_keys: Vec<String>,
        parent_key: Option<String>,
    ) -> Self {
        Self {
            key: key.clone(),
            kind: resource.kind.clone(),
            name: resource.name.clone(),
            ns: resource.namespace.clone(),
            children_keys,
            leaf_keys,
            parent_key,
            is_orphan: resource.is_orphan,
            resource: SerializableResource {
                kind: resource.kind.clone(),
                name: resource.name.clone(),
                ns: resource.namespace.clone(),
                is_orphan: resource.is_orphan,
            },
        }
    }
}

/// Result structure for lineage graph building
#[derive(Serialize, serde::Deserialize)]
struct TreeResult {
    tree_id: String,
    nodes: Vec<SerializableNode>,
    root_key: String,
}

/// Input structure for build_lineage_graph_worker
#[derive(Debug, serde::Serialize, serde::Deserialize)]
struct BuildGraphInput {
    resources: Vec<ResourceInput>,
    root_name: String,
}

/// Input resource structure from Lua - just the raw K8s resource JSON
/// Rust extracts all needed fields (kind, name, namespace, labels, selectors, etc.)
type ResourceInput = Value;

/// Build lineage graph in a worker thread - called via commands.run_async
/// Takes a single JSON string with {resources, root_name}, returns JSON result
#[tracing::instrument(skip(json_input))]
pub fn build_lineage_graph_worker(json_input: String) -> LuaResult<String> {
    // Parse the input JSON
    let input: BuildGraphInput = serde_json::from_str(&json_input)
        .map_err(|e| LuaError::external(format!("Failed to parse input JSON: {}", e)))?;

    // Use root_name as idempotent tree_id - same cluster always uses same key
    let tree_id = input.root_name.clone();

    // Convert typed input resources to our Resource struct
    let total_resources = input.resources.len();
    let parsed_resources: Vec<Resource> = input
        .resources
        .into_iter()
        .filter_map(parse_resource_typed)
        .collect();

    tracing::info!(
        total_input = total_resources,
        parsed = parsed_resources.len(),
        filtered = total_resources - parsed_resources.len(),
        "Resource parsing completed"
    );

    // Create root resource (cluster) - use tree_id which is root_name
    let root_resource = Resource {
        kind: "cluster".to_string(),
        name: tree_id.clone(),
        namespace: None,
        api_version: None,
        uid: None,
        labels: None,
        selectors: None,
        owners: None,
        relations: None,
        is_orphan: false,
        resource_type: None,
        missing_refs: None,
    };

    // Build the tree with pre-allocated capacity
    let mut tree = Tree::new(root_resource);

    // Add all resources to the tree
    for resource in parsed_resources {
        tree.add_node(resource);
    }

    // Link nodes based on relationships
    tree.link_nodes();

    // Convert tree nodes to serializable format
    // Pre-allocate with exact capacity
    let mut nodes: Vec<SerializableNode> = Vec::with_capacity(tree.graph.node_count());

    // Collect all node indices and sort by key
    let mut node_data: Vec<(String, petgraph::graph::NodeIndex)> = tree
        .key_to_index
        .iter()
        .map(|(key, &idx)| (key.clone(), idx))
        .collect();
    node_data.sort_by(|a, b| a.0.cmp(&b.0));

    for (key, idx) in node_data {
        let resource = &tree.graph[idx];
        let children_keys = tree.get_children_keys(idx);
        let leaf_keys = tree.get_leaf_keys(idx);
        let parent_key = tree.get_parent_key(idx);

        nodes.push(SerializableNode::from_resource_and_edges(
            resource,
            key,
            children_keys,
            leaf_keys,
            parent_key,
        ));
    }

    let result = TreeResult {
        tree_id: tree_id.clone(),
        nodes,
        root_key: tree.root_key.clone(),
    };

    // Store the tree
    let mut trees = LINEAGE_TREES
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to lock LINEAGE_TREES".into()))?;
    trees.insert(tree_id, tree);

    // Return as JSON string
    serde_json::to_string(&result)
        .map_err(|e| LuaError::external(format!("Failed to serialize result: {}", e)))
}

/// Get related nodes for a given node in a stored tree
/// Returns JSON array of related node keys
#[tracing::instrument(skip(_lua))]
pub fn get_lineage_related_nodes(_lua: &Lua, (tree_id, node_key): (String, String)) -> LuaResult<String> {
    let trees = LINEAGE_TREES
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to lock LINEAGE_TREES".into()))?;

    let tree = trees
        .get(&tree_id)
        .ok_or_else(|| LuaError::RuntimeError(format!("Tree not found: {}", tree_id)))?;

    let related_keys = tree.get_related_items(&node_key);

    serde_json::to_string(&related_keys)
        .map_err(|e| LuaError::external(format!("Failed to serialize related nodes: {}", e)))
}

/// Export lineage graph to Graphviz DOT format
/// Returns DOT string for the specified tree
#[tracing::instrument(skip(_lua))]
pub fn export_lineage_dot(_lua: &Lua, tree_id: String) -> LuaResult<String> {
    let trees = LINEAGE_TREES
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to lock LINEAGE_TREES".into()))?;

    let tree = trees
        .get(&tree_id)
        .ok_or_else(|| LuaError::RuntimeError(format!("Tree not found: {}", tree_id)))?;

    Ok(tree.export_dot())
}

/// Export lineage graph to Mermaid diagram format
/// Returns Mermaid string for the specified tree
#[tracing::instrument(skip(_lua))]
pub fn export_lineage_mermaid(_lua: &Lua, tree_id: String) -> LuaResult<String> {
    let trees = LINEAGE_TREES
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to lock LINEAGE_TREES".into()))?;

    let tree = trees
        .get(&tree_id)
        .ok_or_else(|| LuaError::RuntimeError(format!("Tree not found: {}", tree_id)))?;

    Ok(tree.to_mermaid())
}

/// Export lineage subgraph to Graphviz DOT format
/// Returns DOT string for the subgraph centered on the specified resource
#[tracing::instrument(skip(_lua))]
pub fn export_lineage_subgraph_dot(_lua: &Lua, (tree_id, resource_key): (String, String)) -> LuaResult<String> {
    let trees = LINEAGE_TREES
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to lock LINEAGE_TREES".into()))?;

    let tree = trees
        .get(&tree_id)
        .ok_or_else(|| LuaError::RuntimeError(format!("Tree not found: {}", tree_id)))?;

    Ok(tree.export_subgraph_dot(&resource_key))
}

/// Export lineage subgraph to Mermaid diagram format
/// Returns Mermaid string for the subgraph centered on the specified resource
#[tracing::instrument(skip(_lua))]
pub fn export_lineage_subgraph_mermaid(_lua: &Lua, (tree_id, resource_key): (String, String)) -> LuaResult<String> {
    let trees = LINEAGE_TREES
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to lock LINEAGE_TREES".into()))?;

    let tree = trees
        .get(&tree_id)
        .ok_or_else(|| LuaError::RuntimeError(format!("Tree not found: {}", tree_id)))?;

    Ok(tree.export_subgraph_mermaid(&resource_key))
}

/// Find orphan resources in a stored tree
/// Returns JSON array of orphan resource keys
#[tracing::instrument(skip(_lua))]
pub fn find_lineage_orphans(_lua: &Lua, tree_id: String) -> LuaResult<String> {
    let trees = LINEAGE_TREES
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to lock LINEAGE_TREES".into()))?;

    let tree = trees
        .get(&tree_id)
        .ok_or_else(|| LuaError::RuntimeError(format!("Tree not found: {}", tree_id)))?;

    let orphans = tree.find_orphans();

    serde_json::to_string(&orphans)
        .map_err(|e| LuaError::external(format!("Failed to serialize orphans: {}", e)))
}

/// Compute impact analysis for a resource
/// Returns JSON array of tuples: [[resource_key, edge_type], ...]
#[tracing::instrument(skip(_lua))]
pub fn compute_lineage_impact(_lua: &Lua, (tree_id, resource_key): (String, String)) -> LuaResult<String> {
    let trees = LINEAGE_TREES
        .lock()
        .map_err(|_| LuaError::RuntimeError("Failed to lock LINEAGE_TREES".into()))?;

    let tree = trees
        .get(&tree_id)
        .ok_or_else(|| LuaError::RuntimeError(format!("Tree not found: {}", tree_id)))?;

    let impacted = tree.compute_impact(&resource_key);

    serde_json::to_string(&impacted)
        .map_err(|e| LuaError::external(format!("Failed to serialize impact analysis: {}", e)))
}

/// Build a lineage graph from a list of Kubernetes resources
/// Returns a Lua table with the tree structure
#[tracing::instrument(skip(lua, resources_json))]
pub fn build_lineage_graph(lua: &Lua, resources_json: String, root_name: String) -> LuaResult<LuaTable> {
    // Parse the JSON input using typed deserialization
    let resources: Vec<ResourceInput> = serde_json::from_str(&resources_json)
        .map_err(|e| LuaError::external(format!("Failed to parse resources JSON: {}", e)))?;

    // Convert typed input resources to our Resource struct
    let parsed_resources: Vec<Resource> = resources
        .into_iter()
        .filter_map(parse_resource_typed)
        .collect();

    // Create root resource (cluster)
    let root_resource = Resource {
        kind: "cluster".to_string(),
        name: root_name,
        namespace: None,
        api_version: None,
        uid: None,
        labels: None,
        selectors: None,
        owners: None,
        relations: None,
        is_orphan: false,
        resource_type: None,
        missing_refs: None,
    };

    // Build the tree with pre-allocated capacity
    let mut tree = Tree::new(root_resource);

    // Add all resources to the tree
    for resource in parsed_resources {
        tree.add_node(resource);
    }

    // Link nodes based on relationships
    tree.link_nodes();

    // Convert tree to Lua table
    tree_to_lua_table(lua, &tree)
}

/// Parse a raw K8s resource JSON into a Resource struct
/// Extracts all needed fields from the JSON
fn parse_resource_typed(input: ResourceInput) -> Option<Resource> {
    // Extract kind - can be at top level or we skip this resource
    let kind = input.get("kind").and_then(|v| v.as_str())?;

    // Extract metadata early to get name for logging
    let metadata = input.get("metadata")?;
    let name = metadata.get("name").and_then(|v| v.as_str())?;

    // Log when we're parsing RBAC resources
    if kind.to_lowercase().contains("role") {
        tracing::debug!(
            resource_kind = %kind,
            resource_name = %name,
            "Parsing RBAC resource"
        );
    }

    let kind = kind.to_string();
    let name = name.to_string();
    let namespace = metadata
        .get("namespace")
        .and_then(|v| v.as_str())
        .map(String::from);

    // Extract apiVersion
    let api_version = input
        .get("apiVersion")
        .and_then(|v| v.as_str())
        .map(String::from);

    // Extract UID
    let uid = metadata
        .get("uid")
        .and_then(|v| v.as_str())
        .map(String::from);

    // Extract labels from metadata.labels
    let labels = metadata.get("labels").and_then(|v| {
        v.as_object().map(|obj| {
            obj.iter()
                .filter_map(|(k, v)| v.as_str().map(|s| (k.clone(), s.to_string())))
                .collect::<HashMap<String, String>>()
        })
    });

    // Extract selectors from spec.selector.matchLabels or spec.selector
    let selectors = input.get("spec").and_then(|spec| {
        spec.get("selector").and_then(|sel| {
            // Try matchLabels first (Deployments, ReplicaSets, etc.)
            let label_map = sel
                .get("matchLabels")
                .or(Some(sel))
                .and_then(|m| m.as_object());

            label_map.map(|obj| {
                obj.iter()
                    .filter_map(|(k, v)| v.as_str().map(|s| (k.clone(), s.to_string())))
                    .collect::<HashMap<String, String>>()
            })
        })
    });

    // Extract ownerReferences from metadata
    let owners = metadata
        .get("ownerReferences")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|owner| {
                    let owner_kind = owner.get("kind")?.as_str()?.to_string();
                    let owner_name = owner.get("name")?.as_str()?.to_string();

                    // Try to get namespace from owner reference first, then fall back to resource namespace
                    let owner_namespace = owner
                        .get("namespace")
                        .and_then(|v| v.as_str())
                        .map(String::from)
                        .or_else(|| namespace.clone());

                    Some(RelationRef {
                        kind: owner_kind,
                        name: owner_name,
                        namespace: owner_namespace,
                        api_version: owner
                            .get("apiVersion")
                            .and_then(|v| v.as_str())
                            .map(String::from),
                        uid: owner.get("uid").and_then(|v| v.as_str()).map(String::from),
                    })
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    // Extract relationships using Rust relationship extraction (uses full raw JSON)
    let relations = super::relationships::extract_relationships(&kind, &input);

    // Extract resource-specific type information
    // For Secrets, extract the type field (e.g., "kubernetes.io/service-account-token")
    let resource_type = if kind == "Secret" {
        input.get("type").and_then(|v| v.as_str()).map(String::from)
    } else {
        None
    };

    Some(Resource {
        kind,
        name,
        namespace,
        api_version,
        uid,
        labels,
        selectors,
        owners: if owners.is_empty() { None } else { Some(owners) },
        relations: if relations.is_empty() {
            None
        } else {
            Some(relations)
        },
        is_orphan: false,
        resource_type,
        missing_refs: None,
    })
}

/// Convert the tree structure to a Lua table
fn tree_to_lua_table(lua: &Lua, tree: &Tree) -> LuaResult<LuaTable> {
    let result = lua.create_table()?;

    // Create nodes table with pre-allocated capacity
    let nodes_table = lua.create_table_with_capacity(tree.graph.node_count(), 0)?;

    // Collect all node indices and sort by key
    let mut node_data: Vec<(String, petgraph::graph::NodeIndex)> = tree
        .key_to_index
        .iter()
        .map(|(key, &idx)| (key.clone(), idx))
        .collect();
    node_data.sort_by(|a, b| a.0.cmp(&b.0));

    for (lua_idx, (key, idx)) in node_data.iter().enumerate() {
        let resource = &tree.graph[*idx];
        let children_keys = tree.get_children_keys(*idx);
        let leaf_keys = tree.get_leaf_keys(*idx);
        let parent_key = tree.get_parent_key(*idx);

        let node_table = node_to_lua_table(lua, resource, key, children_keys, leaf_keys, parent_key)?;
        nodes_table.set(lua_idx + 1, node_table)?;
    }

    result.set("nodes", nodes_table)?;

    // Create a function to get related nodes
    let tree_clone = tree.clone();
    let get_related = lua.create_function(move |lua, selected_key: String| {
        let related_keys = tree_clone.get_related_items(&selected_key);
        let related_table = lua.create_table()?;

        for (idx, key) in related_keys.iter().enumerate() {
            related_table.set(idx + 1, key.clone())?;
        }

        Ok(related_table)
    })?;

    result.set("get_related_nodes", get_related)?;

    // Add root key
    result.set("root_key", tree.root_key.clone())?;

    Ok(result)
}

/// Convert a Resource and edge data to a Lua table
fn node_to_lua_table(
    lua: &Lua,
    resource: &Resource,
    key: &str,
    children_keys: Vec<String>,
    leaf_keys: Vec<String>,
    parent_key: Option<String>,
) -> LuaResult<LuaTable> {
    // Pre-allocate table with known field count (8 fields - added is_orphan)
    let table = lua.create_table_with_capacity(0, 8)?;

    table.set("key", key)?;
    table.set("kind", resource.kind.as_str())?;
    table.set("name", resource.name.as_str())?;
    table.set("is_orphan", resource.is_orphan)?;

    if let Some(ref ns) = resource.namespace {
        table.set("ns", ns.as_str())?;
    } else {
        table.set("ns", LuaValue::Nil)?;
    }

    // Children keys
    let children_table = lua.create_table_with_capacity(children_keys.len(), 0)?;
    for (idx, child_key) in children_keys.iter().enumerate() {
        children_table.set(idx + 1, child_key.as_str())?;
    }
    table.set("children_keys", children_table)?;

    // Leaf keys
    let leafs_table = lua.create_table_with_capacity(leaf_keys.len(), 0)?;
    for (idx, leaf_key) in leaf_keys.iter().enumerate() {
        leafs_table.set(idx + 1, leaf_key.as_str())?;
    }
    table.set("leaf_keys", leafs_table)?;

    // Parent key
    if let Some(ref parent_key) = parent_key {
        table.set("parent_key", parent_key.as_str())?;
    } else {
        table.set("parent_key", LuaValue::Nil)?;
    }

    // Resource data (for debugging/display)
    let resource_table = lua.create_table_with_capacity(0, 4)?;
    resource_table.set("kind", resource.kind.as_str())?;
    resource_table.set("name", resource.name.as_str())?;
    resource_table.set("is_orphan", resource.is_orphan)?;
    if let Some(ref ns) = resource.namespace {
        resource_table.set("ns", ns.as_str())?;
    }
    table.set("resource", resource_table)?;

    Ok(table)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_resource_typed() {
        let input = serde_json::json!({
            "kind": "Pod",
            "apiVersion": "v1",
            "metadata": {
                "name": "test-pod",
                "namespace": "default",
                "labels": {
                    "app": "nginx"
                }
            }
        });

        let resource = parse_resource_typed(input).unwrap();
        assert_eq!(resource.kind, "Pod");
        assert_eq!(resource.name, "test-pod");
        assert_eq!(resource.namespace, Some("default".to_string()));
        assert!(resource.labels.is_some());
    }

    #[test]
    fn test_parse_resource_with_owner_refs() {
        let input = serde_json::json!({
            "kind": "Pod",
            "apiVersion": "v1",
            "metadata": {
                "name": "test-pod",
                "namespace": "default",
                "ownerReferences": [{
                    "kind": "ReplicaSet",
                    "name": "test-rs",
                    "apiVersion": "apps/v1",
                    "uid": "123"
                }]
            }
        });

        let resource = parse_resource_typed(input).unwrap();
        assert_eq!(resource.kind, "Pod");
        assert!(resource.owners.is_some());
        let owners = resource.owners.unwrap();
        assert_eq!(owners.len(), 1);
        assert_eq!(owners[0].kind, "ReplicaSet");
        assert_eq!(owners[0].name, "test-rs");
    }
}
