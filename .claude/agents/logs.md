---
name: logs
description: Pod logs feature specialist. Use when working on log streaming, tailing, JSON expand/collapse, histogram visualization, or LogSession UserData bindings.
tools: Read, Grep, Glob, Edit, Write, Bash
model: sonnet
---

# Pod Logs Feature Guidance

Guidance for working with the pod logs view feature.

## When to Use This Subagent

Work on:
- Log streaming, tailing, or fetching
- JSON expand/collapse in log output
- Log view keybindings or syntax highlighting
- Histogram visualization
- `LogSession` UserData or related mlua bindings

For general mlua FFI patterns (async functions, JSON serialization, error handling), use the `rust` subagent.

## File Map

| Layer | File | Purpose |
|-------|------|---------|
| Rust | `kubectl-client/src/cmd/log_session.rs` | Streaming session, histogram, log fetching |
| Rust | `kubectl-client/src/cmd/mod.rs:91-94` | Registers exports |
| Rust | `kubectl-client/src/utils.rs:65-113` | `toggle_json()` utility |
| Rust | `kubectl-client/src/lib.rs:474-488` | Exposes `toggle_json` to Lua |
| Lua | `lua/kubectl/client/init.lua:86-88` | Client wrapper |
| Lua | `lua/kubectl/client/types.lua:8-46` | Type definitions |
| Lua | `lua/kubectl/resources/pods/init.lua:69-284` | Session lifecycle |
| Lua | `lua/kubectl/resources/pod_logs/mappings.lua` | Keybindings |
| Vim | `syntax/k8s_pod_logs.vim` | Syntax highlighting |

## Data Flow

```
Lua                              Rust (dylib)
-----------------------------------------------------------
Logs() --> log_stream_async ---> One-shot fetch + histogram
TailLogs() --> log_session ----> LogSession (streaming)
toggle_json() -----------------> JSON expand/collapse
```

## Rust: LogSession UserData

`LogSession` exposes a streaming session to Lua as a stateful object. See `log_session.rs:339-348`:

```rust
impl UserData for LogSession {
    fn add_methods<M: UserDataMethods<Self>>(m: &mut M) {
        m.add_method("read_chunk", |_, this, ()| Ok(this.read_chunk()?));
        m.add_method("open", |_, this, ()| Ok(this.is_open()));
        m.add_method("close", |_, this, ()| {
            this.close();
            Ok(())
        });
    }
}
```

**Interior mutability:** Session state uses `Mutex<mpsc::Receiver>` and `Arc<AtomicBool>` since UserData methods receive `&self`.

**Multi-argument function:** `log_session()` at line 357 demonstrates receiving multiple Lua values including `Vec<mlua::Table>` for pod list.

## Rust: toggle_json Return Pattern

Returns table or nil based on `Option<T>`. See `lib.rs:474-488`:

```rust
match utils::toggle_json(&input) {
    Some(result) => {
        let tbl = lua.create_table()?;
        tbl.set("json", result.json)?;
        tbl.set("start_idx", result.start_idx)?;  // 1-based for Lua
        tbl.set("end_idx", result.end_idx)?;
        Ok(mlua::Value::Table(tbl))
    }
    None => Ok(mlua::Value::Nil),
}
```

## Lua: Session Lifecycle

**Creating session:** `pods/init.lua:261-275` - Call `client.log_session()` with pod list, options.

**Polling loop:** `pods/init.lua:96-175` - Uses `vim.uv.new_timer()` at 200ms interval, calls `session:read_chunk()`, appends to buffer.

**Cleanup:** Stops timer, closes session on buffer close or when `session:open()` returns false.

## Type Definitions

```lua
--- @class kubectl.LogSession
--- @field open fun(self: kubectl.LogSession): boolean
--- @field close fun(self: kubectl.LogSession)
--- @field read_chunk fun(self: kubectl.LogSession): string[]?

--- @class kubectl.ToggleJsonResult
--- @field json string
--- @field start_idx integer  -- 1-based
--- @field end_idx integer    -- 1-based
```

## Keybindings

| Key | Plug | Action |
|-----|------|--------|
| `f` | `<Plug>(kubectl.follow)` | Toggle follow mode |
| `gw` | `<Plug>(kubectl.wrap)` | Toggle line wrap |
| `gp` | `<Plug>(kubectl.prefix)` | Toggle pod prefix |
| `gt` | `<Plug>(kubectl.timestamps)` | Toggle timestamps |
| `gh` | `<Plug>(kubectl.history)` | Set since duration |
| `gpp` | `<Plug>(kubectl.previous_logs)` | Previous container logs |
| `gj` | `<Plug>(kubectl.expand_json)` | Expand/collapse JSON |

## Syntax Highlighting

Defined in `syntax/k8s_pod_logs.vim`. Key patterns:

| Pattern | Group | Matches |
|---------|-------|---------|
| `kubectlLogContainer` | `KubectlPending` | `[pod-name]` prefix |
| `kubectlLogTimestamp` | `KubectlGray` | ISO timestamps |
| `kubectlLogError` | `KubectlError` | ERROR, FATAL, PANIC |
| `kubectlLogWarn` | `KubectlWarning` | WARN, WARNING |

Uses `syn sync minlines=100` for performance on large buffers.

## Common Tasks

### Adding a Log Option

1. Add state in `pods/init.lua` M.log table
2. Add hint in `M.Logs()` hints array
3. Add keybinding in `pod_logs/mappings.lua`
4. If Rust processing needed: add to `CmdStreamArgs` and `log_stream_async`

### Adding Syntax Pattern

In `syntax/k8s_pod_logs.vim`:
```vim
syn match kubectlLogNewPattern /regex/
hi def link kubectlLogNewPattern HighlightGroup
```

### Adding LogSession Method

1. Add method in `log_session.rs` UserData impl
2. Update type in `types.lua`
