//! Resource lineage tree using petgraph for efficient graph operations.
//!
//! This module implements a directed graph-based lineage tree for Kubernetes resources.
//! It uses petgraph's DiGraph with two edge types:
//! - `EdgeType::Owns`: Represents ownership relationships (parent-child via ownerReferences)
//! - `EdgeType::References`: Represents reference relationships (selectors, ConfigMaps, Secrets)

use k8s_openapi::serde::{Deserialize, Serialize};
use petgraph::algo::is_cyclic_directed;
use petgraph::graph::{DiGraph, NodeIndex};
use petgraph::visit::{Dfs, EdgeFiltered, EdgeRef};
use petgraph::Direction;
use std::collections::{HashMap, HashSet};

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

impl Resource {
    /// Generate a unique key for a resource
    pub fn get_resource_key(&self) -> String {
        if let Some(ref ns) = self.namespace {
            return format!("{}/{}/{}", self.kind, ns, self.name).to_lowercase();
        }
        format!("{}/{}", self.kind, self.name).to_lowercase()
    }
}

/// Edge types in the lineage graph
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EdgeType {
    /// Owner-owned relationship (parent-child)
    Owns,
    /// Reference relationship (selector-based or explicit)
    References,
}

/// The lineage tree structure using petgraph
#[derive(Debug, Clone)]
pub struct Tree {
    /// The underlying directed graph
    pub graph: DiGraph<Resource, EdgeType>,
    /// Root node in the graph
    root_index: NodeIndex,
    /// Map from resource keys to node indices
    pub key_to_index: HashMap<String, NodeIndex>,
    /// Root resource key
    pub root_key: String,
}

impl Tree {
    #[tracing::instrument(skip(root_resource), fields(root_kind = %root_resource.kind, root_name = %root_resource.name))]
    pub fn new(root_resource: Resource) -> Self {
        let mut graph = DiGraph::new();
        let root_key = Resource::get_resource_key(&root_resource);
        let root_index = graph.add_node(root_resource);

        let mut key_to_index = HashMap::new();
        key_to_index.insert(root_key.clone(), root_index);

        Self {
            graph,
            root_index,
            key_to_index,
            root_key,
        }
    }

    pub fn add_node(&mut self, resource: Resource) {
        let key = Resource::get_resource_key(&resource);

        // Skip if node already exists
        if self.key_to_index.contains_key(&key) {
            return;
        }

        let node_index = self.graph.add_node(resource);
        self.key_to_index.insert(key, node_index);
    }

