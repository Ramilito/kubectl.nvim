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
    pub children_keys: Vec<String>,
    pub leaf_keys: Vec<String>,
    pub key: String,
    pub parent_key: Option<String>,
}

impl TreeNode {
    pub fn new(resource: Resource) -> Self {
        let key = Self::get_resource_key(&resource);
        Self {
            resource,
            children_keys: Vec::new(),
            leaf_keys: Vec::new(),
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
        if !self.children_keys.contains(&child_key) {
            self.children_keys.push(child_key);
        }
    }

    pub fn add_leaf(&mut self, leaf_key: String) {
        if !self.leaf_keys.contains(&leaf_key) {
            self.leaf_keys.push(leaf_key);
        }
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

            let node = self.nodes.get(node_key).unwrap();
            let mut parent_found = false;

            // Check if this node has owners
            if let Some(ref owners) = node.resource.owners {
                if !owners.is_empty() {
                    let owner = &owners[0]; // Use first owner
                    let owner_key = TreeNode::get_resource_key(&Resource {
                        kind: owner.kind.clone(),
                        name: owner.name.clone(),
                        namespace: owner.namespace.clone(),
                        api_version: owner.api_version.clone(),
                        uid: owner.uid.clone(),
                        labels: None,
                        selectors: None,
                        owners: None,
                        relations: None,
                    });

                    if self.nodes.contains_key(&owner_key) {
                        parent_found = true;
                        // Update parent-child relationship
                        if let Some(parent_node) = self.nodes.get_mut(&owner_key) {
                            parent_node.add_child(node_key.clone());
                        }
                        if let Some(child_node) = self.nodes.get_mut(node_key) {
                            child_node.parent_key = Some(owner_key);
                        }
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

        // Second pass: handle selector-based and explicit relationships (leafs)
        let node_keys: Vec<String> = self.nodes.keys().cloned().collect();
        for node_key in node_keys.iter() {
            let node = self.nodes.get(node_key).unwrap().clone();

            // Handle selector-based relationships
            if let Some(ref selectors) = node.resource.selectors {
                for potential_child_key in node_keys.iter() {
                    if potential_child_key == node_key {
                        continue;
                    }

                    if let Some(potential_child) = self.nodes.get(potential_child_key) {
                        if let Some(ref labels) = potential_child.resource.labels {
                            if selectors_match(selectors, labels) {
                                // Add bidirectional leaf relationship
                                if let Some(n) = self.nodes.get_mut(node_key) {
                                    n.add_leaf(potential_child_key.clone());
                                }
                                if let Some(n) = self.nodes.get_mut(potential_child_key) {
                                    n.add_leaf(node_key.clone());
                                }
                            }
                        }
                    }
                }
            }

            // Handle explicit relations
            if let Some(ref relations) = node.resource.relations {
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
                        if let Some(n) = self.nodes.get_mut(node_key) {
                            n.add_leaf(relation_key);
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

        let mut related_nodes = Vec::new();
        let mut visited = std::collections::HashSet::new();

        // Helper to add node if not visited
        let add_node = |key: &str, related: &mut Vec<String>, vis: &mut std::collections::HashSet<String>| {
            if !vis.contains(key) {
                related.push(key.to_string());
                vis.insert(key.to_string());
            }
        };

        // Collect all ancestors (but skip root)
        let mut current_key = Some(node_key.to_string());
        while let Some(ref key) = current_key {
            if let Some(node) = self.nodes.get(key) {
                if key != &self.root.key {
                    add_node(key, &mut related_nodes, &mut visited);
                }
                current_key = node.parent_key.clone();
            } else {
                break;
            }
        }

        // Collect descendants and leafs for all ancestors
        let ancestors = related_nodes.clone();
        for ancestor_key in ancestors.iter() {
            self.collect_descendants(ancestor_key, &mut related_nodes, &mut visited);
        }

        // Finally add the selected node itself and its descendants
        add_node(node_key, &mut related_nodes, &mut visited);
        self.collect_descendants(node_key, &mut related_nodes, &mut visited);
        self.collect_leafs(node_key, &mut related_nodes, &mut visited);

        // Sort related nodes by key
        related_nodes.sort();
        related_nodes
    }

    fn collect_descendants(
        &self,
        node_key: &str,
        related: &mut Vec<String>,
        visited: &mut std::collections::HashSet<String>,
    ) {
        if let Some(node) = self.nodes.get(node_key) {
            for child_key in node.children_keys.iter() {
                if !visited.contains(child_key) {
                    related.push(child_key.clone());
                    visited.insert(child_key.clone());
                    self.collect_leafs(child_key, related, visited);
                    self.collect_descendants(child_key, related, visited);
                }
            }
        }
    }

    fn collect_leafs(
        &self,
        node_key: &str,
        related: &mut Vec<String>,
        visited: &mut std::collections::HashSet<String>,
    ) {
        if let Some(node) = self.nodes.get(node_key) {
            for leaf_key in node.leaf_keys.iter() {
                if !visited.contains(leaf_key) {
                    related.push(leaf_key.clone());
                    visited.insert(leaf_key.clone());
                }
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
