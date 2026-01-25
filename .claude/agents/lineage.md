---
name: lineage
description: Lineage feature specialist. ALWAYS use for ANY task involving resource lineage, relationship graphs, owner references, or the lineage tree view.
tools: Read, Grep, Glob, Edit, Write, Bash
model: sonnet
---

# Lineage Feature Guidance

**ALWAYS use this subagent** for ANY task involving:
- Resource lineage display or tree visualization
- Owner reference traversal
- Relationship definitions between K8s resources
- Label selector matching for resource relationships
- Lineage cache loading or refresh
- Folding behavior in lineage view

For general Lua patterns or Neovim API usage, use the `lua` subagent.

## File Map

| Layer | File | Purpose |
|-------|------|---------|
| Rust | `kubectl-client/src/lineage/relationships.rs` | K8s resource relationship extraction |
| Rust | `kubectl-client/src/lineage/builder.rs` | Parse resources, build tree, convert to Lua |
| Rust | `kubectl-client/src/lineage/tree.rs` | Tree/TreeNode structs, graph algorithms |
| Lua | `lua/kubectl/views/lineage/init.lua` | View lifecycle (View, Draw, load_cache), keymaps, folding |
| Lua | `lua/kubectl/views/lineage/definition.lua` | Resource collection, display formatting |
| Lua | `lua/kubectl/views/lineage/tree.lua` | DEPRECATED - kept for backward compatibility |
| Lua | `lua/kubectl/views/lineage/relationships.lua` | DEPRECATED - relationships now extracted in Rust |

## Data Flow

```
Lua --> Rust Integration
-----------------------------------------------------------
View(name, ns, kind) --> Check cache ready
                    --> load_cache() if first time
                    --> Create floating buffer
                    --> Draw()

load_cache() --> Fetch all API resources via get_all_async
            --> processRow() stores raw resource data
            --> Store in cached_api_resources.values[].data
            --> Fire K8sLineageDataLoaded autocmd

Draw() --> collect_all_resources() from cache (with namespaced flag)
       --> build_graph() --> Rust build_lineage_graph()
           --> Parse resources
           --> Extract ownerReferences from metadata
           --> Extract relationships via relationships::extract_relationships()
           --> Build tree structure
           --> Return Lua table with nodes and get_related_nodes function
       --> build_display_lines() for selected node
       --> displayContentRaw() with folding
```

## Core Data Structures

### Resource (Rust: `tree.rs:6-18`)

```rust
pub struct Resource {
    pub kind: String,
    pub name: String,
    pub namespace: Option<String>,
    pub api_version: Option<String>,
    pub uid: Option<String>,
    pub labels: Option<HashMap<String, String>>,
    pub selectors: Option<HashMap<String, String>>,
    pub owners: Option<Vec<RelationRef>>,      // From ownerReferences
    pub relations: Option<Vec<RelationRef>>,   // From relationship extraction
}
```

### TreeNode (Rust: `tree.rs:33-40`)

```rust
pub struct TreeNode {
    pub resource: Resource,
    pub children_keys: Vec<String>,  // Child nodes (via ownerReferences)
    pub leaf_keys: Vec<String>,      // Bidirectional relations (via selectors)
    pub key: String,                 // Unique identifier: "kind/ns/name" or "kind/name"
    pub parent_key: Option<String>,  // Parent node reference
}
```

### Tree (Rust: `tree.rs:78-82`)

```rust
pub struct Tree {
    pub root: TreeNode,              // Cluster root node
    pub nodes: HashMap<String, TreeNode>,  // Fast lookup by key
}
```

### Resource Row (Lua: `definition.lua:41-49`)

```lua
local row = {
    kind = "Pod",
    name = "resource-name",
    ns = "namespace",
    apiVersion = "v1",
    labels = { ... },
    metadata = { ... },      -- Full metadata for Rust extraction
    spec = { ... },          -- Full spec for Rust extraction
    selectors = { ... },     -- For matching children by labels
    namespaced = true,       -- From API resource metadata
}
```

## Key Functions

### Rust Functions

| Function | Location | Purpose |
|----------|----------|---------|
| `build_lineage_graph()` | `builder.rs:11-61` | Main entry point, builds tree and returns Lua table |
| `parse_resource()` | `builder.rs:64-162` | Parse JSON resource, extract owners and relationships |
| `extract_relationships()` | `relationships.rs:5-21` | Dispatch relationship extraction by kind |
| `extract_pod_relationships()` | `relationships.rs:211-275` | Extract Pod → Node, ServiceAccount, ConfigMap, etc. |
| `extract_hpa_relationships()` | `relationships.rs:562-594` | Extract HPA → scaleTargetRef |
| `Tree::add_node()` | `tree.rs:94-104` | Add resource node to graph |
| `Tree::link_nodes()` | `tree.rs:106-207` | Build parent-child and leaf relationships |
| `Tree::get_related_items()` | `tree.rs:209-276` | Find all related nodes for selection |
| `TreeNode::get_resource_key()` | `tree.rs:55-60` | Generate unique key based on namespace |

