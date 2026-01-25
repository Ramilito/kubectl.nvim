# Lineage Module

This module implements resource lineage graph building for Kubernetes resources. It creates a hierarchical tree structure showing relationships between resources through owner references, label selectors, and explicit resource references.

## Architecture

### Core Components

1. **`tree.rs`** - Core data structures
   - `Resource` - Represents a K8s resource with metadata
   - `RelationRef` - Reference to a related resource
   - `TreeNode` - Node in the lineage tree
   - `Tree` - The complete lineage graph

2. **`relationships.rs`** - Relationship extraction logic
   - Hardcoded rules for extracting relationships from specific resource types
   - Supports: Event, Ingress, IngressClass, Pod, ClusterRole, PVC, PV, ClusterRoleBinding

3. **`builder.rs`** - Graph construction and Lua serialization
   - `build_lineage_graph()` - Main entry point called from Lua
   - Parses JSON resources, builds tree, returns Lua table

## Usage from Lua

```lua
local kubectl_client = require("kubectl_client")

-- Resources should be an array of resource objects
local resources_json = vim.json.encode({
  { kind = "Pod", name = "my-pod", ns = "default", owners = {...}, ... },
  { kind = "Deployment", name = "my-deploy", ns = "default", ... },
  -- ... more resources
})

local root_name = "my-cluster"
local graph = kubectl_client.build_lineage_graph(resources_json, root_name)

-- graph structure:
-- {
--   root_key = "cluster/my-cluster",
--   nodes = { array of node tables },
--   get_related_nodes = function(selected_key) ... end
-- }

-- Get related nodes for a specific resource
local selected_key = "pod/default/my-pod"
local related = graph.get_related_nodes(selected_key)
-- Returns array of keys: ["pod/default/my-pod", "deployment/default/my-deploy", ...]
```

## Relationship Types

### Parent-Child (via ownerReferences)
- ReplicaSet owns Pods
- Deployment owns ReplicaSets
- Follows Kubernetes `metadata.ownerReferences`

### Bidirectional (via label selectors)
- Service selects Pods via `spec.selector`
- Deployment selects ReplicaSets via `spec.selector`
- Both nodes maintain references to each other

### Explicit Relations (via resource references)
- Pod → Node (via `spec.nodeName`)
- Pod → ServiceAccount (via `spec.serviceAccountName`)
- Pod → ConfigMap/Secret (via `spec.volumes`)
- Ingress → Service (via `spec.rules[].http.paths[].backend`)
- PVC → PV (via `spec.volumeName`)
- And more...

## Key Design Decisions

### 1. Serialized Data, Not UserData
Returns Lua tables instead of UserData to avoid lifetime/borrow checker complexity when crossing the FFI boundary.

### 2. Custom Tree, Not petgraph
Simple custom tree implementation instead of petgraph dependency. Simpler for our specific use case.

### 3. Hardcoded Relationship Rules
Relationship extraction logic is hardcoded in Rust enums rather than being data-driven. Easier to maintain and type-safe.

### 4. Key-Based Lookup
Resources are identified by lowercase keys: `kind/namespace/name` or `kind/name` for cluster-scoped resources.

## Performance Characteristics

- **Time Complexity**: O(n²) for selector matching during `link_nodes()`
- **Space Complexity**: O(n) where n is the number of resources
- **Typical Usage**: Handles 1000s of resources efficiently

## Future Enhancements

1. Add more relationship types (RoleBinding subjects, etc.)
2. Support custom relationship extractors from Lua
3. Cache compiled selector matchers
4. Parallel processing for large graphs

## Testing

Run tests with:
```bash
cargo test --lib lineage
```

Tests cover:
- Resource key generation
- Selector matching
- Relationship extraction for various resource types
- JSON parsing
