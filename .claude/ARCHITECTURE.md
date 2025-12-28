# ARCHITECTURE.md

Architecture contract for kubectl.nvim. Defines expected structure, layer boundaries, and dependency rules.

## System Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                         Neovim                                  │
└─────────────────────────────┬───────────────────────────────────┘
                              │ Lua API
┌─────────────────────────────▼───────────────────────────────────┐
│                      Lua Layer                                  │
│  ┌─────────┐ ┌──────────┐ ┌───────┐ ┌─────────┐ ┌─────────────┐│
│  │  Core   │ │ Resources│ │ Views │ │ Actions │ │   Client    ││
│  └────┬────┘ └────┬─────┘ └───┬───┘ └────┬────┘ └──────┬──────┘│
└───────┼──────────┼────────────┼──────────┼─────────────┼────────┘
        │          │            │          │             │
        └──────────┴────────────┴──────────┴─────────────┘
                              │ FFI (luv async)
┌─────────────────────────────▼───────────────────────────────────┐
│                      Rust Layer                                 │
│  ┌─────────┐ ┌────────────┐ ┌─────┐ ┌─────┐ ┌──────┐ ┌───────┐ │
│  │   Lib   │ │ Processors │ │ DAO │ │ CMD │ │  UI  │ │ Store │ │
│  └────┬────┘ └─────┬──────┘ └──┬──┘ └──┬──┘ └──┬───┘ └───┬───┘ │
└───────┼────────────┼───────────┼───────┼───────┼─────────┼──────┘
        │            │           │       │       │         │
        └────────────┴───────────┴───────┴───────┴─────────┘
                              │ C FFI
┌─────────────────────────────▼───────────────────────────────────┐
│                       Go Layer                                  │
│             ┌──────────────┐ ┌──────────────┐                   │
│             │   Describe   │ │    Drain     │                   │
│             └──────────────┘ └──────────────┘                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Lua Layer (`lua/kubectl/`)

### Sub-layers

| Layer | Path | Responsibility |
|-------|------|----------------|
| **Core** | `*.lua` (root) | Plugin entry, config, state, mappings |
| **Resources** | `resources/` | Kubernetes resource definitions and views |
| **Views** | `views/` | UI components (filter, namespace, portforward) |
| **Actions** | `actions/` | Operations on resources (delete, edit, apply) |
| **Utils** | `utils/` | Shared utilities (formatting, events, tables) |
| **Client** | `client/` | Rust FFI bridge |

### Core Modules

| Module | Responsibility | Allowed Dependencies |
|--------|----------------|----------------------|
| `init.lua` | Plugin entry, commands | config, state, client |
| `config.lua` | User configuration | (none) |
| `state.lua` | Runtime state | config |
| `mappings.lua` | Global keybindings | resources, views, actions |
| `resource_factory.lua` | Builder for resource views | state, utils |
| `resource_manager.lua` | Resource lifecycle | resource_factory |
| `cache.lua` | API resource cache | client |
| `event_queue.lua` | Event polling | client, state |

### Dependency Rules — Lua

```
Core ──────► Utils        ✓ allowed
Core ──────► Client       ✓ allowed
Core ──────► Views        ✓ allowed (init, mappings only)
Core ──────► Resources    ✓ allowed (mappings only)
Core ──────► Actions      ✗ NOT allowed (use mappings indirection)

Resources ─► Core         ✓ allowed (state, config, factory)
Resources ─► Utils        ✓ allowed
Resources ─► Views        ✓ allowed (for sub-views like portforward)
Resources ─► Actions      ✓ allowed
Resources ─► Client       ✗ NOT allowed (use actions)
Resources ─► Resources    ⚠ only base_resource

Views ─────► Core         ✓ allowed (state, config)
Views ─────► Utils        ✓ allowed
Views ─────► Client       ✓ allowed (for data fetching)
Views ─────► Actions      ✓ allowed
Views ─────► Resources    ✗ NOT allowed (circular risk)

Actions ───► Core         ✓ allowed (state)
Actions ───► Utils        ✓ allowed
Actions ───► Client       ✓ allowed
Actions ───► Views        ⚠ only for opening result views
Actions ───► Resources    ✗ NOT allowed

Utils ─────► (anything)   ✗ NOT allowed (must be leaf)
Client ────► (anything)   ✗ NOT allowed (must be leaf)
```