    #[tracing::instrument(skip(self), fields(node_count = self.key_to_index.len()))]
    pub fn link_nodes(&mut self) {
        // Collect all node keys to avoid borrow checker issues
        let node_keys: Vec<String> = self.key_to_index.keys().cloned().collect();

        // First pass: handle ownership relationships
        for node_key in node_keys.iter() {
            if node_key == &self.root_key {
                continue;
            }

            // Get the node index
            let node_idx = self.key_to_index[node_key];
            let resource = &self.graph[node_idx];

            // Extract owner information
            let owner_key_opt = resource.owners.as_ref().and_then(|owners| {
                if !owners.is_empty() {
                    let owner = &owners[0];
                    Some(Resource {
                        kind: owner.kind.clone(),
                        name: owner.name.clone(),
                        namespace: owner.namespace.clone(),
                        api_version: owner.api_version.clone(),
                        uid: owner.uid.clone(),
                        labels: None,
                        selectors: None,
                        owners: None,
                        relations: None,
                    }.get_resource_key())
                } else {
                    None
                }
            });

            let mut parent_found = false;

            // Link to owner if it exists
            if let Some(owner_key) = owner_key_opt {
                if let Some(&parent_idx) = self.key_to_index.get(&owner_key) {
                    parent_found = true;
                    // Add ownership edge from parent to child
                    self.graph.add_edge(parent_idx, node_idx, EdgeType::Owns);
                }
            }

            // If no parent found, attach to root
            if !parent_found {
                self.graph
                    .add_edge(self.root_index, node_idx, EdgeType::Owns);
            }
        }

        // Build an index of nodes by labels to avoid O(n²) selector matching
        let mut nodes_with_labels: Vec<(String, NodeIndex, HashMap<String, String>)> = Vec::with_capacity(node_keys.len() / 2);

        for node_key in node_keys.iter() {
            if let Some(&idx) = self.key_to_index.get(node_key) {
                if let Some(ref labels) = self.graph[idx].labels {
                    nodes_with_labels.push((node_key.clone(), idx, labels.clone()));
                }
            }
        }

        // Second pass: handle selector-based and explicit relationships (leafs)
        for node_key in node_keys.iter() {
            let node_idx = self.key_to_index[node_key];
            let resource = &self.graph[node_idx];

            // Clone the data we need to avoid borrow conflicts
            let selectors_opt = resource.selectors.clone();
            let relations_opt = resource.relations.clone();

            // Handle selector-based relationships
            if let Some(ref selectors) = selectors_opt {
                let matching_children: Vec<(String, NodeIndex)> = nodes_with_labels
                    .iter()
                    .filter(|(potential_child_key, _, labels)| {
                        potential_child_key != node_key && selectors_match(selectors, labels)
                    })
                    .map(|(key, idx, _)| (key.clone(), *idx))
                    .collect();

                for (_potential_child_key, child_idx) in matching_children {
                    // Add bidirectional reference edges
                    self.graph
                        .add_edge(node_idx, child_idx, EdgeType::References);
                    self.graph
                        .add_edge(child_idx, node_idx, EdgeType::References);
                }
            }

            // Handle explicit relations
            if let Some(ref relations) = relations_opt {
                let mut relation_updates = Vec::new();
                for relation in relations {
                    let relation_key = Resource {
                        kind: relation.kind.clone(),
                        name: relation.name.clone(),
                        namespace: relation.namespace.clone(),
                        api_version: relation.api_version.clone(),
                        uid: relation.uid.clone(),
                        labels: None,
                        selectors: None,
                        owners: None,
                        relations: None,
                    }.get_resource_key();

                    if let Some(&relation_idx) = self.key_to_index.get(&relation_key) {
                        let is_config_or_secret =
                            relation.kind == "ConfigMap" || relation.kind == "Secret";
                        relation_updates.push((relation_idx, is_config_or_secret));
                    }
                }

                for (relation_idx, is_config_or_secret) in relation_updates {
                    // Add forward reference edge (node -> relation)
                    self.graph
                        .add_edge(node_idx, relation_idx, EdgeType::References);

                    // Add reverse relationship for ConfigMap/Secret
                    if is_config_or_secret {
                        self.graph
                            .add_edge(relation_idx, node_idx, EdgeType::References);
                    }
                }
            }
        }

        // Validate ownership DAG in debug builds only
        #[cfg(debug_assertions)]
        self.validate_ownership_dag();
    }

    /// Validate that ownership relationships form a DAG (no cycles)
    /// This is only called in debug builds to catch relationship bugs early
    #[cfg(debug_assertions)]
    fn validate_ownership_dag(&self) {
        // Create a filtered view of the graph with only Owns edges
        let ownership_graph = EdgeFiltered::from_fn(&self.graph, |edge| {
            *edge.weight() == EdgeType::Owns
        });

        if is_cyclic_directed(&ownership_graph) {
            tracing::error!("Ownership graph contains cycles!");
            panic!("Ownership relationships must form a DAG (Directed Acyclic Graph)");
        }
    }

    /// Get all related nodes for a given node key
    #[tracing::instrument(skip(self), fields(node_key = %node_key))]
    pub fn get_related_items(&self, node_key: &str) -> Vec<String> {
        if !self.key_to_index.contains_key(node_key) {
            return Vec::new();
        }

        let node_idx = self.key_to_index[node_key];
        let mut visited = HashSet::with_capacity(self.key_to_index.len() / 4);

        // Collect all ancestors (but skip root)
        let mut current_idx = node_idx;
        loop {
            // Find parent via Owns edge
            let parent_opt = self
                .graph
                .edges_directed(current_idx, Direction::Incoming)
                .find(|edge| *edge.weight() == EdgeType::Owns)
                .map(|edge| edge.source());

            if let Some(parent_idx) = parent_opt {
                // Get the parent key
                let parent_key = self.get_key_for_index(parent_idx);
                if parent_key != self.root_key {
                    visited.insert(parent_key.clone());
                }
                current_idx = parent_idx;
            } else {
                break;
            }
        }

        // Collect descendants for all ancestors using DFS on ownership edges
        let ancestors: Vec<NodeIndex> = visited
            .iter()
            .filter_map(|key| self.key_to_index.get(key).copied())
            .collect();

        let ownership_graph = EdgeFiltered::from_fn(&self.graph, |edge| {
            *edge.weight() == EdgeType::Owns
        });

        for ancestor_idx in ancestors {
            let mut dfs = Dfs::new(&ownership_graph, ancestor_idx);
            while let Some(visited_idx) = dfs.next(&ownership_graph) {
                let key = self.get_key_for_index(visited_idx);
                if key != self.root_key {
                    visited.insert(key);
                }
            }
        }

        // Add the selected node itself and its descendants using DFS
        visited.insert(node_key.to_string());
        let mut dfs = Dfs::new(&ownership_graph, node_idx);
        while let Some(visited_idx) = dfs.next(&ownership_graph) {
            let key = self.get_key_for_index(visited_idx);
            if key != self.root_key {
                visited.insert(key);
            }
        }

        // Collect all reference relationships for all visited nodes
        let visited_indices: Vec<NodeIndex> = visited
            .iter()
            .filter_map(|key| self.key_to_index.get(key).copied())
            .collect();

        for idx in visited_indices {
            for edge in self.graph.edges_directed(idx, Direction::Outgoing) {
                if *edge.weight() == EdgeType::References {
                    let leaf_key = self.get_key_for_index(edge.target());
                    visited.insert(leaf_key);
                }
            }
        }

        // Convert HashSet to sorted Vec
        let mut related_nodes: Vec<String> = visited.into_iter().collect();
        related_nodes.sort();
        related_nodes
    }

