---
name: logs
description: Pod logs feature specialist. ALWAYS use for ANY task involving log streaming, tailing, JSON toggle, histogram, or LogSession.
tools: Read, Grep, Glob, Edit, Write, Bash
model: sonnet
---

# Pod Logs Feature Guidance

**ALWAYS use this subagent** for ANY task involving:
- Log streaming, tailing, or fetching
- JSON expand/collapse in log output
- Log view keybindings or syntax highlighting
- Histogram visualization
- `LogSession` UserData or related mlua bindings

For general mlua FFI patterns (async functions, JSON serialization, error handling), use the `rust` subagent.

## File Map

| Layer | File | Purpose |
|-------|------|---------|
| Rust | `kubectl-client/src/cmd/log_session.rs` | Streaming session, histogram, log fetching, `toggle_json()` |
| Rust | `kubectl-client/src/cmd/mod.rs:124-128` | Registers `log_stream_async` and `log_session` exports |
| Rust | `kubectl-client/src/lib.rs:474-488` | Exposes `toggle_json` to Lua |
| Rust | `kubectl-client/src/structs.rs` | `LogConfig`/`PodRef` structs + custom `FromLua` impl |
| Lua | `lua/kubectl/client/init.lua` | `client.log_session()` / `client.toggle_json()` wrappers |
| Lua | `lua/kubectl/client/types.lua` | `kubectl.LogSession` / `kubectl.ToggleJsonResult` annotations |
| Lua | `lua/kubectl/resources/pods/init.lua` | Entry points: `Logs()`, `TailLogs()`, `LogsWithPods()`, `get_pods_for_logs()` |
| Lua | `lua/kubectl/views/logs/session.lua` | Session manager: options, timer polling, lifecycle |
| Lua | `lua/kubectl/resources/pod_logs/mappings.lua` | Keybindings only — **no sibling `init.lua`/`definition.lua`** |
| Vim | `syntax/k8s_pod_logs.vim` | Syntax highlighting |

`pod_logs` is not a `BaseResource.extend` module. Its view is assembled ad hoc inside `pods/init.lua`'s `LogsWithPods()` (a framed buffer built via `resource_factory`'s `view_framed`), and its mappings are loaded generically from the `k8s_pod_logs` filetype (strip `k8s_` prefix → require `kubectl.resources.pod_logs.mappings`).

## Data Flow

Two distinct code paths share one pod-list resolver but differ in transport:

```
Lua                                Transport                           Rust (dylib)
-------------------------------------------------------------------------------------------
Logs() / LogsWithPods()      --> commands.run_async               --> fetch_logs_async
  one-shot, full buffer            (libuv worker thread,                (async fn) resolves
  replace via buffers.set_content  args JSON-encoded)                   targets, merges streams,
                                                                         renders histogram

TailLogs() / session:start() --> client.log_session                --> log_session
  follow, incremental append       (direct sync FFI call, blocks         (sync fn) LogConfig via
                              --> views/logs/session.lua timer          custom FromLua, spawns one
                                  (vim.uv.new_timer, 200ms) polls        Tokio task per container
                                  session:read_chunk(), appends lines    into a shared LogSession

toggle_json() -----------------------------------------------------> cmd::log_session::toggle_json
```

**Pod-list resolution** (`get_pods_for_logs()` in `pods/init.lua`, shared by both paths, in priority order):
1. Buffer-local vars `kubectl_log_pods`/`kubectl_log_display` — used when already inside a `k8s_pod_logs` buffer (option toggles, refresh).
2. Tab multi-selections — `state.getSelections(bufnr)` (populated by the generic `<Plug>(kubectl.tab)` mapping, not logs-specific).
3. Single selection fallback — `M.selection.pod`/`M.selection.ns` on the `pods` module.

## Rust: LogSession UserData

`LogSession` wraps a generic `StreamingSession<String>` (`kubectl-client/src/streaming.rs`) and exposes it to Lua as a stateful object:

```rust
impl UserData for LogSession {
    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method("read_chunk", |_, this, ()| this.read_chunk());
        methods.add_method("open", |_, this, ()| Ok(this.is_open()));
        methods.add_method("close", |_, this, ()| {
            this.close();
            Ok(())
        });
    }
}
```

**Interior mutability:** `StreamingSession` holds `Mutex<mpsc::UnboundedReceiver<String>>` plus `Arc<AtomicBool>`/`Arc<AtomicUsize>`, since UserData methods receive `&self`.

