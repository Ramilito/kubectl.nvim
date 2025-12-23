# CLAUDE-RUST.md

Guidance for working with the Rust codebase (`kubectl-client/`).

## Context: Neovim Plugin Dylib

This is a **cdylib** loaded by Neovim via the mlua Lua FFI. This context imposes critical constraints:

### Runtime Constraints

**Single Tokio Runtime:** A singleton `OnceLock<Runtime>` manages all async operations. Never create additional runtimes.

**Blocking Bridge:** Lua calls are synchronous. Use `block_on()` to bridge async Rust to sync Lua:
```rust
fn block_on<F: std::future::Future>(fut: F) -> F::Output {
    match Handle::try_current() {
        Ok(h) => task::block_in_place(|| h.block_on(fut)),
        Err(_) => {
            let rt = RUNTIME.get_or_init(|| Runtime::new().expect("tokio runtime"));
            rt.block_on(fut)
        }
    }
}
```

**Client Lifecycle:** Kubernetes clients are stored in global `Mutex<Option<Client>>`. Use `with_client()` helper for safe access:
```rust
pub fn with_client<F, Fut, R>(f: F) -> LuaResult<R>
where
    F: FnOnce(Client) -> Fut,
    Fut: Future<Output = LuaResult<R>>,
{
    let client = CLIENT_INSTANCE.lock()...;
    block_on(f(client))
}
```

### mlua FFI Patterns

**Module Export:** The `#[mlua::lua_module(skip_memory_check)]` attribute exports the module. All public functions must be registered in the exports table:
```rust
exports.set("function_name", lua.create_function(function_name)?)?;
exports.set("async_function", lua.create_async_function(async_function)?)?;
```

**Async Functions:** Use `lua.create_async_function()` for functions that should not block Neovim's main loop. These functions take `Lua` by value (not reference).

**JSON Serialization:** Arguments from Lua come as JSON strings. Parse with serde_json and return JSON strings:
```rust
fn get_all(lua: &Lua, json: String) -> LuaResult<String> {
    let args: GetAllArgs = serde_json::from_str(&json).unwrap();
    // ... process ...
    serde_json::to_string(&result).map_err(|e| mlua::Error::RuntimeError(e.to_string()))
}
```

### Architecture

**Processor Pattern:** Each Kubernetes resource type has a processor in `processors/`. Dispatch via GVK:
```rust
let proc = processor_for(&args.gvk.k.to_lowercase());
proc.process(&lua, &cached, sort_by, sort_order, filter, filter_label, filter_key)
```

**Store/Informer:** `store.rs` implements Kubernetes informer pattern for efficient delta updates. Resources are cached and watched via resourceVersion.

**Metrics Collectors:** Background tasks (`spawn_pod_collector`, `spawn_node_collector`) run on the Tokio runtime. Shut down properly via `shutdown_*_collector()`.

### Go FFI Integration

Go code in `/go/` is compiled as a C archive (`libkubectl_go.a`) and linked into Rust. Used for specialized kubectl operations (describe, drain) that are complex to reimplement.

### Build Notes

- **crate-type:** `["cdylib"]` - produces `.so`/`.dylib`/`.dll`
- **LTO enabled:** Fat LTO, single codegen unit, symbols stripped for size
- **Target:** LuaJIT compatibility required (mlua features: `luajit`)
- **Cross-compilation:** Uses `cross-rs` for linux-musl, darwin, windows targets

### Dependencies

Key crates:
- `kube` + `k8s-openapi` - Kubernetes client
- `mlua` - Lua FFI with `module`, `luajit`, `serialize`, `async` features
- `tokio` - Async runtime (full features)
- `ratatui` + `crossterm` - TUI for dashboard views

### Error Handling

Always convert errors to `LuaError` for proper propagation:
```rust
.map_err(|e| mlua::Error::RuntimeError(e.to_string()))?
.map_err(LuaError::external)?
```

### Tracing

Use `#[tracing::instrument]` on exported functions. Logging configured via telemetry feature or fallback logger.