    /// Helper to get the key for a given node index
    fn get_key_for_index(&self, idx: NodeIndex) -> String {
        self.graph[idx].get_resource_key()
    }

    /// Get all children keys (Owns edges outgoing) for a node
    pub fn get_children_keys(&self, idx: NodeIndex) -> Vec<String> {
        self.graph
            .edges_directed(idx, Direction::Outgoing)
            .filter(|e| *e.weight() == EdgeType::Owns)
            .map(|e| self.get_key_for_index(e.target()))
            .collect()
    }

    /// Get all leaf keys (References edges outgoing) for a node
    pub fn get_leaf_keys(&self, idx: NodeIndex) -> Vec<String> {
        self.graph
            .edges_directed(idx, Direction::Outgoing)
            .filter(|e| *e.weight() == EdgeType::References)
            .map(|e| self.get_key_for_index(e.target()))
            .collect()
    }

    /// Get parent key (Owns edge incoming) for a node
    pub fn get_parent_key(&self, idx: NodeIndex) -> Option<String> {
        self.graph
            .edges_directed(idx, Direction::Incoming)
            .find(|e| *e.weight() == EdgeType::Owns)
            .map(|e| self.get_key_for_index(e.source()))
    }

    /// Compute impact analysis for a resource
    /// Returns all resources that depend on (reference) this resource
    /// Algorithm: BFS following incoming edges (who depends on THIS resource?)
    #[tracing::instrument(skip(self), fields(resource_key = %resource_key))]
    pub fn compute_impact(&self, resource_key: &str) -> Vec<(String, String)> {
        // Find the node index for the given key
        let node_idx = match self.key_to_index.get(resource_key) {
            Some(&idx) => idx,
            None => return Vec::new(),
        };

        let mut impacted = Vec::new();
        let mut visited = HashSet::new();
        let mut queue = std::collections::VecDeque::new();

        // Start BFS from the target node
        queue.push_back(node_idx);
        visited.insert(node_idx);

        while let Some(current_idx) = queue.pop_front() {
            // Get all incoming edges (who depends on current node?)
            for edge in self.graph.edges_directed(current_idx, Direction::Incoming) {
                let source_idx = edge.source();
                let source_key = self.get_key_for_index(source_idx);

                // Skip the root cluster node
                if source_key == self.root_key {
                    continue;
                }

                // Only process if not visited
                if !visited.contains(&source_idx) {
                    visited.insert(source_idx);
                    queue.push_back(source_idx);

                    // Determine edge type
                    let edge_type = match edge.weight() {
                        EdgeType::Owns => "owns",
                        EdgeType::References => "references",
                    };

                    impacted.push((source_key, edge_type.to_string()));
                }
            }
        }

        // Sort for consistent output
        impacted.sort_by(|a, b| a.0.cmp(&b.0));
        impacted
    }

