# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Subagent Guides

- **[CLAUDE-PLAN.md](./.claude/CLAUDE-PLAN.md)** - **INVOKE FIRST** for refactoring/pattern-following tasks. Plans minimal approach before any tool calls.
- **[CLAUDE-RUST.md](./.claude/CLAUDE-RUST.md)** - Rust codebase guidance (dylib constraints, mlua FFI, Tokio runtime)
- **[CLAUDE-LUA.md](./.claude/CLAUDE-LUA.md)** - Lua/Neovim plugin guidance (resource pattern, factory, state management)
- **[CLAUDE-LOGS.md](./.claude/CLAUDE-LOGS.md)** - Pod logs feature (streaming, JSON toggle, histogram, mlua UserData)
- **[CLAUDE-CODE-REVIEW.md](./.claude/CLAUDE-CODE-REVIEW.md)** - Targeted code review (post-edit, pre-commit, module modes)
- **[CLAUDE-ARCHITECTURE-VERIFY.md](./.claude/CLAUDE-ARCHITECTURE-VERIFY.md)** - Architecture verification (dependency rules, pattern conformance)

### Reference Documents

- **[CLAUDE-CLEAN-CODE.md](./.claude/CLAUDE-CLEAN-CODE.md)** - Clean code principles (cognitive load, readability, function design)
- **[ARCHITECTURE.md](./.claude/ARCHITECTURE.md)** - Architecture contract (layers, boundaries, dependency rules)

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
1. **INVOKE [CLAUDE-PLAN.md](./.claude/CLAUDE-PLAN.md)** for any refactoring or pattern-following task
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
