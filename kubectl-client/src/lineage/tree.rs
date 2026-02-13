use super::query::GraphQuery;
use k8s_openapi::serde::{Deserialize, Serialize};
use petgraph::graph::{DiGraph, NodeIndex};
use petgraph::visit::EdgeRef;
use petgraph::Direction;
use std::collections::{HashMap, HashSet};

type MissingTargets = HashMap<String, Vec<(String, String)>>;
type NodeMissingRefs = HashMap<String, HashMap<String, Vec<String>>>;

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
    pub is_orphan: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub resource_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub missing_refs: Option<HashMap<String, Vec<String>>>,
}

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

impl RelationRef {
    pub fn new(kind: impl Into<String>, name: impl Into<String>) -> Self {
        Self {
            kind: kind.into(),
            name: name.into(),
            namespace: None,
            api_version: None,
            uid: None,
        }
    }

    pub fn ns(mut self, namespace: Option<impl Into<String>>) -> Self {
        self.namespace = namespace.map(Into::into);
        self
    }

    pub fn api(mut self, api_version: Option<impl Into<String>>) -> Self {
        self.api_version = api_version.map(Into::into);
        self
    }

    pub fn get_resource_key(&self) -> String {
        if let Some(ref ns) = self.namespace {
            format!("{}/{}/{}", self.kind, ns, self.name).to_lowercase()
        } else {
            format!("{}/{}", self.kind, self.name).to_lowercase()
        }
    }
}