    /// Extract subgraph nodes and edges for a given resource key
    /// Returns tuple of (node_indices, edge_indices) that form the subgraph
    /// Algorithm: Collect all ancestors via ownership, descendants via ownership+references
    #[tracing::instrument(skip(self), fields(resource_key = %resource_key))]
    pub fn extract_subgraph(&self, resource_key: &str) -> (HashSet<NodeIndex>, HashSet<usize>) {
        let mut subgraph_nodes = HashSet::new();
        let mut subgraph_edges = HashSet::new();

        // Find the starting node
        let start_idx = match self.key_to_index.get(resource_key) {
            Some(&idx) => idx,
            None => return (subgraph_nodes, subgraph_edges),
        };

        subgraph_nodes.insert(start_idx);

        // Collect all ancestors (following ownership up to root)
        let mut current_idx = start_idx;
        loop {
            let parent_opt = self
                .graph
                .edges_directed(current_idx, Direction::Incoming)
                .find(|edge| *edge.weight() == EdgeType::Owns)
                .map(|edge| edge.source());

            if let Some(parent_idx) = parent_opt {
                // Don't include the cluster root in the subgraph
                if parent_idx != self.root_index {
                    subgraph_nodes.insert(parent_idx);
                }
                current_idx = parent_idx;
            } else {
                break;
            }
        }

        // Collect all descendants using DFS on full graph (both edge types)
        let mut dfs = Dfs::new(&self.graph, start_idx);
        while let Some(visited_idx) = dfs.next(&self.graph) {
            if visited_idx != self.root_index {
                subgraph_nodes.insert(visited_idx);
            }
        }

        // Collect edges that connect nodes within the subgraph
        for edge in self.graph.edge_references() {
            let source = edge.source();
            let target = edge.target();

            if subgraph_nodes.contains(&source) && subgraph_nodes.contains(&target) {
                subgraph_edges.insert(edge.id().index());
            }
        }

        (subgraph_nodes, subgraph_edges)
    }

    /// Export a subgraph centered on a resource to Graphviz DOT format
    /// Returns a string containing the DOT representation of the subgraph
    pub fn export_subgraph_dot(&self, resource_key: &str) -> String {
        let (subgraph_nodes, subgraph_edges) = self.extract_subgraph(resource_key);

        let mut output = String::from("digraph lineage_subgraph {\n");
        output.push_str("    rankdir=TB;\n");
        output.push_str("    node [fontname=\"Arial\"];\n");
        output.push_str("    edge [fontname=\"Arial\"];\n\n");

        // Add nodes with styling
        for idx in subgraph_nodes.iter() {
            let resource = &self.graph[*idx];
            let node_id = format!("N{}", idx.index());

            let shape = if resource.kind == "ConfigMap" || resource.kind == "Secret" {
                "shape=note style=filled fillcolor=lightyellow"
            } else {
                "shape=ellipse"
            };

            let label = if let Some(ref ns) = resource.namespace {
                format!("{}\\n{}\\n({})", resource.kind, resource.name, ns)
            } else {
                format!("{}\\n{}", resource.kind, resource.name)
            };

            output.push_str(&format!("    {} [label=\"{}\" {}];\n", node_id, label, shape));
        }

        output.push('\n');

        // Add edges with styling (only edges in the subgraph)
        for edge_idx in subgraph_edges.iter() {
            if let Some(edge) = self.graph.edge_references().find(|e| e.id().index() == *edge_idx) {
                let source_id = format!("N{}", edge.source().index());
                let target_id = format!("N{}", edge.target().index());

                let style = match edge.weight() {
                    EdgeType::Owns => "color=blue style=solid",
                    EdgeType::References => "color=green style=dashed",
                };

                output.push_str(&format!("    {} -> {} [{}];\n", source_id, target_id, style));
            }
        }

        output.push_str("}\n");
        output
    }

    /// Export the lineage graph to Graphviz DOT format
    /// Returns a string containing the DOT representation
    pub fn export_dot(&self) -> String {
        let mut output = String::from("digraph lineage {\n");
        output.push_str("    rankdir=TB;\n");
        output.push_str("    node [fontname=\"Arial\"];\n");
        output.push_str("    edge [fontname=\"Arial\"];\n\n");

        // Add nodes with styling
        for idx in self.graph.node_indices() {
            let resource = &self.graph[idx];
            let node_id = format!("N{}", idx.index());

            let shape = if idx == self.root_index {
                "shape=box style=filled fillcolor=lightgray"
            } else if resource.kind == "ConfigMap" || resource.kind == "Secret" {
                "shape=note style=filled fillcolor=lightyellow"
            } else {
                "shape=ellipse"
            };

            let label = if let Some(ref ns) = resource.namespace {
                format!("{}\\n{}\\n({})", resource.kind, resource.name, ns)
            } else {
                format!("{}\\n{}", resource.kind, resource.name)
            };

            output.push_str(&format!("    {} [label=\"{}\" {}];\n", node_id, label, shape));
        }

        output.push('\n');

        // Add edges with styling
        for edge in self.graph.edge_references() {
            let source_id = format!("N{}", edge.source().index());
            let target_id = format!("N{}", edge.target().index());

            let style = match edge.weight() {
                EdgeType::Owns => "color=blue style=solid",
                EdgeType::References => "color=green style=dashed",
            };

            output.push_str(&format!("    {} -> {} [{}];\n", source_id, target_id, style));
        }

        output.push_str("}\n");
        output
    }