### Lua Functions

| Function | Location | Purpose |
|----------|----------|---------|
| `M.View()` | `init.lua:26-57` | Entry point, setup buffer |
| `M.Draw()` | `init.lua:59-103` | Render tree to buffer, call Rust graph builder |
| `M.load_cache()` | `init.lua:133-178` | Fetch all resources async |
| `M.processRow()` | `definition.lua:14-68` | Store raw resource data with metadata/spec |
| `M.collect_all_resources()` | `definition.lua:70-83` | Collect resources with namespaced flag |
| `M.build_graph()` | `definition.lua:85-94` | Convert to JSON and call Rust |
| `M.build_display_lines()` | `definition.lua:96-220` | Format tree for display |
| `M.set_folding()` | `init.lua:223-289` | Configure fold expression |

## Relationship Types

Defined in `kubectl-client/src/lineage/relationships.rs`. All relationships are dependency-based (this resource depends on or references the target).

### Supported Resources

- **Event** - regarding, related references
- **Ingress** - ingressClassName, backend services, TLS secrets
- **IngressClass** - parameters reference
- **Pod** - nodeName, priorityClass, runtimeClass, serviceAccount, volumes (ConfigMap, Secret, PVC, CSI)
- **ClusterRole** - aggregation rules (currently returns empty, can be enhanced)
- **PersistentVolumeClaim** - volumeName
- **PersistentVolume** - claimRef
- **ClusterRoleBinding** - subjects (ServiceAccounts), roleRef
- **StatefulSet** - volumeClaimTemplates, serviceName
- **DaemonSet** - (placeholder, can be enhanced)
- **Job** - (placeholder, can be enhanced)
- **CronJob** - (placeholder, can be enhanced)
- **HorizontalPodAutoscaler** - scaleTargetRef

## User Events

| Event | Trigger |
|-------|---------|
| `K8sLineageDataLoaded` | Cache loading complete, triggers redraw |

## Keybindings

| Key | Plug | Action |
|-----|------|--------|
| `<CR>` | `<Plug>(kubectl.select)` | Navigate to selected resource |
| `gr` | `<Plug>(kubectl.refresh)` | Refresh lineage cache |

## State Management

```lua
M.selection = {}    -- Current selection: {name, ns, kind}
M.builder = nil     -- Resource builder for buffer
M.loaded = false    -- Cache loaded flag
M.is_loading = false -- Loading in progress
M.processed = 0     -- Progress counter
M.total = 0         -- Total resources to load
```

## Kind Normalization (`init.lua:75-93`)

Views use plural forms (e.g., "pods"), lineage needs singular forms (e.g., "Pod").

**Implementation:** Lookup in `cached_api_resources` to find the actual GVK kind:
1. Check `cached_api_resources.values[lowercase_kind]`
2. Check `cached_api_resources.shortNames[lowercase_kind]`
3. Extract `resource_info.gvk.k` for the canonical kind
4. Fallback to simple plural removal if not found in cache

**Benefits:**
- Robust for all resource types, including CRDs
- No hardcoded special cases
- Uses the same API resource metadata as the rest of the plugin

## Folding Implementation

Custom fold expression in `set_folding()` (`init.lua:223-289`):
- Uses indent-based folding (`foldmethod=expr`)
- Custom `kubectl_fold_expr()` calculates level from indent
- Custom `kubectl_get_statuscol()` shows fold icons (,)
- Shiftwidth: 4 spaces per indent level

## Common Tasks

### Adding a New Relationship Type

Add an extraction function in `kubectl-client/src/lineage/relationships.rs`:

1. Add the resource kind to the match statement in `extract_relationships()`
2. Create a new `extract_RESOURCE_relationships()` function
3. Extract relevant fields from `item: &Value`
4. Return `Vec<RelationRef>` with all related resources

Example pattern:
```rust
fn extract_deployment_relationships(item: &Value) -> Vec<RelationRef> {
    let mut relations = Vec::new();
    let namespace = item
        .get("metadata")
        .and_then(|m| m.get("namespace"))
        .and_then(|v| v.as_str());

    // Example: Extract a simple string reference
    if let Some(target_name) = item
        .get("spec")
        .and_then(|s| s.get("targetRef"))
        .and_then(|v| v.as_str())
    {
        relations.push(RelationRef {
            kind: "TargetResource".to_string(),
            name: target_name.to_string(),
            namespace: namespace.map(String::from),
            api_version: None,
            uid: None,
        });
    }

    relations
}
```

### Adding Display Information

Modify `build_display_lines()` in `definition.lua:125-197`:
1. Adjust line formatting in the `build_lines()` inner function
2. Update marks for highlighting
3. Modify indent string for different tree styles

### Adding Tree Traversal Logic

Modify `Tree:get_related_items()` in `tree.lua:148-216`:
1. Extend `collect_descendants()` for new traversal patterns
2. Add new collection helpers similar to `collect_leafs()`
3. Ensure visited tracking to avoid infinite loops
