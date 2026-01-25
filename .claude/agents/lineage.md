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
| Lua | `lua/kubectl/views/lineage/init.lua` | View lifecycle (View, Draw, load_cache), keymaps, folding |
| Lua | `lua/kubectl/views/lineage/definition.lua` | Resource definition, graph building, display formatting |
| Lua | `lua/kubectl/views/lineage/tree.lua` | Tree/TreeNode classes, graph algorithms |
| Lua | `lua/kubectl/views/lineage/relationships.lua` | K8s resource relationship definitions |

## Data Flow

```
Lua
-----------------------------------------------------------
View(name, ns, kind) --> Check cache ready
                    --> load_cache() if first time
                    --> Create floating buffer
                    --> Draw()

load_cache() --> Fetch all API resources via get_all_async
            --> processRow() for each resource
            --> Build relationships (owners, dependencies)
            --> Store in cached_api_resources.values[].data
            --> Fire K8sLineageDataLoaded autocmd

Draw() --> collect_all_resources() from cache
       --> build_graph() creates Tree
       --> build_display_lines() for selected node
       --> displayContentRaw() with folding
```

## Core Data Structures

### TreeNode (`tree.lua:24-46`)

```lua
local node = {
    resource = resource,    -- Original K8s resource data
    children = {},          -- Child nodes (via ownerReferences)
    leafs = {},             -- Bidirectional relations (via selectors)
    key = "kind/ns/name",   -- Unique identifier
    parent = nil,           -- Parent node reference
}
```

### Tree (`tree.lua:48-61`)

```lua
local tree = {
    root = TreeNode,        -- Cluster root node
    nodes_by_key = {},      -- Fast lookup by key
    nodes_list = {},        -- Ordered list for iteration
}
```

### Resource Row (`definition.lua:72-87`)

```lua
local row = {
    name = "resource-name",
    ns = "namespace",
    apiVersion = "v1",
    labels = { ... },
    owners = { ... },       -- Owner relationships
    relations = { ... },    -- Dependency relationships
    selectors = { ... },    -- For matching children by labels
}
```

## Key Functions

### Tree Operations

| Function | Location | Purpose |
|----------|----------|---------|
| `Tree:add_node()` | `tree.lua:63-75` | Add resource to graph |
| `Tree:link_nodes()` | `tree.lua:77-146` | Build parent-child and leaf relationships |
| `Tree:get_related_items()` | `tree.lua:148-216` | Find all related nodes for selection |

### Relationship Resolution

| Function | Location | Purpose |
|----------|----------|---------|
| `getRelationship()` | `relationships.lua:11-63` | Extract relationships from resource spec |
| `extractFieldValue()` | `relationships.lua:3-9` | Navigate nested field paths |

### View Lifecycle

| Function | Location | Purpose |
|----------|----------|---------|
| `M.View()` | `init.lua:26-57` | Entry point, setup buffer |
| `M.Draw()` | `init.lua:59-131` | Render tree to buffer |
| `M.load_cache()` | `init.lua:133-178` | Fetch all resources async |
| `M.set_folding()` | `init.lua:223-289` | Configure fold expression |

## Relationship Types

Defined in `relationships.lua:65-502`. Two main types:

| Type | Meaning | Example |
|------|---------|---------|
| `owner` | Target owns this resource | Event → Pod (regarding) |
| `dependency` | This resource depends on target | Pod → Node (nodeName) |

### Supported Resources

- **Event** - regarding, related references
- **Ingress** - ingressClassName, backend services, TLS secrets
- **IngressClass** - parameters reference
- **Pod** - nodeName, priorityClass, runtimeClass, serviceAccount, volumes
- **ClusterRole** - aggregation rules, policy rules
- **PersistentVolumeClaim** - volumeName
- **PersistentVolume** - claimRef
- **ClusterRoleBinding** - subjects, roleRef

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

## Kind Normalization (`init.lua:76-93`)

Views use plural forms, lineage uses singular. Special cases:
- `storageclasses` → `storageclass`
- `ingresses` → `ingress`
- `ingressclasses` → `ingressclass`
- `sa` → `serviceaccount`
- Default: strip trailing `s`

## Folding Implementation

Custom fold expression in `set_folding()` (`init.lua:223-289`):
- Uses indent-based folding (`foldmethod=expr`)
- Custom `kubectl_fold_expr()` calculates level from indent
- Custom `kubectl_get_statuscol()` shows fold icons (,)
- Shiftwidth: 4 spaces per indent level

## Common Tasks

### Adding a New Relationship Type

1. Add entry to `M.definition` in `relationships.lua`
2. Specify `relationship_type`: `owner` or `dependency`
3. Define `field_path` to extract the reference
4. Implement `target_kind`, `target_name`, `target_namespace` functions
5. Use `extract_subfield` for array fields

Example pattern:
```lua
MyResource = {
    kind = "MyResource",
    relationships = {
        {
            relationship_type = "dependency",
            field_path = "spec.targetRef",
            target_kind = function(field_value)
                return field_value.kind
            end,
            target_name = function(field_value)
                return field_value.name
            end,
            target_namespace = true,  -- Same as source
        },
    },
},
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