    /// Find orphan resources in the tree
    /// An orphan is a resource with no owners and no incoming edges from non-root nodes
    /// Returns a list of resource keys that are orphans
    pub fn find_orphans(&self) -> Vec<String> {
        // Well-known cluster-scoped resources that are expected to have no owners
        const CLUSTER_SCOPED_KINDS: &[&str] = &[
            "namespace",
            "node",
            "clusterrole",
            "clusterrolebinding",
            "persistentvolume",
            "storageclass",
            "customresourcedefinition",
            "apiservice",
            "mutatingwebhookconfiguration",
            "validatingwebhookconfiguration",
            "priorityclass",
            "runtimeclass",
            "volumeattachment",
            "csidriver",
            "csinode",
            "ingressclass",
        ];

        let mut orphans = Vec::new();

        for (key, &idx) in self.key_to_index.iter() {
            // Skip the cluster root node
            if key == &self.root_key {
                continue;
            }

            let resource = &self.graph[idx];

            // Skip well-known cluster-scoped resources
            if CLUSTER_SCOPED_KINDS.contains(&resource.kind.to_lowercase().as_str()) {
                continue;
            }

            // Check if the resource has owners
            let has_owners = resource
                .owners
                .as_ref()
                .map(|owners| !owners.is_empty())
                .unwrap_or(false);

            // If it has owners, it's not an orphan
            if has_owners {
                continue;
            }

            // Check if the resource has incoming edges from non-root nodes
            let has_non_root_incoming_edges = self
                .graph
                .edges_directed(idx, Direction::Incoming)
                .any(|edge| edge.source() != self.root_index);

            // An orphan has no owners and no incoming edges from non-root nodes
            if !has_non_root_incoming_edges {
                orphans.push(key.clone());
            }
        }

        // Sort for consistent output
        orphans.sort();
        orphans
    }

    /// Export a subgraph centered on a resource to Mermaid diagram format
    /// Returns a string containing the Mermaid representation of the subgraph
    pub fn export_subgraph_mermaid(&self, resource_key: &str) -> String {
        let (subgraph_nodes, subgraph_edges) = self.extract_subgraph(resource_key);

        let mut output = String::from("graph TD\n");

        // Create node definitions with sanitized IDs
        let mut node_ids: HashMap<NodeIndex, String> = HashMap::new();
        for idx in subgraph_nodes.iter() {
            let resource = &self.graph[*idx];
            let node_id = format!("N{}", idx.index());
            node_ids.insert(*idx, node_id.clone());

            let label = if let Some(ref ns) = resource.namespace {
                format!("{}\\n{}\\n({})", resource.kind, resource.name, ns)
            } else {
                format!("{}\\n{}", resource.kind, resource.name)
            };

            let shape = if resource.kind == "ConfigMap" || resource.kind == "Secret" {
                format!("    {}[\"{}\"]:::config\n", node_id, label)
            } else {
                format!("    {}[\"{}\"]\n", node_id, label)
            };

            output.push_str(&shape);
        }

        output.push('\n');

        // Create edge definitions (only edges in the subgraph)
        for edge_idx in subgraph_edges.iter() {
            if let Some(edge) = self.graph.edge_references().find(|e| e.id().index() == *edge_idx) {
                let source_id = &node_ids[&edge.source()];
                let target_id = &node_ids[&edge.target()];

                let edge_def = match edge.weight() {
                    EdgeType::Owns => format!("    {} --> {}\n", source_id, target_id),
                    EdgeType::References => format!("    {} -.-> {}\n", source_id, target_id),
                };

                output.push_str(&edge_def);
            }
        }

        // Add style classes
        output.push_str("\n    classDef config fill:#ffffcc,stroke:#333,stroke-width:2px\n");

        output
    }

