# CLAUDE-LSP.md

Guidance for working with the LSP features (completion, hover, diagnostics).

## When to Use This Guide

Consult this guide when working on:
- LSP server configuration or capabilities
- Completion sources for different filetypes
- Hover provider (resource info display)
- Diagnostics (errors/warnings for resources)
- Adding new completion sources or hover formatters

For general Lua/Neovim patterns, see [CLAUDE-LUA.md](./CLAUDE-LUA.md).
For Rust async patterns and mlua FFI, see [CLAUDE-RUST.md](./CLAUDE-RUST.md).

## Architecture Overview

The plugin runs an **in-process LSP server** (no external process). This enables:
- Native completion via `vim.lsp.completion` or external plugins (blink.cmp, nvim-cmp)
- Hover information via `vim.lsp.buf.hover()` (typically `K` key)
- Diagnostics for resource status issues

```
┌─────────────────────────────────────────────────────────────┐
│                        Neovim                               │
│  ┌─────────────────┐      ┌────────────────────────────┐   │
│  │ Plugin Buffers  │◄────►│  kubectl LSP Server        │   │
│  │ (k8s_* types)   │      │  (in-process, lsp/init.lua)│   │
│  └─────────────────┘      └────────────────────────────┘   │
│           │                          │                      │
│           ▼                          ▼                      │
│  ┌─────────────────┐      ┌────────────────────────────┐   │
│  │ Diagnostics     │      │  Handlers:                 │   │
│  │ (virtual_lines) │      │  - completion → sources/*  │   │
│  └─────────────────┘      │  - hover → Rust FFI        │   │
│                           └────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## File Map

| Layer | File | Purpose |
|-------|------|---------|
| Lua | `lua/kubectl/lsp/init.lua` | LSP server, capability negotiation, client management |
| Lua | `lua/kubectl/lsp/hover/init.lua` | Hover handler, diagnostic integration |
| Lua | `lua/kubectl/lsp/diagnostics/init.lua` | Set/toggle diagnostics, quickfix export |
| Lua | `lua/kubectl/lsp/sources/aliases.lua` | Completion for `:Kubectl` (resource names, short names) |
| Lua | `lua/kubectl/lsp/sources/namespaces.lua` | Completion for `:Kubens` |
| Lua | `lua/kubectl/lsp/sources/contexts.lua` | Completion for `:Kubectx` |
| Lua | `lua/kubectl/lsp/sources/filter.lua` | Completion for filter prompt (history) |
| Rust | `kubectl-client/src/hover/mod.rs` | Async hover data fetch |
| Rust | `kubectl-client/src/hover/formatters.rs` | Resource-specific markdown formatters |

## Data Flow

### Completion Flow
```
User types in prompt buffer
        │
        ▼
LSP textDocument/completion request
        │
        ▼
lsp/init.lua:get_completion_items()
        │
        ▼
sources[filetype]() → items[]
        │
        ▼
Return to LSP client (displayed by completion plugin)
```

### Hover Flow
```
User triggers hover (K key)
        │
        ▼
LSP textDocument/hover request
        │
        ▼
lsp/hover/init.lua:get_hover()
        │
        ├─► resource_from_filetype() → resource name
        ├─► get_selection() → name, namespace
        │
        ▼
commands.run_async("get_hover_async", {gvk, namespace, name})
        │
        ▼
Rust: hover/mod.rs → store cache or API fetch
        │
        ▼
Rust: formatters.rs → markdown output
        │
        ▼
Lua: append diagnostic section (if any)
        │
        ▼
Return markdown to Neovim hover window
```

### Diagnostics Flow
```
Resource view drawn (via resource_factory)
        │
        ▼
diagnostics.set_diagnostics(bufnr, resource)
        │
        ▼
Iterate builder.processedData rows
        │
        ├─► Check status/phase/conditions for severity symbols
        ├─► Build message from status, ready, restarts, hint
        │
        ▼
vim.diagnostic.set(ns, bufnr, diagnostics)
        │
        ▼
Displayed via virtual_lines (current line only by default)
```

## LSP Server Implementation

The server is created in `lsp/init.lua:8-49` as a Lua function (not an external process):

```lua
local function server(opts)
  return function(dispatchers)
    local srv = {}

    function srv.request(method, params, callback)
      local handler = handlers[method]
      if handler then
        handler(method, params, callback)
      elseif method == "initialize" then
        callback(nil, { capabilities = capabilities })
      end
      -- ...
    end

    return srv
  end
end
```

**Capabilities declared** (line 76-80):
- `completionProvider` with trigger characters `:`, `-`
- `hoverProvider = true`

**Client reuse:** Same client attached to all `k8s_*` buffers via `reuse_client` (line 69-71).

## Completion Sources

Each source follows the pattern:

```lua
local M = {}

function M.get_items()
  local items = {}
  -- Build completion items
  return items
end

function M.register()
  require("kubectl.lsp").register_source("k8s_<filetype>", M.get_items)
end

