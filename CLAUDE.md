# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Subagent Guides

- **[CLAUDE-RUST.md](./.claude/CLAUDE-RUST.md)** - Rust codebase guidance (dylib constraints, mlua FFI, Tokio runtime)
- **[CLAUDE-LUA.md](./.claude/CLAUDE-LUA.md)** - Lua/Neovim plugin guidance (resource pattern, factory, state management)

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