    /// Export the lineage graph to Mermaid diagram format
    /// Returns a string containing the Mermaid representation
    pub fn to_mermaid(&self) -> String {
        let mut output = String::from("graph TD\n");

        // Create node definitions with sanitized IDs
        let mut node_ids: HashMap<NodeIndex, String> = HashMap::new();
        for idx in self.graph.node_indices() {
            let resource = &self.graph[idx];
            let node_id = format!("N{}", idx.index());
            node_ids.insert(idx, node_id.clone());

            let label = if let Some(ref ns) = resource.namespace {
                format!("{}\\n{}\\n({})", resource.kind, resource.name, ns)
            } else {
                format!("{}\\n{}", resource.kind, resource.name)
            };

            let shape = if idx == self.root_index {
                format!("    {}[[\"{}\"]]\n", node_id, label)
            } else if resource.kind == "ConfigMap" || resource.kind == "Secret" {
                format!("    {}[\"{}\"]:::config\n", node_id, label)
            } else {
                format!("    {}[\"{}\"]\n", node_id, label)
            };

            output.push_str(&shape);
        }

        output.push('\n');

        // Create edge definitions
        for edge in self.graph.edge_references() {
            let source_id = &node_ids[&edge.source()];
            let target_id = &node_ids[&edge.target()];

            let edge_def = match edge.weight() {
                EdgeType::Owns => format!("    {} --> {}\n", source_id, target_id),
                EdgeType::References => format!("    {} -.-> {}\n", source_id, target_id),
            };

            output.push_str(&edge_def);
        }

        // Add style classes
        output.push_str("\n    classDef config fill:#ffffcc,stroke:#333,stroke-width:2px\n");

        output
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

        let key = resource.get_resource_key();
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

        let key = resource.get_resource_key();
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

    #[test]
    fn test_tree_creation_and_linking() {
        let root = Resource {
            kind: "cluster".to_string(),
            name: "test-cluster".to_string(),
            namespace: None,
            api_version: None,
            uid: None,
            labels: None,
            selectors: None,
            owners: None,
            relations: None,
        };

        let mut tree = Tree::new(root);

        // Add a deployment
        let deployment = Resource {
            kind: "Deployment".to_string(),
            name: "nginx-deployment".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("apps/v1".to_string()),
            uid: Some("dep-123".to_string()),
            labels: None,
            selectors: Some({
                let mut map = HashMap::new();
                map.insert("app".to_string(), "nginx".to_string());
                map
            }),
            owners: None,
            relations: None,
        };

        tree.add_node(deployment);

        // Add a pod owned by deployment
        let pod = Resource {
            kind: "Pod".to_string(),
            name: "nginx-pod-1".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("v1".to_string()),
            uid: Some("pod-123".to_string()),
            labels: Some({
                let mut map = HashMap::new();
                map.insert("app".to_string(), "nginx".to_string());
                map
            }),
            selectors: None,
            owners: Some(vec![RelationRef {
                kind: "Deployment".to_string(),
                name: "nginx-deployment".to_string(),
                namespace: Some("default".to_string()),
                api_version: Some("apps/v1".to_string()),
                uid: Some("dep-123".to_string()),
            }]),
            relations: None,
        };

        tree.add_node(pod);

        // Link nodes
        tree.link_nodes();

        // Verify structure
        assert_eq!(tree.graph.node_count(), 3); // root + deployment + pod

        let dep_key = "deployment/default/nginx-deployment";
        let pod_key = "pod/default/nginx-pod-1";
        let dep_idx = tree.key_to_index[dep_key];
        let pod_idx = tree.key_to_index[pod_key];

        // Check ownership relationship
        let children_keys = tree.get_children_keys(dep_idx);
        assert!(children_keys.contains(&pod_key.to_string()));
        assert_eq!(tree.get_parent_key(pod_idx).as_deref(), Some(dep_key));

        // Check selector-based relationship
        let dep_leaf_keys = tree.get_leaf_keys(dep_idx);
        let pod_leaf_keys = tree.get_leaf_keys(pod_idx);
        assert!(dep_leaf_keys.contains(&pod_key.to_string()));
        assert!(pod_leaf_keys.contains(&dep_key.to_string()));

        // Test get_related_items
        let related = tree.get_related_items(dep_key);
        assert!(related.contains(&dep_key.to_string()));
        assert!(related.contains(&pod_key.to_string()));
    }

    #[test]
    fn test_export_dot() {
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
        };
        tree.add_node(deployment);

        let pod = Resource {
            kind: "Pod".to_string(),
            name: "pod-1".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("v1".to_string()),
            uid: Some("pod-1".to_string()),
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
        };
        tree.add_node(pod);

        tree.link_nodes();

        let dot = tree.export_dot();
        assert!(dot.contains("digraph"));
        assert!(dot.contains("Deployment"));
        assert!(dot.contains("Pod"));
        assert!(dot.contains("color=blue")); // Owns edge
    }

    #[test]
    fn test_export_mermaid() {
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
        };
        tree.add_node(deployment);

        let pod = Resource {
            kind: "Pod".to_string(),
            name: "pod-1".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("v1".to_string()),
            uid: Some("pod-1".to_string()),
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
        };
        tree.add_node(pod);

