use k8s_openapi::serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Represents a resource in the lineage tree
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Resource {
    pub kind: String,
    pub name: String,
    #[serde(rename = "ns")]
    pub namespace: Option<String>,
    #[serde(rename = "apiVersion")]
    pub api_version: Option<String>,
    pub uid: Option<String>,
    pub labels: Option<HashMap<String, String>>,
    pub selectors: Option<HashMap<String, String>>,
    pub owners: Option<Vec<RelationRef>>,
    pub relations: Option<Vec<RelationRef>>,
}

/// Reference to a related resource
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RelationRef {
    pub kind: String,
    pub name: String,
    #[serde(rename = "ns")]
    pub namespace: Option<String>,
    #[serde(rename = "apiVersion")]
    pub api_version: Option<String>,
    pub uid: Option<String>,
}

/// A node in the lineage tree
#[derive(Debug, Clone)]
pub struct TreeNode {
    pub resource: Resource,
    pub children_keys: std::collections::HashSet<String>,
    pub leaf_keys: std::collections::HashSet<String>,
    pub key: String,
    pub parent_key: Option<String>,
}

impl TreeNode {
    pub fn new(resource: Resource) -> Self {
        let key = Self::get_resource_key(&resource);
        Self {
            resource,
            children_keys: std::collections::HashSet::new(),
            leaf_keys: std::collections::HashSet::new(),
            key,
            parent_key: None,
        }
    }

    /// Generate a unique key for a resource
    pub fn get_resource_key(resource: &Resource) -> String {
        if let Some(ref ns) = resource.namespace {
            return format!("{}/{}/{}", resource.kind, ns, resource.name).to_lowercase();
        }
        format!("{}/{}", resource.kind, resource.name).to_lowercase()
    }

    pub fn add_child(&mut self, child_key: String) {
        self.children_keys.insert(child_key);
    }

    pub fn add_leaf(&mut self, leaf_key: String) {
        self.leaf_keys.insert(leaf_key);
    }
}

/// The lineage tree structure
#[derive(Debug, Clone)]
pub struct Tree {
    pub root: TreeNode,
    pub nodes: HashMap<String, TreeNode>,
}

impl Tree {
    pub fn new(root_resource: Resource) -> Self {
        let root = TreeNode::new(root_resource);
        let root_key = root.key.clone();
        let mut nodes = HashMap::new();
        nodes.insert(root_key, root.clone());

        Self { root, nodes }
    }

    pub fn add_node(&mut self, resource: Resource) {
        let node = TreeNode::new(resource);
        let key = node.key.clone();

        // Skip if node already exists
        if self.nodes.contains_key(&key) {
            return;
        }

        self.nodes.insert(key, node);
    }

    pub fn link_nodes(&mut self) {
        // Collect all node keys to avoid borrow checker issues
        let node_keys: Vec<String> = self.nodes.keys().cloned().collect();

        // First pass: handle ownership relationships
        for node_key in node_keys.iter() {
            if node_key == &self.root.key {
                continue;
            }

            // Extract all needed data while borrowing immutably
            let owner_key_opt = {
                let node = self.nodes.get(node_key).unwrap();
                node.resource.owners.as_ref().and_then(|owners| {
                    if !owners.is_empty() {
                        let owner = &owners[0];
                        Some(TreeNode::get_resource_key(&Resource {
                            kind: owner.kind.clone(),
                            name: owner.name.clone(),
                            namespace: owner.namespace.clone(),
                            api_version: owner.api_version.clone(),
                            uid: owner.uid.clone(),
                            labels: None,
                            selectors: None,
                            owners: None,
                            relations: None,
                        }))
                    } else {
                        None
                    }
                })
            };

            let mut parent_found = false;

            // Now perform mutable operations with extracted data
            if let Some(owner_key) = owner_key_opt {
                if self.nodes.contains_key(&owner_key) {
                    parent_found = true;
                    // Update parent-child relationship
                    if let Some(parent_node) = self.nodes.get_mut(&owner_key) {
                        parent_node.add_child(node_key.clone());
                    }
                    if let Some(child_node) = self.nodes.get_mut(node_key) {
                        child_node.parent_key = Some(owner_key.clone());
                    }
                }
            }

            // If no parent found, attach to root
            if !parent_found {
                if let Some(root_node) = self.nodes.get_mut(&self.root.key) {
                    root_node.add_child(node_key.clone());
                }
                if let Some(node) = self.nodes.get_mut(node_key) {
                    node.parent_key = Some(self.root.key.clone());
                }
            }
        }

        // Build an index of nodes by labels to avoid O(n²) selector matching
        // Clone the minimal data needed (keys and labels only, not entire nodes)
        let mut nodes_with_labels: Vec<(String, HashMap<String, String>)> = Vec::new();
        for node_key in node_keys.iter() {
            if let Some(node) = self.nodes.get(node_key) {
                if let Some(ref labels) = node.resource.labels {
                    nodes_with_labels.push((node_key.clone(), labels.clone()));
                }
            }
        }

        // Second pass: handle selector-based and explicit relationships (leafs)
        for node_key in node_keys.iter() {
            // Extract selectors and relations without cloning the entire node
            let (selectors_opt, relations_opt) = {
                let node = self.nodes.get(node_key).unwrap();
                (node.resource.selectors.clone(), node.resource.relations.clone())
            };

            // Handle selector-based relationships
            if let Some(ref selectors) = selectors_opt {
                // Collect matching child keys first
                let mut matching_children = Vec::new();
                for (potential_child_key, labels) in nodes_with_labels.iter() {
                    if potential_child_key == node_key {
                        continue;
                    }

                    if selectors_match(selectors, labels) {
                        matching_children.push(potential_child_key.clone());
                    }
                }

                // Now perform mutable operations
                for potential_child_key in matching_children {
                    // Add bidirectional leaf relationship
                    if let Some(n) = self.nodes.get_mut(node_key) {
                        n.add_leaf(potential_child_key.clone());
                    }
                    if let Some(n) = self.nodes.get_mut(&potential_child_key) {
                        n.add_leaf(node_key.clone());
                    }
                }
            }

            // Handle explicit relations
            if let Some(ref relations) = relations_opt {
                // Collect relation keys and their types first
                let mut relation_updates = Vec::new();
                for relation in relations {
                    let relation_key = TreeNode::get_resource_key(&Resource {
                        kind: relation.kind.clone(),
                        name: relation.name.clone(),
                        namespace: relation.namespace.clone(),
                        api_version: relation.api_version.clone(),
                        uid: relation.uid.clone(),
                        labels: None,
                        selectors: None,
                        owners: None,
                        relations: None,
                    });

                    if self.nodes.contains_key(&relation_key) {
                        let is_config_or_secret = relation.kind == "ConfigMap" || relation.kind == "Secret";
                        relation_updates.push((relation_key, is_config_or_secret));
                    }
                }

                // Now perform mutable operations
                for (relation_key, is_config_or_secret) in relation_updates {
                    // Add forward relationship (node -> relation)
                    if let Some(n) = self.nodes.get_mut(node_key) {
                        n.add_leaf(relation_key.clone());
                    }

                    // Add reverse relationship for ConfigMap/Secret
                    // When viewing a ConfigMap or Secret, show which Pods consume it
                    if is_config_or_secret {
                        if let Some(n) = self.nodes.get_mut(&relation_key) {
                            n.add_leaf(node_key.clone());
                        }
                    }
                }
            }
        }
    }