impl Resource {
    pub fn get_resource_key(&self) -> String {
        if let Some(ref ns) = self.namespace {
            return format!("{}/{}/{}", self.kind, ns, self.name).to_lowercase();
        }
        format!("{}/{}", self.kind, self.name).to_lowercase()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EdgeType {
    Owns,
    References,
}

#[derive(Debug, Clone)]
pub struct Tree {
    pub graph: DiGraph<Resource, EdgeType>,
    root_index: NodeIndex,
    pub key_to_index: HashMap<String, NodeIndex>,
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
        if self.key_to_index.contains_key(&key) {
            return;
        }
        let node_index = self.graph.add_node(resource);
        self.key_to_index.insert(key, node_index);
    }

    fn build_ownership_edges(&mut self, node_keys: &[String]) {
        for node_key in node_keys {
            if node_key == &self.root_key {
                continue;
            }

            let node_idx = self.key_to_index[node_key];
            let resource = &self.graph[node_idx];

            let owner_key = resource.owners.as_ref().and_then(|owners| {
                owners.first().map(|owner| {
                    RelationRef::new(&owner.kind, &owner.name)
                        .ns(owner.namespace.as_ref())
                        .get_resource_key()
                })
            });

            let parent_idx = owner_key
                .and_then(|key| self.key_to_index.get(&key).copied())
                .unwrap_or(self.root_index);

            self.graph.add_edge(parent_idx, node_idx, EdgeType::Owns);
        }
    }

    fn build_label_index(&self, node_keys: &[String]) -> Vec<(String, NodeIndex, HashMap<String, String>)> {
        node_keys
            .iter()
            .filter_map(|key| {
                let idx = *self.key_to_index.get(key)?;
                let labels = self.graph[idx].labels.clone()?;
                Some((key.clone(), idx, labels))
            })
            .collect()
    }

    fn build_selector_edges(
        &mut self,
        node_keys: &[String],
        nodes_with_labels: &[(String, NodeIndex, HashMap<String, String>)],
    ) {
        for node_key in node_keys {
            let node_idx = self.key_to_index[node_key];
            let selectors = match self.graph[node_idx].selectors.clone() {
                Some(s) => s,
                None => continue,
            };

            let matches: Vec<NodeIndex> = nodes_with_labels
                .iter()
                .filter(|(child_key, child_idx, labels)| {
                    child_key != node_key
                        && !matches!(self.graph[*child_idx].kind.as_str(), "ConfigMap" | "Secret")
                        && selectors_match(&selectors, labels)
                })
                .map(|(_, idx, _)| *idx)
                .collect();

            for child_idx in matches {
                self.graph.add_edge(node_idx, child_idx, EdgeType::References);
                self.graph.add_edge(child_idx, node_idx, EdgeType::References);
            }
        }
    }

    fn build_explicit_relation_edges(
        &mut self,
        node_keys: &[String],
    ) -> (MissingTargets, NodeMissingRefs) {
        let mut missing_targets: MissingTargets = HashMap::new();
        let mut node_missing_refs: NodeMissingRefs = HashMap::new();

        for node_key in node_keys {
            let node_idx = self.key_to_index[node_key];
            let relations = match self.graph[node_idx].relations.clone() {
                Some(r) => r,
                None => continue,
            };

            for relation in relations {
                let relation_key = RelationRef::new(&relation.kind, &relation.name)
                    .ns(relation.namespace.as_ref())
                    .get_resource_key();

                if let Some(&relation_idx) = self.key_to_index.get(&relation_key) {
                    self.graph.add_edge(node_idx, relation_idx, EdgeType::References);
                    self.graph.add_edge(relation_idx, node_idx, EdgeType::References);
                    tracing::debug!(
                        source_key = %node_key,
                        target_key = %relation_key,
                        relation_kind = %relation.kind,
                        "Found relation target in graph"
                    );
                } else {
                    missing_targets
                        .entry(relation.kind.clone())
                        .or_default()
                        .push((node_key.clone(), relation.name.clone()));

                    node_missing_refs
                        .entry(node_key.clone())
                        .or_default()
                        .entry(relation.kind.clone())
                        .or_default()
                        .push(relation.name.clone());

                    tracing::warn!(
                        source_key = %node_key,
                        target_key = %relation_key,
                        relation_kind = %relation.kind,
                        relation_name = %relation.name,
                        "Relation target NOT found in graph"
                    );
                }
            }
        }

        (missing_targets, node_missing_refs)
    }

    fn log_missing_targets(missing_targets: &MissingTargets) {
        if missing_targets.is_empty() {
            return;
        }

        let total_missing: usize = missing_targets.values().map(|v| v.len()).sum();
        tracing::warn!(
            missing_kinds = ?missing_targets.keys().collect::<Vec<_>>(),
            total_missing_edges = total_missing,
            "Graph construction incomplete: some relationship targets not found"
        );

        for (kind, sources) in missing_targets {
            if sources.len() <= 5 {
                for (source_key, target_name) in sources {
                    tracing::info!(
                        missing_kind = %kind,
                        source = %source_key,
                        target_name = %target_name,
                        "Missing relationship target"
                    );
                }
            } else {
                tracing::warn!(
                    missing_kind = %kind,
                    count = sources.len(),
                    examples = ?sources.iter().take(3).map(|(s, t)| format!("{} -> {}", s, t)).collect::<Vec<_>>(),
                    "Many resources missing this relationship target (showing first 3)"
                );
            }
        }
    }

    fn store_missing_refs(&mut self, node_missing_refs: NodeMissingRefs) {
        for (node_key, missing_refs_map) in node_missing_refs {
            if let Some(&idx) = self.key_to_index.get(&node_key) {
                if let Some(resource) = self.graph.node_weight_mut(idx) {
                    resource.missing_refs = Some(missing_refs_map);
                }
            }
        }
    }

    #[tracing::instrument(skip(self), fields(node_count = self.key_to_index.len()))]
    pub fn link_nodes(&mut self) {
        let node_keys: Vec<String> = self.key_to_index.keys().cloned().collect();

        self.build_ownership_edges(&node_keys);

        let nodes_with_labels = self.build_label_index(&node_keys);
        self.build_selector_edges(&node_keys, &nodes_with_labels);

        let (missing_targets, node_missing_refs) = self.build_explicit_relation_edges(&node_keys);
        Self::log_missing_targets(&missing_targets);
        self.store_missing_refs(node_missing_refs);

        self.compute_orphan_status();

        #[cfg(debug_assertions)]
        self.validate_ownership_dag();
    }

    #[cfg(debug_assertions)]
    fn validate_ownership_dag(&self) {
        use petgraph::algo::is_cyclic_directed;
        use petgraph::visit::EdgeFiltered;

        let ownership_graph = EdgeFiltered::from_fn(&self.graph, |edge| {
            *edge.weight() == EdgeType::Owns
        });

        if is_cyclic_directed(&ownership_graph) {
            tracing::error!("Ownership graph contains cycles!");
            panic!("Ownership relationships must form a DAG");
        }
    }

    fn compute_orphan_status(&mut self) {
        for (key, &idx) in self.key_to_index.iter() {
            if key == &self.root_key {
                continue;
            }

            let resource = &self.graph[idx];
            let kind = &resource.kind;
            let name = &resource.name;
            let namespace = resource.namespace.as_deref();
            let labels = resource.labels.as_ref();
            let resource_type = resource.resource_type.as_deref();
            let missing_refs = resource.missing_refs.as_ref();

            let incoming_refs: Vec<(EdgeType, String)> = self
                .graph
                .edges_directed(idx, Direction::Incoming)
                .filter(|edge| edge.source() != self.root_index)
                .map(|edge| {
                    let source_kind = self.graph[edge.source()].kind.clone();
                    (*edge.weight(), source_kind)
                })
                .collect();

            let incoming_refs_slice: Vec<(EdgeType, &str)> = incoming_refs
                .iter()
                .map(|(edge_type, kind)| (*edge_type, kind.as_str()))
                .collect();

            let is_orphan = super::registry::is_resource_orphan(
                kind, name, namespace, &incoming_refs_slice, labels, resource_type, missing_refs
            );

            if let Some(resource) = self.graph.node_weight_mut(idx) {
                resource.is_orphan = is_orphan;
            }
        }
    }

    #[tracing::instrument(skip(self), fields(node_key = %node_key))]
    pub fn get_related_items(&self, node_key: &str) -> Vec<String> {
        GraphQuery::from_key(self, node_key)
            .map(|q| q.ancestors().descendants().with_references().collect_keys())
            .unwrap_or_default()
    }

    pub(crate) fn get_key_for_index(&self, idx: NodeIndex) -> String {
        self.graph[idx].get_resource_key()
    }

    pub fn get_children_keys(&self, idx: NodeIndex) -> Vec<String> {
        let mut keys: Vec<String> = self.graph
            .edges_directed(idx, Direction::Outgoing)
            .filter(|e| *e.weight() == EdgeType::Owns)
            .map(|e| self.get_key_for_index(e.target()))
            .collect();
        keys.sort();
        keys
    }

    pub fn get_leaf_keys(&self, idx: NodeIndex) -> Vec<String> {
        self.graph
            .edges_directed(idx, Direction::Outgoing)
            .filter(|e| *e.weight() == EdgeType::References)
            .map(|e| self.get_key_for_index(e.target()))
            .collect()
    }

    pub fn get_parent_key(&self, idx: NodeIndex) -> Option<String> {
        self.graph
            .edges_directed(idx, Direction::Incoming)
            .find(|e| *e.weight() == EdgeType::Owns)
            .map(|e| self.get_key_for_index(e.source()))
    }

    #[tracing::instrument(skip(self), fields(resource_key = %resource_key))]
    pub fn compute_impact(&self, resource_key: &str) -> Vec<(String, String)> {
        let node_idx = match self.key_to_index.get(resource_key) {
            Some(&idx) => idx,
            None => return Vec::new(),
        };

        let mut impacted = Vec::new();
        let mut direct_referencers = Vec::new();

        for edge in self.graph.edges_directed(node_idx, Direction::Incoming) {
            if matches!(edge.weight(), EdgeType::References) {
                let source_idx = edge.source();
                let source_key = self.get_key_for_index(source_idx);

                if source_key != self.root_key {
                    direct_referencers.push(source_idx);
                    impacted.push((source_key, "references".to_string()));
                }
            }
        }

        for referencer_idx in direct_referencers {
            if let Some(q) = GraphQuery::from_key(self, &self.get_key_for_index(referencer_idx)) {
                let descendants = q.descendants().collect_keys();
                for key in descendants {
                    if key != self.get_key_for_index(referencer_idx) {
                        impacted.push((key, "owned by affected".to_string()));
                    }
                }
            }
        }

        impacted.sort_by(|a, b| a.0.cmp(&b.0));
        impacted
    }

    #[tracing::instrument(skip(self), fields(resource_key = %resource_key))]
    pub fn extract_subgraph(&self, resource_key: &str) -> (HashSet<NodeIndex>, HashSet<usize>) {
        let subgraph_nodes = GraphQuery::from_key(self, resource_key)
            .map(|q| q.ancestors().descendants().with_references().collect_nodes())
            .unwrap_or_default();

        let mut subgraph_edges = HashSet::new();
        for edge in self.graph.edge_references() {
            let source = edge.source();
            let target = edge.target();

            if subgraph_nodes.contains(&source) && subgraph_nodes.contains(&target) {
                subgraph_edges.insert(edge.id().index());
            }
        }

        (subgraph_nodes, subgraph_edges)
    }

    pub fn export_subgraph_dot(&self, resource_key: &str) -> String {
        let (subgraph_nodes, subgraph_edges) = self.extract_subgraph(resource_key);

        let mut output = String::from("digraph lineage_subgraph {\n");
        output.push_str("    rankdir=TB;\n");
        output.push_str("    node [fontname=\"Arial\"];\n");
        output.push_str("    edge [fontname=\"Arial\"];\n\n");

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

    pub fn export_dot(&self) -> String {
        let mut output = String::from("digraph lineage {\n");
        output.push_str("    rankdir=TB;\n");
        output.push_str("    node [fontname=\"Arial\"];\n");
        output.push_str("    edge [fontname=\"Arial\"];\n\n");

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

    pub fn find_orphans(&self) -> Vec<String> {
        let mut orphans = Vec::new();

        for (key, &idx) in self.key_to_index.iter() {
            if key == &self.root_key {
                continue;
            }

            let resource = &self.graph[idx];
            if resource.is_orphan {
                orphans.push(key.clone());
            }
        }

        orphans.sort();
        orphans
    }

    pub fn export_subgraph_mermaid(&self, resource_key: &str) -> String {
        let (subgraph_nodes, subgraph_edges) = self.extract_subgraph(resource_key);

        let mut output = String::from("graph TD\n");

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

        output.push_str("\n    classDef config fill:#ffffcc,stroke:#333,stroke-width:2px\n");
        output
    }

    pub fn to_mermaid(&self) -> String {
        let mut output = String::from("graph TD\n");

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

        for edge in self.graph.edge_references() {
            let source_id = &node_ids[&edge.source()];
            let target_id = &node_ids[&edge.target()];

            let edge_def = match edge.weight() {
                EdgeType::Owns => format!("    {} --> {}\n", source_id, target_id),
                EdgeType::References => format!("    {} -.-> {}\n", source_id, target_id),
            };

            output.push_str(&edge_def);
        }

        output.push_str("\n    classDef config fill:#ffffcc,stroke:#333,stroke-width:2px\n");
        output
    }
}

fn selectors_match(selectors: &HashMap<String, String>, labels: &HashMap<String, String>) -> bool {
    selectors
        .iter()
        .all(|(key, value)| labels.get(key).map(|v| v == value).unwrap_or(false))
}
