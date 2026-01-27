//! Graph query builder for composable lineage traversals.
//!
//! Provides a fluent API for building complex graph queries over the lineage tree.
//! Replaces duplicated traversal patterns in tree.rs with a single, reusable abstraction.

use super::tree::{EdgeType, Tree};
use petgraph::graph::NodeIndex;
use petgraph::visit::{Dfs, EdgeFiltered, EdgeRef};
use petgraph::Direction;
use std::collections::HashSet;

/// A graph query builder for composable lineage traversals.
///
/// Allows chaining traversal operations to build complex queries:
/// ```ignore
/// GraphQuery::from_key(tree, "deployment/default/app")
///     .ancestors()
///     .descendants()
///     .with_references()
///     .collect_keys()
/// ```
pub struct GraphQuery<'a> {
    /// Reference to the lineage tree
    tree: &'a Tree,
    /// Set of currently selected nodes
    nodes: HashSet<NodeIndex>,
    /// Reference to the root key (to exclude it from results)
    root_key: &'a str,
}

impl<'a> GraphQuery<'a> {
    /// Create a new query starting from a resource key.
    ///
    /// Returns None if the key doesn't exist in the tree.
    pub fn from_key(tree: &'a Tree, key: &str) -> Option<Self> {
        let node_idx = tree.key_to_index.get(key).copied()?;
        let mut nodes = HashSet::new();
        nodes.insert(node_idx);

        Some(Self {
            tree,
            nodes,
            root_key: &tree.root_key,
        })
    }

    /// Add all ancestors of the current nodes (walking up ownership chain).
    ///
    /// Excludes the cluster root node.
    pub fn ancestors(mut self) -> Self {
        let mut new_nodes = HashSet::new();

        // For each node in the current set, walk up the ownership chain
        for &node_idx in &self.nodes {
            let mut current_idx = node_idx;
            loop {
                // Find parent via incoming Owns edge
                let parent_opt = self
                    .tree
                    .graph
                    .edges_directed(current_idx, Direction::Incoming)
                    .find(|edge| *edge.weight() == EdgeType::Owns)
                    .map(|edge| edge.source());

                if let Some(parent_idx) = parent_opt {
                    let parent_key = self.tree.get_key_for_index(parent_idx);
                    if parent_key != self.root_key {
                        new_nodes.insert(parent_idx);
                    }
                    current_idx = parent_idx;
                } else {
                    break;
                }
            }
        }

        // Add ancestors to the nodes set
        self.nodes.extend(new_nodes);
        self
    }

    /// Add all descendants of the current nodes (DFS following Owns edges).
    ///
    /// Excludes the cluster root node.
    pub fn descendants(mut self) -> Self {
        // Create a filtered graph that only includes Owns edges
        let ownership_graph = EdgeFiltered::from_fn(&self.tree.graph, |edge| {
            *edge.weight() == EdgeType::Owns
        });

        // Collect descendants for all current nodes using DFS
        let current_nodes: Vec<NodeIndex> = self.nodes.iter().copied().collect();
        for node_idx in current_nodes {
            let mut dfs = Dfs::new(&ownership_graph, node_idx);
            while let Some(visited_idx) = dfs.next(&ownership_graph) {
                let key = self.tree.get_key_for_index(visited_idx);
                if key != self.root_key {
                    self.nodes.insert(visited_idx);
                }
            }
        }

        self
    }

    /// Add all resources referenced by the current nodes (outgoing References edges).
    ///
    /// Excludes the cluster root node.
    pub fn with_references(mut self) -> Self {
        let mut new_nodes = HashSet::new();

        // Collect all outgoing References targets for all current nodes
        for &node_idx in &self.nodes {
            for edge in self
                .tree
                .graph
                .edges_directed(node_idx, Direction::Outgoing)
            {
                if *edge.weight() == EdgeType::References {
                    let target_idx = edge.target();
                    let target_key = self.tree.get_key_for_index(target_idx);
                    if target_key != self.root_key {
                        new_nodes.insert(target_idx);
                    }
                }
            }
        }

        // Add reference targets to the nodes set
        self.nodes.extend(new_nodes);
        self
    }