### Resource Pattern

Every resource in `resources/<name>/` MUST have:

```
<resource>/
├── init.lua       # View definition, extends base_resource
└── mappings.lua   # Resource-specific keybindings (optional)
```

**init.lua contract:**
```lua
local BaseResource = require("kubectl.resources.base_resource")

return BaseResource.extend({
  resource = "<name>",           -- REQUIRED: resource identifier
  display_name = "<NAME>",       -- REQUIRED: display name
  ft = "k8s_<name>",             -- REQUIRED: filetype
  gvk = { g = "", v = "", k = "" }, -- REQUIRED: GroupVersionKind
  headers = { ... },             -- REQUIRED: column definitions
  hints = { ... },               -- OPTIONAL: keybinding hints
})
```

---

## Rust Layer (`kubectl-client/src/`)

### Sub-layers

| Layer | Path | Responsibility |
|-------|------|----------------|
| **Lib** | `lib.rs` | FFI exports, Lua bindings |
| **Processors** | `processors/` | Resource-specific data transformation |
| **DAO** | `dao/` | Kubernetes API client |
| **CMD** | `cmd/` | kubectl command wrappers |
| **UI** | `ui/` | View rendering helpers |
| **Store** | `store.rs` | Informer-based resource cache |

### Dependency Rules — Rust

```
lib ────────► (all)         ✓ allowed (entry point)

processors ─► structs       ✓ allowed
processors ─► utils         ✓ allowed
processors ─► dao           ✗ NOT allowed (processors are pure transforms)

dao ────────► (external)    ✓ kube-rs, k8s-openapi
dao ────────► structs       ✓ allowed

cmd ────────► dao           ✓ allowed
cmd ────────► processors    ✓ allowed
cmd ────────► store         ✓ allowed

ui ─────────► processors    ✓ allowed
ui ─────────► structs       ✓ allowed
ui ─────────► dao           ✗ NOT allowed

store ──────► dao           ✓ allowed
store ──────► processors    ✓ allowed
```

### Processor Pattern

Every processor in `processors/` MUST implement:

```rust
pub trait Processor: Send + Sync {
    fn process(&self, resource: &DynamicObject) -> ProcessedRow;
    fn gvk(&self) -> GroupVersionKind;
}
```

**Dispatch via GVK** — no type switches in calling code.

---

## Go Layer (`go/`)

### Responsibility
Specialized kubectl operations not easily replicated in Rust.

### Modules

| Module | Responsibility |
|--------|----------------|
| `kubedescribe.go` | Resource describe output |
| `kubedrain.go` | Node drain operation |

### Constraint
- MUST export C-compatible functions only
- MUST NOT call back into Rust or Lua
- Pure request→response operations

---

## Cross-Layer Rules

### Data Flow Direction

```
User Input → Lua (mappings) → Actions → Client → Rust → [Go] → K8s API
                                                    ↓
User Display ← Lua (views) ← Client ← Rust (processors) ←──────┘
```

### Boundary Contracts

| Boundary | Contract |
|----------|----------|
| Lua → Rust | JSON serialized args, JSON response via callback |
| Rust → Go | C strings, C error codes |
| Rust → K8s | kube-rs client, typed resources |

### State Ownership

| State | Owner | Accessors |
|-------|-------|-----------|
| User config | `config.lua` | read-only everywhere |
| Runtime state | `state.lua` | read everywhere, write via state methods |
| Resource cache | `store.rs` | read via client, write via informer |
| UI state (buffers) | `resource_manager.lua` | views only |

---

## Violations to Watch For

### Critical
- [ ] Utils requiring non-utils (breaks leaf constraint)
- [ ] Resources requiring other resources (except base_resource)
- [ ] Circular dependencies between views and resources
- [ ] Processors accessing DAO directly

### Warning
- [ ] Actions requiring views (should be rare)
- [ ] Core modules requiring resources directly (use mappings)
- [ ] More than 7 imports in any module

---

## Verification Checklist

When verifying architecture health:

1. **Layer boundaries** — Do imports respect the dependency rules?
2. **Pattern conformance** — Do all resources extend base_resource?
3. **State ownership** — Is state only mutated by its owner?
4. **Data flow** — Does data flow in the documented direction?
5. **Leaf modules** — Are utils and client truly dependency-free?
