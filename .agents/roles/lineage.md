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
- Orphan detection and filtering
- Impact analysis
- Export (DOT/Mermaid)
- Lineage cache loading or refresh

For general Lua patterns or Neovim API usage, use the `lua` subagent.

## Delegation Rules

**Delegate to `rust` subagent for:**
- Adding tracing/instrumentation to Rust code
- Telemetry or logging changes
- Any cross-cutting Rust concerns not specific to lineage logic

## File Map

### Lua (`lua/kubectl/views/lineage/`)

| File | Responsibility |
|------|---------------|
| `init.lua` | **Orchestrator** — View lifecycle, Draw dispatch, state machine, progress timer, folding. Thin layer that delegates data ops to `graph.lua` and rendering to `renderer.lua` |
| `graph.lua` | **Data pipeline** — Facade for fetch → process → build. Owns `processRow`, `collect_all_resources`, `build_graph_async`, and `load_and_build`. Uses `commands.run_async` / `commands.await_all` |
| `definition.lua` | **Static metadata only** — resource name, ft, hints, panes, `find_resource_name()` |
| `renderer.lua` | **Rendering** — `RenderContext` builder class, render functions for each phase (status, header, tree, orphans, error) |
| `actions.lua` | **User actions** — `go_to_resource`, `impact_analysis` (floating buffer), `export` (DOT/Mermaid, table-driven format dispatch) |
| `mappings.lua` | **Keybindings** — Uses `with_graph_node(fn)` decorator for callbacks needing graph+cursor validation |

### Rust (`kubectl-client/src/lineage/`)

| File | Responsibility |
|------|---------------|
| `builder.rs` | FFI entry points — `build_lineage_graph_worker`, `get_lineage_related_nodes`, export/impact/orphan functions. Stores trees in `LINEAGE_TREES` mutex |
| `tree.rs` | `Resource`, `RelationRef`, `EdgeType`, `Tree` structs. Uses `petgraph::DiGraph` for the graph. Key methods: `new`, `add_node`, `link_nodes` |
| `query.rs` | `GraphQuery` — traversal algorithms for related nodes, subgraph extraction, impact computation |
| `relationships.rs` | `extract_relationships(kind, item)` — extracts dependency refs from resource JSON by kind |
| `orphan_rules.rs` | Orphan detection rules and exceptions |
| `resource_behavior.rs` | Resource-specific behavior traits |
| `registry.rs` | Resource behavior registry |
| `mod.rs` | Module exports and `install()` for Lua FFI registration |

## Architecture & Design Patterns

### State Machine (`init.lua`)
Phases: `"idle"` → `"loading"` → `"building"` → `"ready"` | `"error"`

`Draw()` dispatches to the correct renderer function based on phase. The progress timer runs during `"loading"` to update the display.

### Facade Pattern (`graph.lua: load_and_build`)
Single entry point encapsulating: GVK enumeration → `await_all` fetch → JSON decode → `processRow` → `collect_all_resources` → `build_graph_async`. Takes three callbacks: `on_progress`, `on_building`, `on_graph`.

### Decorator Pattern (`mappings.lua: with_graph_node`)
Wraps mapping callbacks with graph existence + cursor node validation. Callbacks receive `(graph, resource_key)`.

### Table-Driven Dispatch
- `actions.lua: export_formats` — format config table for DOT/Mermaid
- `init.lua: folding_buf_opts / folding_win_opts` — fold settings as data

### RenderContext (`renderer.lua`)
Builder class that tracks lines, marks, line_nodes, and header separately. Key methods: `line()`, `blank()`, `mark()`, `set_node()`, `header()`, `resource_line()`, `kind_header()`, `get()`. Used by both the main view and impact analysis popup.

## Data Flow

```
User triggers gxx on a resource
  → mappings dispatches to init.View(name, ns, kind)

init.View()
  → manager.get_or_create(definition.resource)
  → builder.view_framed(definition, {recreate_func, recreate_args})
  → state.addToHistory()
  → Registers BufWipeout cleanup
  → Calls begin_loading() if no graph

begin_loading()
  → Sets phase="loading", starts progress timer
  → graph_mod.load_and_build(on_progress, on_building, on_graph)
    → commands.await_all(get_all_async for each GVK)
    → processRow() stores data in cached_api_resources
    → on_building: phase="building", Draw()
    → build_graph_async → commands.run_async("build_lineage_graph_worker")
      → Rust: parse resources, build petgraph, store in LINEAGE_TREES
      → Returns JSON {nodes, root_key, tree_id}
    → on_graph: phase="ready", Draw()

Draw()
  → renderer.render_tree(ctx, graph, selected_key)
    → graph.get_related_nodes(selected_key) → Rust lookup
    → Walk ownership tree + reference nodes
  → builder.displayContentRaw()
  → set_folding()
```

## Key Rust FFI Functions