    /// Collect the resource keys of all selected nodes.
    ///
    /// Returns a sorted vector of resource keys.
    pub fn collect_keys(self) -> Vec<String> {
        let mut keys: Vec<String> = self
            .nodes
            .iter()
            .map(|&idx| self.tree.get_key_for_index(idx))
            .collect();
        keys.sort();
        keys
    }

    /// Collect the node indices of all selected nodes.
    pub fn collect_nodes(self) -> HashSet<NodeIndex> {
        self.nodes
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lineage::tree::Resource;

    #[test]
    fn test_query_from_key() {
        let root = Resource {
            kind: "cluster".to_string(),
            name: "test".to_string(),
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

        let mut tree = Tree::new(root);

        let deployment = Resource {
            kind: "Deployment".to_string(),
            name: "app".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("apps/v1".to_string()),
            uid: Some("dep-1".to_string()),
            labels: None,
            selectors: None,
            owners: None,
            relations: None,
            is_orphan: false,
            resource_type: None,
            missing_refs: None,
        };
        tree.add_node(deployment);

        // Test valid key
        let query = GraphQuery::from_key(&tree, "deployment/default/app");
        assert!(query.is_some());

        // Test invalid key
        let query = GraphQuery::from_key(&tree, "nonexistent/key");
        assert!(query.is_none());
    }

    #[test]
    fn test_query_collect_nodes() {
        let root = Resource {
            kind: "cluster".to_string(),
            name: "test".to_string(),
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

        let tree = Tree::new(root);

        let query = GraphQuery::from_key(&tree, "cluster/test").unwrap();
        let nodes = query.collect_nodes();

        assert_eq!(nodes.len(), 1);
    }

    #[test]
    fn test_placeholder_methods_return_self() {
        let root = Resource {
            kind: "cluster".to_string(),
            name: "test".to_string(),
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

        let tree = Tree::new(root);

        // Test that chaining works (methods return self)
        let query = GraphQuery::from_key(&tree, "cluster/test")
            .unwrap()
            .ancestors()
            .descendants()
            .with_references();

        assert_eq!(query.nodes.len(), 1);
    }

    #[test]
    fn test_ancestors_traversal() {
        use crate::lineage::tree::RelationRef;

        let root = Resource {
            kind: "cluster".to_string(),
            name: "test".to_string(),
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

        let mut tree = Tree::new(root);

        // Add deployment
        let deployment = Resource {
            kind: "Deployment".to_string(),
            name: "app".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("apps/v1".to_string()),
            uid: Some("dep-1".to_string()),
            labels: None,
            selectors: None,
            owners: None,
            relations: None,
            is_orphan: false,
            resource_type: None,
            missing_refs: None,
        };
        tree.add_node(deployment);

        // Add replicaset owned by deployment
        let replicaset = Resource {
            kind: "ReplicaSet".to_string(),
            name: "app-rs".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("apps/v1".to_string()),
            uid: Some("rs-1".to_string()),
            labels: None,
            selectors: None,
            owners: Some(vec![RelationRef {
                kind: "Deployment".to_string(),
                name: "app".to_string(),
                namespace: Some("default".to_string()),
                api_version: Some("apps/v1".to_string()),
                uid: Some("dep-1".to_string()),
            }]),
            relations: None,
            is_orphan: false,
            resource_type: None,
            missing_refs: None,
        };
        tree.add_node(replicaset);

        // Add pod owned by replicaset
        let pod = Resource {
            kind: "Pod".to_string(),
            name: "app-pod".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("v1".to_string()),
            uid: Some("pod-1".to_string()),
            labels: None,
            selectors: None,
            owners: Some(vec![RelationRef {
                kind: "ReplicaSet".to_string(),
                name: "app-rs".to_string(),
                namespace: Some("default".to_string()),
                api_version: Some("apps/v1".to_string()),
                uid: Some("rs-1".to_string()),
            }]),
            relations: None,
            is_orphan: false,
            resource_type: None,
            missing_refs: None,
        };
        tree.add_node(pod);

        tree.link_nodes();

        // Query ancestors from pod - should get replicaset and deployment (but not root)
        let keys = GraphQuery::from_key(&tree, "pod/default/app-pod")
            .unwrap()
            .ancestors()
            .collect_keys();

        assert_eq!(keys.len(), 3); // pod itself + replicaset + deployment
        assert!(keys.contains(&"deployment/default/app".to_string()));
        assert!(keys.contains(&"replicaset/default/app-rs".to_string()));
        assert!(keys.contains(&"pod/default/app-pod".to_string()));
        assert!(!keys.contains(&"cluster/test".to_string())); // root excluded
    }

    #[test]
    fn test_descendants_traversal() {
        use crate::lineage::tree::RelationRef;

        let root = Resource {
            kind: "cluster".to_string(),
            name: "test".to_string(),
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

        let mut tree = Tree::new(root);

        // Add deployment
        let deployment = Resource {
            kind: "Deployment".to_string(),
            name: "app".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("apps/v1".to_string()),
            uid: Some("dep-1".to_string()),
            labels: None,
            selectors: None,
            owners: None,
            relations: None,
            is_orphan: false,
            resource_type: None,
            missing_refs: None,
        };
        tree.add_node(deployment);

        // Add replicaset owned by deployment
        let replicaset = Resource {
            kind: "ReplicaSet".to_string(),
            name: "app-rs".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("apps/v1".to_string()),
            uid: Some("rs-1".to_string()),
            labels: None,
            selectors: None,
            owners: Some(vec![RelationRef {
                kind: "Deployment".to_string(),
                name: "app".to_string(),
                namespace: Some("default".to_string()),
                api_version: Some("apps/v1".to_string()),
                uid: Some("dep-1".to_string()),
            }]),
            relations: None,
            is_orphan: false,
            resource_type: None,
            missing_refs: None,
        };
        tree.add_node(replicaset);

        // Add pod owned by replicaset
        let pod = Resource {
            kind: "Pod".to_string(),
            name: "app-pod".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("v1".to_string()),
            uid: Some("pod-1".to_string()),
            labels: None,
            selectors: None,
            owners: Some(vec![RelationRef {
                kind: "ReplicaSet".to_string(),
                name: "app-rs".to_string(),
                namespace: Some("default".to_string()),
                api_version: Some("apps/v1".to_string()),
                uid: Some("rs-1".to_string()),
            }]),
            relations: None,
            is_orphan: false,
            resource_type: None,
            missing_refs: None,
        };
        tree.add_node(pod);

        tree.link_nodes();

        // Query descendants from deployment - should get replicaset and pod (but not root)
        let keys = GraphQuery::from_key(&tree, "deployment/default/app")
            .unwrap()
            .descendants()
            .collect_keys();

        assert_eq!(keys.len(), 3); // deployment itself + replicaset + pod
        assert!(keys.contains(&"deployment/default/app".to_string()));
        assert!(keys.contains(&"replicaset/default/app-rs".to_string()));
        assert!(keys.contains(&"pod/default/app-pod".to_string()));
        assert!(!keys.contains(&"cluster/test".to_string())); // root excluded
    }

    #[test]
    fn test_with_references_traversal() {
        use crate::lineage::tree::RelationRef;

        let root = Resource {
            kind: "cluster".to_string(),
            name: "test".to_string(),
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

        let mut tree = Tree::new(root);

        // Add pod that references a ConfigMap
        let pod = Resource {
            kind: "Pod".to_string(),
            name: "app-pod".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("v1".to_string()),
            uid: Some("pod-1".to_string()),
            labels: None,
            selectors: None,
            owners: None,
            relations: Some(vec![RelationRef {
                kind: "ConfigMap".to_string(),
                name: "config".to_string(),
                namespace: Some("default".to_string()),
                api_version: Some("v1".to_string()),
                uid: Some("cm-1".to_string()),
            }]),
            is_orphan: false,
            resource_type: None,
            missing_refs: None,
        };
        tree.add_node(pod);

        // Add ConfigMap
        let configmap = Resource {
            kind: "ConfigMap".to_string(),
            name: "config".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("v1".to_string()),
            uid: Some("cm-1".to_string()),
            labels: None,
            selectors: None,
            owners: None,
            relations: None,
            is_orphan: false,
            resource_type: None,
            missing_refs: None,
        };
        tree.add_node(configmap);

        tree.link_nodes();

        // Query references from pod - should include ConfigMap
        let keys = GraphQuery::from_key(&tree, "pod/default/app-pod")
            .unwrap()
            .with_references()
            .collect_keys();

        assert!(keys.contains(&"pod/default/app-pod".to_string()));
        assert!(keys.contains(&"configmap/default/config".to_string()));
    }

    #[test]
    fn test_chained_traversal() {
        use crate::lineage::tree::RelationRef;

        let root = Resource {
            kind: "cluster".to_string(),
            name: "test".to_string(),
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

        let mut tree = Tree::new(root);

        // Add deployment
        let deployment = Resource {
            kind: "Deployment".to_string(),
            name: "app".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("apps/v1".to_string()),
            uid: Some("dep-1".to_string()),
            labels: None,
            selectors: None,
            owners: None,
            relations: None,
            is_orphan: false,
            resource_type: None,
            missing_refs: None,
        };
        tree.add_node(deployment);

        // Add replicaset owned by deployment
        let replicaset = Resource {
            kind: "ReplicaSet".to_string(),
            name: "app-rs".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("apps/v1".to_string()),
            uid: Some("rs-1".to_string()),
            labels: None,
            selectors: None,
            owners: Some(vec![RelationRef {
                kind: "Deployment".to_string(),
                name: "app".to_string(),
                namespace: Some("default".to_string()),
                api_version: Some("apps/v1".to_string()),
                uid: Some("dep-1".to_string()),
            }]),
            relations: None,
            is_orphan: false,
            resource_type: None,
            missing_refs: None,
        };
        tree.add_node(replicaset);

        // Add pod owned by replicaset, referencing ConfigMap
        let pod = Resource {
            kind: "Pod".to_string(),
            name: "app-pod".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("v1".to_string()),
            uid: Some("pod-1".to_string()),
            labels: None,
            selectors: None,
            owners: Some(vec![RelationRef {
                kind: "ReplicaSet".to_string(),
                name: "app-rs".to_string(),
                namespace: Some("default".to_string()),
                api_version: Some("apps/v1".to_string()),
                uid: Some("rs-1".to_string()),
            }]),
            relations: Some(vec![RelationRef {
                kind: "ConfigMap".to_string(),
                name: "config".to_string(),
                namespace: Some("default".to_string()),
                api_version: Some("v1".to_string()),
                uid: Some("cm-1".to_string()),
            }]),
            is_orphan: false,
            resource_type: None,
            missing_refs: None,
        };
        tree.add_node(pod);

        // Add ConfigMap
        let configmap = Resource {
            kind: "ConfigMap".to_string(),
            name: "config".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("v1".to_string()),
            uid: Some("cm-1".to_string()),
            labels: None,
            selectors: None,
            owners: None,
            relations: None,
            is_orphan: false,
            resource_type: None,
            missing_refs: None,
        };
        tree.add_node(configmap);

        tree.link_nodes();

        // Chain: start from ReplicaSet, get ancestors (Deployment) + descendants (Pod) + references (ConfigMap)
        let keys = GraphQuery::from_key(&tree, "replicaset/default/app-rs")
            .unwrap()
            .ancestors() // Should add Deployment
            .descendants() // Should add Pod
            .with_references() // Should add ConfigMap (from Pod)
            .collect_keys();

        assert!(keys.contains(&"deployment/default/app".to_string()));
        assert!(keys.contains(&"replicaset/default/app-rs".to_string()));
        assert!(keys.contains(&"pod/default/app-pod".to_string()));
        assert!(keys.contains(&"configmap/default/config".to_string()));
        assert!(!keys.contains(&"cluster/test".to_string())); // root excluded
    }
}
