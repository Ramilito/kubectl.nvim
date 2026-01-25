# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Subagents

This project uses Claude Code subagents (`.claude/agents/`). **You MUST use them.**

### Rule 1: ALWAYS Plan First

For ANY non-trivial task, invoke the `plan` subagent FIRST before doing anything else.
- Trivial = single obvious edit, typo fix, or direct question
- Everything else = use `plan` first

### Rule 2: ALWAYS Use Domain Subagents

When a task touches a domain, use that subagent. No exceptions.

| Domain | Subagent | Trigger |
|--------|----------|---------|
| Rust code | `rust` | ANY task involving `kubectl-client/`, telemetry, Tokio, mlua, Go FFI |
| Lua code | `lua` | ANY task involving `lua/kubectl/`, Neovim API, plugin code |
| Keymappings | `keymappings` | ANY task involving adding, modifying, or removing keybindings |
| Pod logs | `logs` | ANY task involving log streaming, LogSession, histogram |
| LSP | `lsp` | ANY task involving completion, hover, diagnostics |
| Statusline | `statusline` | ANY task involving statusline metrics or display |
| Lineage | `lineage` | ANY task involving resource lineage, relationship graphs, owner references |

### Rule 3: Use Verification Subagents

| Subagent | When |
|----------|------|
| `code-review` | After writing/editing code, before commits |
| `architecture-verify` | To check dependency rules and patterns |

### Reference Subagents (read-only)

| Subagent | Purpose |
|----------|---------|
| `clean-code` | Clean code principles and patterns |
| `architecture` | Architecture contract and dependency rules |

## Project Overview

kubectl.nvim is a Neovim plugin that provides a vim-like interface for browsing and managing Kubernetes clusters. It renders kubectl output in interactive buffers with hierarchical navigation, colors, sorting, and contextual actions.

**Multi-language architecture:**
- **Lua** (`lua/kubectl/`) - Plugin UI, keybindings, state management, Neovim integration
- **Rust** (`kubectl-client/`) - Performance-critical Kubernetes client, resource processing, metrics
- **Go** (`go/`) - Specialized kubectl operations compiled as C archive and linked into Rust

## Build Commands

```bash
# Lint and format Lua code
make llscheck      # Type checking via lua-language-server
make luacheck      # Lint Lua code
make stylua        # Check Lua formatting
make check         # Run all above checks

# Build the Rust/Go native library
make build         # Release build (no telemetry)
make build_release # Release build with telemetry
make build_dev     # Debug build with telemetry
make build_go      # Build Go static library only
make clean         # Remove build artifacts
```

**Requirements:**
- Rust nightly toolchain for building from source
- Go 1.24.0+
- luacheck, stylua, llscheck for Lua linting

## Testing

No automated test suite. Manual testing via minimal reproduction setup:
```bash
nvim -u repro.lua
```

## Architecture

### Lua Layer (`lua/kubectl/`)

**Core modules:**
- `init.lua` - Plugin entry, commands (`:Kubectl`, `:Kubens`, `:Kubectx`), setup
- `config.lua` - Configuration defaults
- `state.lua` - Runtime state, session persistence
- `resource_factory.lua` - Builder pattern for resource views with fluent API

**Resource pattern:** Each Kubernetes resource in `lua/kubectl/resources/` follows:
- `init.lua` - View definition (View, Draw, Desc functions)
- `definition.lua` - Data structure with GVK, headers, hints
- `mappings.lua` - Resource-specific keybindings

**Views:** UI components in `lua/kubectl/views/` (filter, namespace selector, portforward manager, etc.)

**File types:** Plugin creates `k8s_*` filetypes (e.g., `k8s_pods`, `k8s_deployments`) for buffer identification.

### Rust Layer (`kubectl-client/src/`)

**Key patterns:**
- **Processor trait** (`processors/`) - Polymorphic handling for 28+ resource types, dispatched via GVK
- **Informer pattern** (`store.rs`) - Efficient delta updates using resourceVersion
- **Tokio runtime** - Singleton async runtime bridged to Lua via block-on pattern
- **mlua FFI** - Lua bindings with LuaJIT, async, serialize support

**Commands:** `cmd/` contains kubectl operation wrappers (get, apply, delete, exec, portforward, etc.)

### Go FFI Bridge (`go/`)

Minimal C-compatible exports for specialized kubectl operations (describe, drain). Compiled as static library and linked into Rust.

## Key Commands

```vim
:Kubectl [get <resource>|diff|apply|top|api-resources] [args...]
:Kubens [namespace]
:Kubectx [context]
```

## User Events

- `K8sResourceSelected` - Resource selected in view
- `K8sContextChanged` - Kubernetes context switched
- `K8sCacheLoaded` - API resources cache loaded

## Denied Commands

Do NOT run these commands:
- `make build` - Takes too long, use `make build_dev` instead

## Token Efficiency Rules

Follow these rules to minimize token usage:

**Before starting work:**
1. **Use the `plan` subagent** for any refactoring or pattern-following task
2. Ask clarifying questions FIRST if the task involves patterns you need to understand
3. Request the user paste relevant code snippets instead of exploring broadly
4. For refactoring tasks, read ONLY the file being changed + ONE example of the target pattern

**Planning:**
1. Do NOT use TodoWrite for tasks with fewer than 4 steps
2. Do NOT use Task/Explore agent when you can identify the specific file to read
3. Plan the full approach before any edits - avoid creating files you'll delete

**Editing:**
1. Batch related changes into single Edit calls (aim for 1-3 edits per file)
2. Do NOT read files after editing just to verify - the Edit tool shows the result
3. Run `make check` only ONCE at the end, not after each change

**Reading:**
1. Use `offset` and `limit` parameters - don't read 500+ line files fully
2. Use Grep with `-A`/`-B` context instead of reading entire files
3. One good example file is enough - don't read 5 similar files to understand a pattern