| Lua Call | Rust Function | Worker? | Notes |
|----------|--------------|---------|-------|
| `commands.run_async("build_lineage_graph_worker", args)` | `build_lineage_graph_worker` | Yes | Stores tree in `LINEAGE_TREES`, returns JSON. Args: `{resources, root_name}` |
| `client.get_lineage_related_nodes(tree_id, key)` | `get_lineage_related_nodes` | No (sync) | Looks up stored tree, returns JSON array of related keys |
| `client.compute_lineage_impact(tree_id, key)` | `compute_lineage_impact` | No | Returns JSON array of `[key, edge_type]` tuples |
| `client.export_lineage_subgraph_dot(tree_id, key)` | `export_lineage_subgraph_dot` | No | Returns DOT string |
| `client.export_lineage_subgraph_mermaid(tree_id, key)` | `export_lineage_subgraph_mermaid` | No | Returns Mermaid string |
| `client.find_lineage_orphans(tree_id)` | `find_lineage_orphans` | No | Returns JSON array of orphan keys |

**Important**: `build_lineage_graph_worker` is called via `commands.run_async` (runs in `vim.uv.new_work` thread). All other lineage client functions are synchronous and called directly on the main thread.

## Core Rust Data Structures

```rust
// tree.rs
pub struct Resource {
    pub kind: String,
    pub name: String,
    pub namespace: Option<String>,  // serialized as "ns"
    pub api_version: Option<String>,
    pub uid: Option<String>,
    pub labels: Option<HashMap<String, String>>,
    pub selectors: Option<HashMap<String, String>>,
    pub owners: Option<Vec<RelationRef>>,
    pub relations: Option<Vec<RelationRef>>,
    pub is_orphan: bool,
}

pub struct Tree {
    pub graph: DiGraph<Resource, EdgeType>,  // petgraph directed graph
    root_index: NodeIndex,
    pub key_to_index: HashMap<String, NodeIndex>,
    pub root_key: String,
}

pub enum EdgeType { Owns, References }
```

**Key format**: `"kind/namespace/name"` (lowercased) or `"kind/name"` for cluster-scoped.

## Graph JSON (Rust → Lua)

The JSON returned by `build_lineage_graph_worker` contains:
```json
{
  "nodes": [{ "key": "...", "kind": "...", "name": "...", "ns": "...",
              "parent_key": "...", "children_keys": [...], "is_orphan": false }],
  "root_key": "cluster/cluster-name",
  "tree_id": "uuid"
}
```

The Lua graph object wraps this with a `get_related_nodes(key)` closure that calls back into Rust.

## Keybindings

| Key | Plug | Action |
|-----|------|--------|
| `<CR>` | `<Plug>(kubectl.select)` | Navigate to resource view |
| `gr` | `<Plug>(kubectl.refresh)` | Refresh (reload all resources) |
| `gO` | `<Plug>(kubectl.toggle_orphan_filter)` | Toggle orphan-only view |
| `gI` | `<Plug>(kubectl.impact_analysis)` | Show impact analysis popup |
| `gD` | `<Plug>(kubectl.export_dot)` | Export subgraph as DOT |
| `gM` | `<Plug>(kubectl.export_mermaid)` | Export subgraph as Mermaid |

## Relationship Types (`relationships.rs`)

Resources with extracted dependency relationships:
- **Event** — regarding, related references
- **Ingress** — ingressClassName, backend services, TLS secrets
- **IngressClass** — parameters reference
- **Pod** — nodeName, priorityClass, runtimeClass, serviceAccount, volumes (ConfigMap, Secret, PVC, CSI)
- **PersistentVolumeClaim** — volumeName
- **PersistentVolume** — claimRef
- **ClusterRoleBinding** — subjects, roleRef
- **StatefulSet** — volumeClaimTemplates, serviceName
- **HorizontalPodAutoscaler** — scaleTargetRef

## Common Tasks

### Adding a New Relationship Type

In `kubectl-client/src/lineage/relationships.rs`:
1. Add kind to match in `extract_relationships()`
2. Create `extract_<resource>_relationships(item: &Value) -> Vec<RelationRef>`
3. Use `RelationRef::new(kind, name).ns(namespace)` builder pattern

### Adding a New Keybinding

1. Add hint to `definition.lua: M.hints`
2. Add override in `mappings.lua: M.overrides` — use `with_graph_node()` if it needs graph+cursor
3. Register default key in `mappings.lua: M.register`
4. Implement action in `actions.lua` if it's a user-facing feature

### Adding a New Render Mode

1. Add render function in `renderer.lua`
2. Add phase/condition branch in `init.lua: Draw()`
3. If it needs new state, add to `init.lua` locals

### Modifying the Data Pipeline

All data operations live in `graph.lua`. The facade `load_and_build` coordinates the pipeline. To change how data is fetched or processed, modify `graph.lua` only — `init.lua` should not know pipeline details.

## User Events

| Event | Trigger |
|-------|---------|
| `K8sLineageDataLoaded` | All resources fetched, fired before graph build starts |