        tree.link_nodes();

        let mermaid = tree.to_mermaid();
        assert!(mermaid.starts_with("graph TD"));
        assert!(mermaid.contains("Deployment"));
        assert!(mermaid.contains("Pod"));
        assert!(mermaid.contains("-->")); // Owns edge
        assert!(mermaid.contains("classDef config")); // Style class
    }

    #[test]
    fn test_edge_types_distinction() {
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
        };

        let mut tree = Tree::new(root);

        // Add deployment with selectors
        let deployment = Resource {
            kind: "Deployment".to_string(),
            name: "app".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("apps/v1".to_string()),
            uid: Some("dep-1".to_string()),
            labels: None,
            selectors: Some({
                let mut map = HashMap::new();
                map.insert("app".to_string(), "web".to_string());
                map
            }),
            owners: None,
            relations: None,
        };
        tree.add_node(deployment);

        // Add pod owned by deployment (Owns edge)
        let pod = Resource {
            kind: "Pod".to_string(),
            name: "pod-1".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("v1".to_string()),
            uid: Some("pod-1".to_string()),
            labels: Some({
                let mut map = HashMap::new();
                map.insert("app".to_string(), "web".to_string());
                map
            }),
            selectors: None,
            owners: Some(vec![RelationRef {
                kind: "Deployment".to_string(),
                name: "app".to_string(),
                namespace: Some("default".to_string()),
                api_version: Some("apps/v1".to_string()),
                uid: Some("dep-1".to_string()),
            }]),
            relations: None,
        };
        tree.add_node(pod);

        // Add ConfigMap referenced by pod (References edge)
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
        };
        tree.add_node(configmap);

        // Add explicit relation from pod to configmap
        let pod_with_relation = Resource {
            kind: "Pod".to_string(),
            name: "pod-with-cm".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("v1".to_string()),
            uid: Some("pod-2".to_string()),
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
        };
        tree.add_node(pod_with_relation);

        tree.link_nodes();

        // Verify ownership edges
        let dep_idx = tree.key_to_index["deployment/default/app"];
        let pod_idx = tree.key_to_index["pod/default/pod-1"];
        let owns_edge_exists = tree
            .graph
            .edges_directed(dep_idx, Direction::Outgoing)
            .any(|e| e.target() == pod_idx && *e.weight() == EdgeType::Owns);
        assert!(
            owns_edge_exists,
            "Should have Owns edge from deployment to pod"
        );

        // Verify selector-based reference edges are bidirectional
        let ref_edge_to_pod = tree
            .graph
            .edges_directed(dep_idx, Direction::Outgoing)
            .any(|e| e.target() == pod_idx && *e.weight() == EdgeType::References);
        let ref_edge_from_pod = tree
            .graph
            .edges_directed(pod_idx, Direction::Outgoing)
            .any(|e| e.target() == dep_idx && *e.weight() == EdgeType::References);
        assert!(
            ref_edge_to_pod && ref_edge_from_pod,
            "Selector relationships should be bidirectional"
        );

        // Verify explicit reference edge to ConfigMap
        let cm_idx = tree.key_to_index["configmap/default/config"];
        let pod2_idx = tree.key_to_index["pod/default/pod-with-cm"];
        let ref_edge_to_cm = tree
            .graph
            .edges_directed(pod2_idx, Direction::Outgoing)
            .any(|e| e.target() == cm_idx && *e.weight() == EdgeType::References);
        assert!(
            ref_edge_to_cm,
            "Should have References edge from pod to configmap"
        );

        // ConfigMap should have reverse reference (since it's a ConfigMap)
        let ref_edge_from_cm = tree
            .graph
            .edges_directed(cm_idx, Direction::Outgoing)
            .any(|e| e.target() == pod2_idx && *e.weight() == EdgeType::References);
        assert!(
            ref_edge_from_cm,
            "ConfigMap should have reverse References edge"
        );
    }

    #[test]
    fn test_compute_impact() {
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
        };

        let mut tree = Tree::new(root);

        // Add ConfigMap
        let configmap = Resource {
            kind: "ConfigMap".to_string(),
            name: "my-config".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("v1".to_string()),
            uid: Some("cm-1".to_string()),
            labels: None,
            selectors: None,
            owners: None,
            relations: None,
        };
        tree.add_node(configmap);

        // Add Pod that references ConfigMap
        let pod = Resource {
            kind: "Pod".to_string(),
            name: "pod-1".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("v1".to_string()),
            uid: Some("pod-1".to_string()),
            labels: None,
            selectors: None,
            owners: None,
            relations: Some(vec![RelationRef {
                kind: "ConfigMap".to_string(),
                name: "my-config".to_string(),
                namespace: Some("default".to_string()),
                api_version: Some("v1".to_string()),
                uid: Some("cm-1".to_string()),
            }]),
        };
        tree.add_node(pod);

        // Add Deployment that owns Pod
        let deployment = Resource {
            kind: "Deployment".to_string(),
            name: "my-app".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("apps/v1".to_string()),
            uid: Some("dep-1".to_string()),
            labels: None,
            selectors: None,
            owners: None,
            relations: None,
        };
        tree.add_node(deployment);

        // Update pod to be owned by deployment
        let pod_with_owner = Resource {
            kind: "Pod".to_string(),
            name: "pod-1".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("v1".to_string()),
            uid: Some("pod-1".to_string()),
            labels: None,
            selectors: None,
            owners: Some(vec![RelationRef {
                kind: "Deployment".to_string(),
                name: "my-app".to_string(),
                namespace: Some("default".to_string()),
                api_version: Some("apps/v1".to_string()),
                uid: Some("dep-1".to_string()),
            }]),
            relations: Some(vec![RelationRef {
                kind: "ConfigMap".to_string(),
                name: "my-config".to_string(),
                namespace: Some("default".to_string()),
                api_version: Some("v1".to_string()),
                uid: Some("cm-1".to_string()),
            }]),
        };

        // Replace the pod node with the updated version
        let pod_key = "pod/default/pod-1";
        if let Some(&pod_idx) = tree.key_to_index.get(pod_key) {
            tree.graph[pod_idx] = pod_with_owner;
        }

        tree.link_nodes();

        // Test impact of deleting ConfigMap - should affect Pod
        let cm_key = "configmap/default/my-config";
        let impact = tree.compute_impact(cm_key);

        assert!(!impact.is_empty(), "ConfigMap should have dependents");
        assert!(
            impact.iter().any(|(key, _)| key == pod_key),
            "Pod should be in ConfigMap impact list"
        );

        // Test impact of deleting Pod - should affect Deployment
        let pod_key = "pod/default/pod-1";
        let impact = tree.compute_impact(pod_key);

        assert!(
            impact.iter().any(|(key, edge_type)| {
                key == "deployment/default/my-app" && edge_type == "owns"
            }),
            "Deployment should be in Pod impact list with 'owns' relationship"
        );

        // Test impact of deleting Deployment - should have no incoming edges
        let dep_key = "deployment/default/my-app";
        let impact = tree.compute_impact(dep_key);

        assert!(
            impact.is_empty(),
            "Deployment should have no resources depending on it"
        );
    }

    #[test]
    fn test_find_orphans() {
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
        };

        let mut tree = Tree::new(root);

        // Add deployment with no owner (orphan)
        let orphan_deployment = Resource {
            kind: "Deployment".to_string(),
            name: "orphan-deployment".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("apps/v1".to_string()),
            uid: Some("dep-orphan".to_string()),
            labels: None,
            selectors: None,
            owners: None, // No owner
            relations: None,
        };
        tree.add_node(orphan_deployment);

        // Add deployment with owner (not an orphan)
        let owned_deployment = Resource {
            kind: "Deployment".to_string(),
            name: "owned-deployment".to_string(),
            namespace: Some("default".to_string()),
            api_version: Some("apps/v1".to_string()),
            uid: Some("dep-owned".to_string()),
            labels: None,
            selectors: None,
            owners: Some(vec![RelationRef {
                kind: "Application".to_string(),
                name: "my-app".to_string(),
                namespace: Some("default".to_string()),
                api_version: Some("v1".to_string()),
                uid: Some("app-1".to_string()),
            }]),
            relations: None,
        };
        tree.add_node(owned_deployment);

        // Add a namespace (cluster-scoped, should be excluded)
        let namespace = Resource {
            kind: "Namespace".to_string(),
            name: "test-ns".to_string(),
            namespace: None,
            api_version: Some("v1".to_string()),
            uid: Some("ns-1".to_string()),
            labels: None,
            selectors: None,
            owners: None,
            relations: None,
        };
        tree.add_node(namespace);

        tree.link_nodes();

        let orphans = tree.find_orphans();

        // Should find the orphan deployment but not the namespace or owned deployment
        assert_eq!(orphans.len(), 1);
        assert!(orphans.contains(&"deployment/default/orphan-deployment".to_string()));
        assert!(!orphans.contains(&"namespace/test-ns".to_string()));
        assert!(!orphans.contains(&"deployment/default/owned-deployment".to_string()));
    }
}
