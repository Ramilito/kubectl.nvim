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

    // Convert JSON resources to our Resource struct
    let mut parsed_resources: Vec<Resource> = Vec::new();
    for resource_value in resources {
        if let Some(resource) = parse_resource(&resource_value) {
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
fn parse_resource(value: &Value) -> Option<Resource> {
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

    // Parse owners
    let owners = value
        .get("owners")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(parse_relation_ref)
                .collect()
        });

    // Parse explicit relations
    let relations = value
        .get("relations")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(parse_relation_ref)
                .collect()
        });

    Some(Resource {
        kind,
        name,
        namespace,
        api_version,
        uid,
        labels,
        selectors,
        owners,
        relations,
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

        let resource = parse_resource(&json).unwrap();
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