    /// Get all related nodes for a given node key
    pub fn get_related_items(&self, node_key: &str) -> Vec<String> {
        if !self.nodes.contains_key(node_key) {
            return Vec::new();
        }

        let mut visited = std::collections::HashSet::new();

        // Collect all ancestors (but skip root)
        let mut current_key = Some(node_key.to_string());
        while let Some(ref key) = current_key {
            if let Some(node) = self.nodes.get(key) {
                if key != &self.root.key {
                    visited.insert(key.to_string());
                }
                current_key = node.parent_key.clone();
            } else {
                break;
            }
        }

        // Collect descendants and leafs for all ancestors
        // Use a small Vec to hold ancestor keys instead of cloning related_nodes
        let ancestors: Vec<String> = visited.iter().cloned().collect();
        for ancestor_key in ancestors.iter() {
            self.collect_descendants(ancestor_key.as_str(), &mut visited);
        }

        // Finally add the selected node itself and its descendants
        visited.insert(node_key.to_string());
        self.collect_descendants(node_key, &mut visited);
        self.collect_leafs(node_key, &mut visited);

        // Convert HashSet to sorted Vec
        let mut related_nodes: Vec<String> = visited.into_iter().collect();
        related_nodes.sort();
        related_nodes
    }

    fn collect_descendants(
        &self,
        node_key: &str,
        visited: &mut std::collections::HashSet<String>,
    ) {
        if let Some(node) = self.nodes.get(node_key) {
            for child_key in node.children_keys.iter() {
                if visited.insert(child_key.clone()) {
                    self.collect_leafs(child_key, visited);
                    self.collect_descendants(child_key, visited);
                }
            }
        }
    }

    fn collect_leafs(
        &self,
        node_key: &str,
        visited: &mut std::collections::HashSet<String>,
    ) {
        if let Some(node) = self.nodes.get(node_key) {
            for leaf_key in node.leaf_keys.iter() {
                visited.insert(leaf_key.clone());
            }
        }
    }
}

/// Check if selectors match labels
fn selectors_match(selectors: &HashMap<String, String>, labels: &HashMap<String, String>) -> bool {
    selectors
        .iter()
        .all(|(key, value)| labels.get(key).map(|v| v == value).unwrap_or(false))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_resource_key_with_namespace() {
        let resource = Resource {
            kind: "Pod".to_string(),
            name: "test-pod".to_string(),
            namespace: Some("default".to_string()),
            api_version: None,
            uid: None,
            labels: None,
            selectors: None,
            owners: None,
            relations: None,
        };

        let key = TreeNode::get_resource_key(&resource);
        assert_eq!(key, "pod/default/test-pod");
    }

    #[test]
    fn test_resource_key_without_namespace() {
        let resource = Resource {
            kind: "Node".to_string(),
            name: "test-node".to_string(),
            namespace: None,
            api_version: None,
            uid: None,
            labels: None,
            selectors: None,
            owners: None,
            relations: None,
        };

        let key = TreeNode::get_resource_key(&resource);
        assert_eq!(key, "node/test-node");
    }

    #[test]
    fn test_selectors_match() {
        let mut selectors = HashMap::new();
        selectors.insert("app".to_string(), "nginx".to_string());

        let mut labels = HashMap::new();
        labels.insert("app".to_string(), "nginx".to_string());
        labels.insert("version".to_string(), "1.0".to_string());

        assert!(selectors_match(&selectors, &labels));
    }

    #[test]
    fn test_selectors_no_match() {
        let mut selectors = HashMap::new();
        selectors.insert("app".to_string(), "nginx".to_string());

        let mut labels = HashMap::new();
        labels.insert("app".to_string(), "apache".to_string());

        assert!(!selectors_match(&selectors, &labels));
    }
}
