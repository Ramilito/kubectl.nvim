use k8s_openapi::serde_json::{self, Value};
use mlua::prelude::*;
use std::collections::HashMap;

use super::tree::{RelationRef, Resource, Tree, TreeNode};

/// Build a lineage graph from a list of Kubernetes resources
/// Returns a Lua table with the tree structure
#[tracing::instrument(skip(lua))]
pub fn build_lineage_graph(lua: &Lua, resources_json: String, root_name: String) -> LuaResult<LuaTable> {
    // Parse the JSON input
    let resources: Vec<Value> = serde_json::from_str(&resources_json)
        .map_err(|e| LuaError::external(format!("Failed to parse resources JSON: {}", e)))?;

    // Build a map of resource kinds to their namespaced status
    let namespaced_map = HashMap::new();
    for resource_value in &resources {
        if let (Some(_kind), Some(_namespaced)) = (
            resource_value.get("kind").and_then(|v| v.as_str()),
            resource_value.get("namespaced").and_then(|v| v.as_bool()),
        ) {
            // Note: namespaced_map is no longer used as we determine namespace
            // from the resource itself via ownerReferences
        }
    }

    // Convert JSON resources to our Resource struct
    let mut parsed_resources: Vec<Resource> = Vec::new();
    for resource_value in resources {
        if let Some(resource) = parse_resource(&resource_value, &namespaced_map) {
            parsed_resources.push(resource);
        }
    }

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

    // Build the tree
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

/// Parse a JSON value into a Resource struct
fn parse_resource(value: &Value, _namespaced_map: &HashMap<String, bool>) -> Option<Resource> {
    let kind = value.get("kind")?.as_str()?.to_string();
    let name = value
        .get("name")
        .or_else(|| value.get("metadata")?.get("name"))?
        .as_str()?
        .to_string();

    let namespace = value
        .get("ns")
        .or_else(|| value.get("metadata").and_then(|m| m.get("namespace")))
        .and_then(|v| v.as_str())
        .map(String::from);

    let api_version = value
        .get("apiVersion")
        .and_then(|v| v.as_str())
        .map(String::from);

    let uid = value
        .get("uid")
        .or_else(|| value.get("metadata").and_then(|m| m.get("uid")))
        .and_then(|v| v.as_str())
        .map(String::from);

    // Parse labels
    let labels = value
        .get("labels")
        .or_else(|| value.get("metadata").and_then(|m| m.get("labels")))
        .and_then(|v| v.as_object())
        .map(|obj| {
            obj.iter()
                .filter_map(|(k, v)| v.as_str().map(|s| (k.clone(), s.to_string())))
                .collect::<HashMap<String, String>>()
        });

    // Parse selectors
    let selectors = value.get("selectors").and_then(|v| v.as_object()).map(|obj| {
        obj.iter()
            .filter_map(|(k, v)| v.as_str().map(|s| (k.clone(), s.to_string())))
            .collect::<HashMap<String, String>>()
    });

    // Parse owners from ownerReferences in metadata
    let mut owners = value
        .get("metadata")
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
                        .or(namespace.as_deref())
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

    // Also merge any owners already set from Lua processing
    if let Some(lua_owners) = value
        .get("owners")
        .and_then(|v| v.as_array())
    {
        for owner in lua_owners.iter().filter_map(parse_relation_ref) {
            if !owners.iter().any(|o| o.kind == owner.kind && o.name == owner.name) {
                owners.push(owner);
            }
        }
    }

    // Extract relationships using Rust relationship extraction
    let mut relations = super::relationships::extract_relationships(&kind, value);

    // Also merge any relations already set from Lua processing
    if let Some(lua_relations) = value
        .get("relations")
        .and_then(|v| v.as_array())
    {
        for relation in lua_relations.iter().filter_map(parse_relation_ref) {
            if !relations.iter().any(|r| r.kind == relation.kind && r.name == relation.name) {
                relations.push(relation);
            }
        }
    }

    Some(Resource {
        kind,
        name,
        namespace,
        api_version,
        uid,
        labels,
        selectors,
        owners: if owners.is_empty() { None } else { Some(owners) },
        relations: if relations.is_empty() { None } else { Some(relations) },
    })
}

/// Parse a JSON value into a RelationRef
fn parse_relation_ref(value: &Value) -> Option<RelationRef> {
    let kind = value.get("kind")?.as_str()?.to_string();
    let name = value.get("name")?.as_str()?.to_string();
    let namespace = value
        .get("ns")
        .or_else(|| value.get("namespace"))
        .and_then(|v| v.as_str())
        .map(String::from);
    let api_version = value
        .get("apiVersion")
        .and_then(|v| v.as_str())
        .map(String::from);
    let uid = value.get("uid").and_then(|v| v.as_str()).map(String::from);

    Some(RelationRef {
        kind,
        name,
        namespace,
        api_version,
        uid,
    })
}

/// Convert the tree structure to a Lua table
fn tree_to_lua_table(lua: &Lua, tree: &Tree) -> LuaResult<LuaTable> {
    let result = lua.create_table()?;

    // Create nodes table
    let nodes_table = lua.create_table()?;

    // Sort node keys for consistent ordering
    let mut node_keys: Vec<&String> = tree.nodes.keys().collect();
    node_keys.sort();

    for (idx, key) in node_keys.iter().enumerate() {
        if let Some(node) = tree.nodes.get(*key) {
            let node_table = node_to_lua_table(lua, node)?;
            nodes_table.set(idx + 1, node_table)?;
        }
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
    result.set("root_key", tree.root.key.clone())?;

    Ok(result)
}

/// Convert a TreeNode to a Lua table
fn node_to_lua_table(lua: &Lua, node: &TreeNode) -> LuaResult<LuaTable> {
    let table = lua.create_table()?;

    table.set("key", node.key.clone())?;
    table.set("kind", node.resource.kind.clone())?;
    table.set("name", node.resource.name.clone())?;

    if let Some(ref ns) = node.resource.namespace {
        table.set("ns", ns.clone())?;
    } else {
        table.set("ns", LuaValue::Nil)?;
    }

    // Children keys
    let children_table = lua.create_table()?;
    for (idx, child_key) in node.children_keys.iter().enumerate() {
        children_table.set(idx + 1, child_key.clone())?;
    }
    table.set("children_keys", children_table)?;

    // Leaf keys
    let leafs_table = lua.create_table()?;
    for (idx, leaf_key) in node.leaf_keys.iter().enumerate() {
        leafs_table.set(idx + 1, leaf_key.clone())?;
    }
    table.set("leaf_keys", leafs_table)?;

    // Parent key
    if let Some(ref parent_key) = node.parent_key {
        table.set("parent_key", parent_key.clone())?;
    } else {
        table.set("parent_key", LuaValue::Nil)?;
    }

    // Resource data (for debugging/display)
    let resource_table = lua.create_table()?;
    resource_table.set("kind", node.resource.kind.clone())?;
    resource_table.set("name", node.resource.name.clone())?;
    if let Some(ref ns) = node.resource.namespace {
        resource_table.set("ns", ns.clone())?;
    }
    table.set("resource", resource_table)?;

    Ok(table)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_resource() {
        let json = serde_json::json!({
            "kind": "Pod",
            "name": "test-pod",
            "ns": "default",
            "labels": {
                "app": "nginx"
            }
        });

        let namespaced_map = HashMap::new();
        let resource = parse_resource(&json, &namespaced_map).unwrap();
        assert_eq!(resource.kind, "Pod");
        assert_eq!(resource.name, "test-pod");
        assert_eq!(resource.namespace, Some("default".to_string()));
        assert!(resource.labels.is_some());
    }

    #[test]
    fn test_parse_relation_ref() {
        let json = serde_json::json!({
            "kind": "Deployment",
            "name": "test-deployment",
            "ns": "default"
        });

        let relation = parse_relation_ref(&json).unwrap();
        assert_eq!(relation.kind, "Deployment");
        assert_eq!(relation.name, "test-deployment");
        assert_eq!(relation.namespace, Some("default".to_string()));
    }
}