return M
```

**Completion item fields:**
- `label` - Display text
- `labelDetails.description` - Secondary info (kind name, etc.)
- `insertText` - Text to insert (if different from label)
- `documentation` - Hover docs for item
- `kind_name` / `kind_icon` - Custom kind display

**Registered sources:**

| Filetype | Source | Items |
|----------|--------|-------|
| `k8s_aliases` | `sources/aliases.lua` | API resources, short names, custom views |
| `k8s_namespaces` | `sources/namespaces.lua` | Namespace names |
| `k8s_contexts` | `sources/contexts.lua` | Kubernetes context names |
| `k8s_filter` | `sources/filter.lua` | Filter history entries |

## Hover Provider

`lsp/hover/init.lua` handles `textDocument/hover`:

1. **Filetype check** (`resource_from_filetype`) - Skips non-resource views (filter, namespaces, yaml, describe)
2. **Selection extraction** (`get_selection`) - Gets name/namespace using column positions from definition
3. **Async fetch** - Calls Rust `get_hover_async` with GVK and identifiers
4. **Diagnostic append** (`get_diagnostic_section`) - Adds diagnostics for current line if any

### Rust Hover Formatters

`hover/formatters.rs` has resource-specific formatters for 15 resource types:

| Resource | Formatter | Key Info Shown |
|----------|-----------|----------------|
| Pod | `format_pod` | Phase, node, IP, containers (state, ready, restarts), conditions |
| Deployment | `format_deployment` | Replicas, strategy, images, selector, conditions |
| StatefulSet | `format_statefulset` | Replicas, service name, conditions |
| DaemonSet | `format_daemonset` | Desired/current/ready counts, conditions |
| Job | `format_job` | Completions, active, failed, duration |
| Service | `format_service` | Type, ClusterIP, ports, selector |
| ConfigMap/Secret | `format_configmap/secret` | Key count, key names |
| PVC/PV | `format_pvc/pv` | Phase, capacity, access modes, storage class |
| Node | `format_node` | Addresses, conditions, schedulability |
| _other_ | `format_generic` | Labels, owner, age |

**Output format:** Markdown with `##` headers, `**bold**` labels, `` `code` `` for values.

## Diagnostics

`lsp/diagnostics/init.lua` provides Kubernetes-aware diagnostics:

**Severity detection** (line 10-11):
```lua
local error_symbols = { KubectlError = vim.diagnostic.severity.ERROR }
local warning_symbols = { KubectlWarning = vim.diagnostic.severity.WARN }
```

These symbols come from Rust processors (`status.symbol` field).

**Message building** (`get_message`, line 49-99):
- Status value with hint from Rust (if unhealthy)
- Ready count (if not all ready)
- Restart count with context
- Age (for errors only)

**Display config** (line 176-184):
```lua
vim.diagnostic.config({
  virtual_text = false,
  virtual_lines = { current_line = true },  -- Only show on current line
  signs = true,
  underline = false,
})
```

**Public API:**
- `M.set_diagnostics(bufnr, resource)` - Called after view draw
- `M.toggle()` - Enable/disable virtual_lines display
- `M.to_quickfix()` - Export to quickfix list

## Common Tasks

### Adding a New Completion Source

1. Create `lua/kubectl/lsp/sources/<name>.lua`:
```lua
local M = {}

function M.get_items()
  local items = {}
  -- Fetch data and build items
  table.insert(items, {
    label = "item-name",
    kind_name = "KindName",
    kind_icon = "󰘧",
  })
  return items
end

function M.register()
  require("kubectl.lsp").register_source("k8s_<filetype>", M.get_items)
end

return M
```

2. Register in plugin initialization (typically in `init.lua` setup)

### Adding Hover for New Resource Type

1. Add case in `hover/formatters.rs:format_resource()`:
```rust
"myresource" | "myresources" => format_myresource(obj),
```

2. Implement formatter function following existing patterns:
```rust
fn format_myresource(obj: &DynamicObject) -> String {
    let Ok(res) = from_value::<MyResource>(to_value(obj).unwrap_or_default()) else {
        return format_generic("MyResource", obj);
    };
    // Build markdown lines...
}
```

### Adding Diagnostic Severity

1. Add symbol mapping in `diagnostics/init.lua`:
```lua
local error_symbols = { KubectlError = ..., MyNewErrorSymbol = ... }
```

2. Ensure Rust processor sets `status.symbol` to match

### Extending Diagnostic Message

Modify `get_message()` in `diagnostics/init.lua` to include new fields:
```lua
if row.my_field then
  local val = get_value(row.my_field)
  if val ~= "" then
    table.insert(parts, string.format("My Field: %s", val))
  end
end
```

## Testing

Manual testing via:
```bash
nvim -u repro.lua
```

Then:
- Open `:Kubectl pods` - verify diagnostics appear on unhealthy pods
- Press `K` on a pod row - verify hover shows resource info
- Open `:Kubectl` and type - verify completion shows resources
- Open `:Kubens` and type - verify namespace completion

## Key Patterns

1. **In-process LSP** - No subprocess, server is a Lua table with request/notify methods
2. **Filetype-based sources** - `sources[filetype]()` pattern for completion dispatch
3. **Async hover** - Rust fetch with `vim.schedule` callback for UI safety
4. **Symbol-based severity** - Rust processors set `symbol` field, Lua maps to severity
5. **Virtual lines** - Diagnostics shown inline only on current line to reduce noise