**Struct-from-table conversion:** `LogConfig`'s custom `FromLua` impl (`structs.rs`) is the reference pattern for turning a nested array-of-tables field (`pods: Vec<mlua::Table>` → `Vec<PodRef>`) into a typed struct — use it as the template when a new FFI config needs a list-of-tables field.

## Rust: toggle_json Return Pattern

Returns table or nil based on `Option<T>`. See `lib.rs:474-488`:

```rust
match cmd::log_session::toggle_json(&input) {
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

## Lua: Session Manager (`views/logs/session.lua`)

Owns per-buffer session objects plus module-level `global_options` (since/prefix/timestamps/previous — shared across *all* log buffers, not per-buffer). Public API: `get_or_create(buf, win, options)`, `get(buf)`, `stop(buf)`, `stop_all()`, `is_active(buf)`, `get_options()`/`set_options()`/`reset_options()`.

**Creating/starting:** `session:start(pods, container)` calls `client.log_session()` (`client/init.lua:111-113`) synchronously — a direct FFI call, not offloaded to a worker thread — with `follow = true`.

**Polling loop:** `session:start()` also creates a `vim.uv.new_timer()` at a 200ms interval; each tick calls `rust_session:read_chunk()` and appends any returned lines to the buffer via `nvim_buf_set_lines`.

**Cleanup (`session:stop()`):** closes the Rust session, stops/closes the timer, removes the manager entry. Triggered by: the manual `f` toggle, self-detection when `session:is_active()` goes false, or a `BufWinLeave` autocmd registered per-session when the session starts.

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

## Durable Quirks & Invariants

- **Container selection is global, not tied to the pod list.** `M.selection.container` lives on the `pods` module (set via `pods.selectPod`), independent of the multi-pod array built by `get_pods_for_logs()`. The pods-view `gl` mapping resets it to `nil` on every press — any new entry point that jumps into `Logs()` must do the same or it will carry over a stale container filter.
- **Log options are one global table, not per-buffer.** `views/logs/session.lua`'s `global_options` is module-level and shared by every log buffer — changing prefix/timestamps/since/previous in one log view changes the default for the next one too.
- **`LogConfig` is deserialized two different ways.** The sync follow path (`client.log_session`) goes through `LogConfig`'s custom `FromLua` impl (direct Lua table → struct, no JSON). The async one-shot path (`log_stream_async` → `fetch_logs_async`) JSON-encodes the args in Lua and does `serde_json::from_str::<LogConfig>` in Rust. Keep both conversions in sync when adding a field.
- **Any option toggle drops follow mode.** `LogsWithPods()` unconditionally stops the active session for the current buffer before doing a one-shot fetch, so toggling prefix/timestamps/history/previous while following stops streaming; the user has to press `f` again to resume.
- **Histogram is one-shot only.** It's computed solely inside `fetch_logs_async`/`render_histogram` from timestamps found in line text — follow mode never recomputes it, and it renders nothing if no line contains a parseable ISO-8601 timestamp.
- **Teardown relies on the WinClosed → BufWinLeave chain.** Session cleanup is wired to a `BufWinLeave` autocmd on the log buffer; that fires because closing the framed view's main pane cascades to close its other windows, and pane buffers are `bufhidden=wipe`. Any new teardown path should go through (or explicitly call) `session:stop()` / `log_session.stop()` rather than assume buffer deletion alone triggers cleanup.

## Common Tasks

### Adding a Log Option

1. Add the default in `views/logs/session.lua`'s `get_default_options()` (and `config.options.logs` in `lua/kubectl/config.lua` if it should be user-configurable).
2. Add a hint in `pods/init.lua`'s `LogsWithPods()` hints array.
3. Add a keybinding + toggle callback in `pod_logs/mappings.lua` (call `update_option()` then `pod_view.Logs()`).
4. If Rust processing is needed: add the field to `LogConfig` (`structs.rs`) and handle it in both `fetch_logs_async` and `LogSession::new` (`log_session.rs`).

### Adding Syntax Pattern

In `syntax/k8s_pod_logs.vim`:
```vim
syn match kubectlLogNewPattern /regex/
hi def link kubectlLogNewPattern HighlightGroup
```

### Adding LogSession Method

1. Add method in `log_session.rs` UserData impl
2. Update type in `types.lua`
