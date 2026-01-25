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
#[derive(Debug, Serialize)]
struct SerializableNode {
    key: String,
    kind: String,
    name: String,
    ns: Option<String>,
    children_keys: Vec<String>,
    leaf_keys: Vec<String>,
    parent_key: Option<String>,
    resource: SerializableResource,
}

#[derive(Debug, Serialize)]
struct SerializableResource {
    kind: String,
    name: String,
    ns: Option<String>,
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
            resource: SerializableResource {
                kind: resource.kind.clone(),
                name: resource.name.clone(),
                ns: resource.namespace.clone(),
            },
        }
    }
}

/// Result structure for lineage graph building
#[derive(Serialize)]
struct TreeResult {
    tree_id: String,
    nodes: Vec<SerializableNode>,
    root_key: String,
}

/// Input structure for build_lineage_graph_worker
#[derive(Debug, serde::Deserialize)]
struct BuildGraphInput {
    resources: Vec<ResourceInput>,
    root_name: String,
}

/// Input resource structure from Lua (matches processRow output)
#[derive(Debug, serde::Deserialize)]
struct ResourceInput {
    kind: String,
    name: String,
    #[serde(rename = "ns")]
    ns: Option<String>,
    #[serde(rename = "apiVersion")]
    api_version: Option<String>,
    #[serde(default)]
    labels: Option<HashMap<String, String>>,
    #[serde(default)]
    selectors: Option<HashMap<String, String>>,
    #[serde(default)]
    metadata: Option<Value>,
    #[serde(default)]
    spec: Option<Value>,
}

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
    let parsed_resources: Vec<Resource> = input
        .resources
        .into_iter()
        .map(parse_resource_typed)
        .collect();

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
        .map(parse_resource_typed)
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

/// Parse a typed ResourceInput into a Resource struct
fn parse_resource_typed(input: ResourceInput) -> Resource {
    let namespace = input.ns.as_deref();

    // Extract ownerReferences from metadata if available
    let owners = input
        .metadata
        .as_ref()
        .and_then(|m| m.get("ownerReferences"))
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
                        .or(namespace)
                        .map(String::from);

                    Some(RelationRef {
                        kind: owner_kind,
                        name: owner_name,
                        namespace: owner_namespace,
                        api_version: owner.get("apiVersion").and_then(|v| v.as_str()).map(String::from),
                        uid: owner.get("uid").and_then(|v| v.as_str()).map(String::from),
                    })
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    // Get UID from metadata if available
    let uid = input
        .metadata
        .as_ref()
        .and_then(|m| m.get("uid"))
        .and_then(|v| v.as_str())
        .map(String::from);

    // Build a combined Value for relationship extraction (metadata + spec)
    let mut combined_value = serde_json::json!({
        "kind": input.kind,
        "apiVersion": input.api_version,
    });

    if let Some(metadata) = &input.metadata {
        combined_value["metadata"] = metadata.clone();
    }
    if let Some(spec) = &input.spec {
        combined_value["spec"] = spec.clone();
    }

    // Extract relationships using Rust relationship extraction
    let relations = super::relationships::extract_relationships(&input.kind, &combined_value);

    Resource {
        kind: input.kind,
        name: input.name,
        namespace: input.ns,
        api_version: input.api_version,
        uid,
        labels: input.labels,
        selectors: input.selectors,
        owners: if owners.is_empty() { None } else { Some(owners) },
        relations: if relations.is_empty() { None } else { Some(relations) },
    }
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
    // Pre-allocate table with known field count (7 fields)
    let table = lua.create_table_with_capacity(0, 7)?;

    table.set("key", key)?;
    table.set("kind", resource.kind.as_str())?;
    table.set("name", resource.name.as_str())?;

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
    let resource_table = lua.create_table_with_capacity(0, 3)?;
    resource_table.set("kind", resource.kind.as_str())?;
    resource_table.set("name", resource.name.as_str())?;
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
        let input = ResourceInput {
            kind: "Pod".to_string(),
            name: "test-pod".to_string(),
            ns: Some("default".to_string()),
            api_version: Some("v1".to_string()),
            labels: Some({
                let mut map = HashMap::new();
                map.insert("app".to_string(), "nginx".to_string());
                map
            }),
            selectors: None,
            metadata: None,
            spec: None,
        };

        let resource = parse_resource_typed(input);
        assert_eq!(resource.kind, "Pod");
        assert_eq!(resource.name, "test-pod");
        assert_eq!(resource.namespace, Some("default".to_string()));
        assert!(resource.labels.is_some());
    }

    #[test]
    fn test_parse_resource_with_owner_refs() {
        let metadata = serde_json::json!({
            "name": "test-pod",
            "namespace": "default",
            "ownerReferences": [{
                "kind": "ReplicaSet",
                "name": "test-rs",
                "apiVersion": "apps/v1",
                "uid": "123"
            }]
        });

        let input = ResourceInput {
            kind: "Pod".to_string(),
            name: "test-pod".to_string(),
            ns: Some("default".to_string()),
            api_version: Some("v1".to_string()),
            labels: None,
            selectors: None,
            metadata: Some(metadata),
            spec: None,
        };

        let resource = parse_resource_typed(input);
        assert_eq!(resource.kind, "Pod");
        assert!(resource.owners.is_some());
        let owners = resource.owners.unwrap();
        assert_eq!(owners.len(), 1);
        assert_eq!(owners[0].kind, "ReplicaSet");
        assert_eq!(owners[0].name, "test-rs");
    }
}
