# kubectl.nvim Code Review Report
**Date:** 2026-01-20
**Reviewed by:** Specialized subagents (rust, lua, logs, lsp, statusline, architecture-verify)

---

## Executive Summary

Six specialized subagents performed comprehensive reviews of their respective areas. The codebase is well-architected overall with excellent patterns in both Rust and Lua layers. However, several issues were identified ranging from critical bugs to architectural improvements.

| Area | Grade | Critical | High | Medium | Low |
|------|-------|----------|------|--------|-----|
| Rust Codebase | B+ | 3 | 2 | 2 | 3 |
| Lua Codebase | 9.2/10 | 1 | 3 | 2 | 2 |
| Pod Logs Feature | - | 2 | 4 | 4 | 6 |
| LSP Features | - | 3 | 2 | 4 | 6 |
| Statusline Feature | - | 1 | 2 | 6 | 4 |
| Architecture | B | 2 | 1 | 0 | 0 |

---

## Table of Contents

1. [Rust Codebase Review](#1-rust-codebase-review)
2. [Lua Codebase Review](#2-lua-codebase-review)
3. [Pod Logs Feature Review](#3-pod-logs-feature-review)
4. [LSP Features Review](#4-lsp-features-review)
5. [Statusline Feature Review](#5-statusline-feature-review)
6. [Architecture Verification](#6-architecture-verification)
7. [Consolidated Action Items](#7-consolidated-action-items)

---

## 1. Rust Codebase Review

**Overall Grade: B+**

The Rust layer is well-engineered with excellent architecture for a Neovim plugin. The use of mlua, tokio patterns, and Kubernetes client library is sophisticated and mostly correct.

### 1.1 Critical Issues

#### 1.1.1 Unsafe `unwrap()` Calls

**Locations:**
- `kubectl-client/src/dao/cronjob.rs:23`
- `kubectl-client/src/cmd/delete.rs:30`
- `kubectl-client/src/processors/node.rs:43,49`
- `kubectl-client/src/processors/pod.rs:361,466`

**Problem:**
```rust
// cronjob.rs:23
let cronjob = cj_api.get(&cronjob_name).await.unwrap();

// delete.rs:30
await_condition(api.clone(), &args.name, is_deleted(&pdel.uid().unwrap()))

// node.rs:43,49
.map(|s| s.node_info.as_ref().unwrap().kubelet_version.clone())
.map(|s| s.node_info.as_ref().unwrap().os_image.clone())
```

**Impact:** Direct `unwrap()` on async Kubernetes API calls will panic if the resource doesn't exist or network fails, causing Neovim to crash.

**Reasoning:** Rust's `unwrap()` is appropriate for cases where failure is impossible or indicates a programming error. In these cases, the failure modes are runtime-dependent (network, missing resources), not programming errors.

**Fix:**
```rust
// Use proper error propagation
let cronjob = cj_api.get(&cronjob_name).await.map_err(LuaError::external)?;

// For uid(), provide context
let uid = pdel.uid().ok_or_else(|| LuaError::external("resource missing UID"))?;

// For node_info, use safe chaining
.map(|s| s.node_info.as_ref().map(|ni| ni.kubelet_version.clone()).unwrap_or_default())
```

---

#### 1.1.2 Error Conversion Issues

**Locations:**
- `kubectl-client/src/processors/secret.rs:27-28`
- `kubectl-client/src/processors/configmap.rs:26-27`
- `kubectl-client/src/processors/serviceaccount.rs:25-26`

**Problem:**
```rust
let secret: Secret =
    from_value(to_value(obj).expect("Failed to convert DynamicObject to JSON Value"))
        .expect("Failed to convert JSON Value into Secret");
```

**Impact:** Double `expect()` will panic on malformed data instead of returning LuaError, causing Neovim crash.

**Reasoning:** The conversion could fail if Kubernetes returns unexpected schema (version skew, CRDs, etc.). Production code should handle these gracefully.

**Fix:**
```rust
let secret: Secret = from_value(to_value(obj).map_err(LuaError::external)?)
    .map_err(LuaError::external)?;
```

---

#### 1.1.3 Sync Function Blocks Neovim Thread

**Location:** `kubectl-client/src/lib.rs:263`

**Problem:**
```rust
fn get_all(_lua: &Lua, json: String) -> LuaResult<String>
```

This is a **sync function** that calls `with_client` which uses `block_on`. This blocks the Neovim main thread.

**Impact:** User-visible UI freeze during Kubernetes API calls.

**Reasoning:** There's already `get_all_async` at line 284, and a TODO comment at line 282 suggests these should be combined. The sync version forces blocking behavior that defeats the purpose of async Rust.

**Fix:** Deprecate the sync version, only expose async functions to Lua.

---

### 1.2 High Priority Issues

#### 1.2.1 Deserialization Without Validation

**Location:** `kubectl-client/src/cmd/delete.rs:15`

**Problem:**
```rust
let args: CmdDeleteArgs = serde_json::from_str(&json).unwrap();
```

**Impact:** Direct `unwrap()` on JSON from Lua. If Lua passes malformed JSON, this panics.

**Fix:**
```rust
let args: CmdDeleteArgs = serde_json::from_str(&json)
    .map_err(|e| mlua::Error::external(format!("invalid JSON: {e}")))?;
```

---

#### 1.2.2 Poisoned Lock Handling Inconsistency

**Problem:** The codebase has two patterns for handling poisoned locks:

**Pattern A (Graceful Recovery):**
```rust
// metrics/pods.rs:292
Err(poisoned) => {
    warn!("poisoned pod_stats lock in collector, recovering");
    poisoned.into_inner().clone()
}
```

**Pattern B (Error Propagation):**
```rust
// lib.rs:96
.map_err(|_| LuaError::RuntimeError("poisoned CLIENT lock".into()))?
```

**Reasoning:** For metrics collectors (read-heavy, non-critical), recovery makes sense. For client instances (critical state), error propagation is safer. The policy should be documented.

---

### 1.3 Medium Priority Issues

#### 1.3.1 String Comparison Performance

**Location:** `kubectl-client/src/sort.rs:29-32`

**Problem:**
```rust
let order = sort_order
    .map(|s| s.trim().to_lowercase())
    .filter(|s| !s.is_empty())
    .unwrap_or_else(|| "asc".to_owned());
// Then multiple string comparisons:
if order == "desc" { ... } else { ... }
```

**Impact:** Allocates new String for every sort operation.

**Fix:**
```rust
enum SortOrder { Asc, Desc }
let order = match sort_order.as_deref() {
    Some("desc") | Some("DESC") => SortOrder::Desc,
    _ => SortOrder::Asc,
};
```

---

### 1.4 Architectural Strengths

1. **Single Runtime Pattern** - Correctly detects if already inside a runtime context and uses `block_in_place`
2. **Reflector Lifecycle Management** - Uses `CancellationToken` for graceful shutdown
3. **Resource Modification in Stream** - Clears `managed_fields` to reduce memory footprint
4. **No Unsafe Blocks** - All FFI handled through safe mlua abstractions
5. **Proper Arc/Mutex Usage** - Correct shared mutable state patterns

---

## 2. Lua Codebase Review

**Overall Grade: 9.2/10**

Excellent patterns, strong defensive programming, and minimal technical debt. The architecture is clean, extensible, and follows Neovim best practices.

### 2.1 Critical Issues

#### 2.1.1 State Initialization Race Condition

**Location:** `lua/kubectl/state.lua:97-107`

**Problem:**
```lua
commands.run_async("get_minified_config_async", {
  ctx_override = M.context["current-context"] or nil,
}, function(data)
  local result = decode(data)
  if result then
    M.context = result
  end
  -- ... continues with cache loading
end)
```

**Impact:** Multiple components may access `state.context` before async initialization completes.

**Reasoning:** The state module is required early in plugin initialization, but the actual context data is loaded asynchronously. Components that depend on this data may get stale/nil values.

**Fix:**
```lua
M.initialized = false
-- ... in callback
M.context = result
M.initialized = true
-- Dependents should check M.initialized or use callback pattern
```

---

### 2.2 High Priority Issues

#### 2.2.1 Buffer State Access Without Nil Check

**Location:** `lua/kubectl/mappings.lua:383-384`

**Problem:**
```lua
local buf_state = state.get_buffer_state(bufnr)
local mark, word = marks.get_current_mark(buf_state.content_row_start, bufnr)
```

**Impact:** No nil check after `get_buffer_state`. If buffer state doesn't exist, accessing `.content_row_start` will fail.

**Fix:**
```lua
local buf_state = state.get_buffer_state(bufnr)
if not buf_state or not buf_state.content_row_start then
  return
end
local mark, word = marks.get_current_mark(buf_state.content_row_start, bufnr)
```

---

#### 2.2.2 Async Callback Missing Buffer Validity Check

**Location:** `lua/kubectl/resource_factory.lua:265-273`

**Problem:**
```lua
commands.run_async("start_reflector_async", { gvk = definition.gvk, namespace = nil }, function(_, err)
  if err then
    return
  end
  vim.schedule(function()
    builder.draw(cancellationToken)
    vim.cmd("doautocmd User K8sDataLoaded")
  end)
end)
```

**Impact:** After async operation, buffer may be deleted before `vim.schedule` callback executes.

**Reasoning:** User can close the buffer while waiting for API response. The scheduled callback will then operate on an invalid buffer.

**Fix:**
```lua
vim.schedule(function()
  if builder.buf_nr and not vim.api.nvim_buf_is_valid(builder.buf_nr) then
    return
  end
  builder.draw(cancellationToken)
  vim.cmd("doautocmd User K8sDataLoaded")
end)
```

---

#### 2.2.3 Picker Registry Memory Leak

**Location:** `lua/kubectl/state.lua:376-396`

**Problem:**
```lua
function M.picker_register(filetype, title, open_func, args)
  -- ... registration logic
  M.buffers[key] = {
    key = key,
    filetype = filetype,
    -- ...
    tab_id = vim.api.nvim_get_current_tabpage(),
  }
end
```

**Impact:** No automatic cleanup when tabs are closed or buffers deleted.

**Fix:**
```lua
vim.api.nvim_create_autocmd("TabClosed", {
  group = "kubectl_session",
  callback = function(args)
    local closed_tab = tonumber(args.file)
    for key, entry in pairs(M.buffers) do
      if entry.tab_id == closed_tab then
        M.picker_remove(key)
      end
    end
  end,
})
```

---

### 2.3 Medium Priority Issues

#### 2.3.1 Mapping Application Order

**Location:** `lua/kubectl/mappings.lua:695-708`

**Problem:** Mappings applied twice if LSP attaches - once immediately, once in LspAttach callback.

**Fix:** Track whether mappings were already applied:
```lua
local applied = {}
local function apply_mappings_once(bufnr, view_name)
  if applied[bufnr] then return end
  apply_mappings(bufnr, view_name)
  applied[bufnr] = true
end
```

---

#### 2.3.2 Inconsistent Error Callback Handling

**Analysis:** Only 7 async callbacks check error parameter. Many `run_async` calls ignore the error parameter, leading to silent failures.

**Recommendation:** Create error handling wrapper:
```lua
function M.run_async_safe(cmd, args, callback)
  M.run_async(cmd, args, function(data, err)
    if err then
      vim.schedule(function()
        vim.notify("kubectl.nvim: " .. cmd .. " failed: " .. err, vim.log.levels.ERROR)
      end)
      return
    end
    callback(data)
  end)
end
```

---

### 2.4 Architectural Strengths

1. **BaseResource Pattern** - Clean inheritance with auto-detection of cluster-scoped resources
2. **Resource Factory Builder** - Fluent API with clear separation of concerns
3. **Consistent Module Structure** - All 101 modules follow `local M = {}` pattern
4. **Strong Defensive Patterns** - Buffer validity checks, pcall usage (113 occurrences)
5. **Comprehensive Type Annotations** - LuaLS annotations throughout

---

## 3. Pod Logs Feature Review

### 3.1 Critical Issues

#### 3.1.1 Syntax Error in Rust Comment

**Location:** `kubectl-client/src/structs.rs:121`

**Problem:**
```rust
/ Force prefix behavior: Some(true) = always, Some(false) = never, None = auto
```

Missing second `/` for comment - should be `//`. This will cause compilation failure.

**Fix:** Change to `// Force prefix behavior...`

---

#### 3.1.2 Resource Leak on Session Stop

**Location:** `lua/kubectl/views/logs/session.lua:84`

**Problem:** When `session:stop()` is called, it removes the session from the manager, but the Rust session cleanup happens via `pcall`. If the `pcall` fails, the manager entry is still removed, leading to orphaned Rust resources.

**Fix:**
```lua
function session:stop()
  if self.stopped then return end
  self.stopped = true

  local cleanup_ok = true
  if self.rust_session then
    cleanup_ok = pcall(function()
      self.rust_session:close()
    end)
    self.rust_session = nil
  end

  if self.timer and not self.timer:is_closing() then
    self.timer:stop()
    self.timer:close()
  end
  self.timer = nil

  -- Only remove if cleanup succeeded
  if cleanup_ok then
    manager.remove(session_key(buf))
  end
end
```

---

#### 3.1.3 Race Condition in Buffer Validation

**Location:** `lua/kubectl/views/logs/session.lua:125-128`

**Problem:** The timer callback checks `vim.api.nvim_buf_is_valid(this.buf)` but then accesses the buffer on line 140-144 without re-checking validity. Buffer could be deleted between the check and use.

**Fix:** Wrap buffer operations in pcall or re-validate just before use.

---

### 3.2 High Priority Issues

#### 3.2.1 Missing Error Context in Log Stream Errors

**Location:** `kubectl-client/src/cmd/log_session.rs:386-388`

**Problem:** Error messages only show pod name but not namespace or container. In multi-pod scenarios with same pod names in different namespaces, this is ambiguous.

**Fix:**
```rust
let _ = log_sender.send(format!(
    "[{}/{}] Error: {}",
    target.pod_name, target.container_name, e
));
```

---

#### 3.2.2 Histogram Timestamp Parsing is Fragile

**Location:** `kubectl-client/src/cmd/log_session.rs:149-164`

**Problem:** The `find_timestamp()` function searches for 'T' character and assumes ISO8601 format, but doesn't validate date components. Could match false positives.

**Example:** Log line `"TESTING 2024T01:02:03Z more text"` might partially match.

---

#### 3.2.3 No Limit on Histogram Bucket Count

**Location:** `kubectl-client/src/cmd/log_session.rs:186`

**Problem:** Minimum check exists (`bucket_count < 12`), but no maximum. A user could set `histogram_width` to an extremely large value.

**Fix:**
```rust
if bucket_count < 12 || bucket_count > 500 {
    return Vec::new();
}
```

---

#### 3.2.4 Silent Pod Failures in Multi-Pod Mode

**Location:** `kubectl-client/src/cmd/log_session.rs:54-56`

**Problem:** When fetching logs from multiple pods, failed pods are silently skipped via `continue`. Users have no indication which pods failed.

**Fix:**
```rust
let mut errors = Vec::new();
for pod_ref in pods {
    match api.get(&pod_ref.name).await {
        Ok(pod) => { /* process */ }
        Err(e) => {
            if is_multi_pod {
                errors.push(format!("{}/{}: {}", pod_ref.namespace, pod_ref.name, e));
                continue;
            }
            // ... existing error return
        }
    }
}
// Log accumulated errors
for err in errors {
    eprintln!("Warning: {}", err);
}
```

---

### 3.3 Medium Priority Issues

- Global options state management (`session.lua:19`)
- Duplicate window validity checks (`session.lua:143`)
- JSON toggle modifies buffer without save check (`pod_logs/mappings.lua:27`)
- No validation of duration string format (`log_session.rs:124-136`)
- Timer memory leak on rapid toggle (`session.lua:112-117`)

---

### 3.4 Performance Concerns

#### 3.4.1 No Backpressure Handling

**Location:** `kubectl-client/src/cmd/log_session.rs:406`

**Problem:** The `log_sender.send(formatted)` uses unbounded channel. If Lua side can't keep up, memory usage could grow unbounded.

---

### 3.5 Positive Observations

1. **RAII Pattern** - `TaskGuard` ensures task count is always decremented
2. **Clean Separation** - Rust handles I/O, Lua handles UI state
3. **Robust Timer Cleanup** - Session cleanup on `BufWinLeave`
4. **Multi-Container Logic** - Prefix handling correctly distinguishes scenarios

---

## 4. LSP Features Review

### 4.1 Critical Issues

#### 4.1.1 LSP Client Never Stopped

**Location:** `lua/kubectl/lsp/init.lua:139-144`

**Problem:**
```lua
function M.stop()
  if M.client_id then
    vim.lsp.stop_client(M.client_id)
    M.client_id = nil
  end
end
```

The `M.stop()` function is defined but **never called** anywhere in the codebase. The LSP client persists even after plugin closes.

**Impact:** Memory leak, LSP client continues running after buffers close.

**Fix:** Call `M.stop()` in cleanup logic or buffer unload autocmd.

---

#### 4.1.2 Diagnostics Disabled by Default Despite Being "Enabled"

**Location:** `lua/kubectl/lsp/diagnostics/init.lua:160-188`

**Problem:**
```lua
local diagnostics_enabled = true  -- Line 160

function M.setup()
  vim.diagnostic.config({
    virtual_text = false,
    virtual_lines = false,  -- Should be { current_line = true }
    signs = true,
    underline = false,
    update_in_insert = false,
  }, ns)
end
```

**Impact:** State mismatch - `diagnostics_enabled = true` but `M.setup()` sets `virtual_lines = false`. Users don't see diagnostics until they manually toggle.

**Fix:** Change line 183 to `virtual_lines = { current_line = true }` to match the enabled state.

---

#### 4.1.3 Emoji Usage in Hover Diagnostics

**Location:** `lua/kubectl/lsp/hover/init.lua:24-26`

**Problem:**
```lua
local icon = diag.severity == vim.diagnostic.severity.ERROR and "🔴"
  or diag.severity == vim.diagnostic.severity.WARN and "🟡"
  or "🔵"
```

**Impact:** Hardcoded emojis violate the project's emoji-free policy, potential terminal compatibility issues.

**Fix:**
```lua
local icon = diag.severity == vim.diagnostic.severity.ERROR and "✗"
  or diag.severity == vim.diagnostic.severity.WARN and "⚠"
  or "ℹ"
```

---

### 4.2 High Priority Issues

#### 4.2.1 Completion Source Registration Race Condition

**Location:** `lua/kubectl/init.lua:19-22`

**Problem:** LSP sources registered synchronously during `init_ui()` but LSP server starts asynchronously on FileType event. If FileType fires before `init_ui()` completes, completion sources won't be registered.

---

#### 4.2.2 Missing Error Propagation in Hover

**Location:** `lua/kubectl/lsp/hover/init.lua:133-169`

**Problem:** Rust errors from `get_hover_async` are silently ignored. If fetch fails, user sees nothing.

**Fix:**
```lua
if not content or content == "" then
  callback(nil, {
    contents = {
      kind = "markdown",
      value = "_Failed to fetch resource details_",
    }
  })
  return
end
```

---

### 4.3 Medium Priority Issues

- Code actions exclude list hard-coded (`code_actions/init.lua:3-12`)
- Stale request cancellation only in hover, not completion (`hover/init.lua:8-10`)
- Buffer validity checks inconsistent across modules
- Diagnostic message building edge case (`diagnostics/init.lua:72-78`)

---

### 4.4 Architectural Strengths

1. **In-process LSP Server** - Clever implementation avoiding subprocess overhead
2. **Filetype-based Source Dispatch** - Clean pattern for completion sources
3. **Async Hover with Rust FFI** - Excellent separation of concerns
4. **vim.schedule() Usage** - Proper event loop handling for UI operations

---

## 5. Statusline Feature Review

### 5.1 Critical Issues

#### 5.1.1 Timer Resource Leak

**Location:** `lua/kubectl/views/statusline/init.lua:16-22`

**Problem:**
```lua
local timer = vim.uv.new_timer()
timer:start(5000, M.interval, function()
  -- Never stopped
end)
```

**Impact:** Timer is created but never stopped or cleaned up. Continues running even if:
- Statusline is disabled mid-session
- User switches context
- Plugin is unloaded

**Evidence:** Other views properly cleanup timers:
- `lua/kubectl/views/logs/session.lua:77-78` - `timer:stop()` + `timer:close()`
- `lua/kubectl/event_queue.lua:50-51` - `timer:stop()` + `timer:close()`

**Fix:**
```lua
-- In View()
builder.timer = timer

-- In Close()
if statusline_builder.timer then
  statusline_builder.timer:stop()
  statusline_builder.timer:close()
  statusline_builder.timer = nil
end
```

---

### 5.2 High Priority Issues

#### 5.2.1 Missing `series.last_observed_time` in Event Timestamp Logic

**Location:** `kubectl-client/src/statusline.rs:62-66`

**Problem:**
```rust
let ts = e
    .event_time
    .as_ref()
    .map(|t| t.0)
    .or_else(|| e.last_timestamp.as_ref().map(|t| t.0));
```

**Impact:** Ignores `series.last_observed_time`, which is the **canonical** timestamp for recurring events. May show stale event counts.

**Correct pattern** (from `kubectl-client/src/processors/event.rs:45-50`):
```rust
let ts = ev.series
    .as_ref()
    .and_then(|s| s.last_observed_time.as_ref().map(|t| t.0))
    .or_else(|| ev.event_time.as_ref().map(|t| t.0))
    .or_else(|| ev.last_timestamp.as_ref().map(|t| t.0))
    .or_else(|| ev.metadata.creation_timestamp.as_ref().map(|t| t.0));
```

---

#### 5.2.2 Missing Error Context on API Failure

**Location:** `kubectl-client/src/lib.rs:369-378`

**Problem:**
```rust
let statusline = match get_statusline(client).await {
    Ok(s) => s,
    Err(_) => return Ok(String::new()),  // Error lost
};
```

**Impact:** No logging for debugging failures. Silent degradation makes troubleshooting difficult.

**Fix:**
```rust
let statusline = match get_statusline(client).await {
    Ok(s) => s,
    Err(e) => {
        tracing::warn!("Failed to get statusline metrics: {}", e);
        return Ok(String::new());
    }
};
```

---

### 5.3 Design Issues

#### 5.3.1 Hardcoded Refresh Interval

**Location:** `lua/kubectl/views/statusline/init.lua:5`

```lua
M.interval = 30000,  -- Not configurable
```

**Problem:** Config type definition only has `enabled` field:
```lua
---@alias StatuslineConfig { enabled: boolean }
```

**Fix:** Add to config:
```lua
---@alias StatuslineConfig { enabled: boolean, interval?: number }
statusline = {
  enabled = false,
  interval = 30000,
}
```

---

#### 5.3.2 CPU/Memory Truncation May Hide Issues

**Location:** `kubectl-client/src/statusline.rs:78-79`

```rust
cpu_pct: (cpu_sum / n) as u16,  // 89.9% becomes 89%
mem_pct: (mem_sum / n) as u16,
```

**Impact:** Truncation from `f64` to `u16` loses precision. A cluster at 89.9% CPU shows as 89%, missing the warning threshold:
```lua
local cpu_ok = (cpu < 90)  -- 89.9% shows green
```

**Fix:**
```rust
cpu_pct: (cpu_sum / n).round() as u16,
mem_pct: (mem_sum / n).round() as u16,
```

---

#### 5.3.3 No Visual Feedback for Stale Data

**Problem:** No indication when:
- Node metrics haven't been collected yet
- Last API call failed
- Data is stale

Current behavior returns default zeros when no data, displaying: `🟢 0/0 │ CPU 0% │ MEM 0% │ EVENTS 0`

This looks like a healthy cluster but actually means "no data".

---

### 5.4 Performance Concerns

#### 5.4.1 Event List Query Performance

**Location:** `kubectl-client/src/statusline.rs:49-73`

**Problem:**
- Lists ALL Warning events in cluster
- Iterates entire list to filter by timestamp
- No limit parameter

**Impact:** On large clusters with many events, causes high API server load every 30 seconds.

---

### 5.5 Positive Observations

1. **Proper Use of Informer Snapshot** - Reads from cached `node_stats()` instead of querying API
2. **Graceful Error Handling in Lua** - Uses pcall for protected calls
3. **Initial Delay Before First Poll** - 5s delay gives time for node collector

---

## 6. Architecture Verification

**Overall Health Score: B (Good)**

### 6.1 Critical Violations

#### 6.1.1 Utils Layer Violates Leaf Constraint

**Rule:** `Utils -> (anything) [NO] NOT allowed (must be leaf)`

**Violations:**
| File | Imports |
|------|---------|
| `utils/tables.lua:2` | `kubectl.actions.highlight` |
| `utils/tables.lua:3` | `kubectl.state` |
| `utils/terminal.lua:1` | `kubectl.actions.buffers` |
| `utils/events.lua:1` | `kubectl.actions.highlight` |
| `utils/grid.lua:1` | `kubectl.actions.highlight` |
| `utils/time.lua:2` | `kubectl.actions.highlight` |
| `utils/url.lua:1` | `kubectl.state` |
| `utils/marks.lua:1` | `kubectl.state` |

**Impact:** Utils modules now depend on state and actions, creating coupling and making them harder to reuse.

**Recommendation:**
- Move `highlight` functionality out of actions or create a dedicated `ui/` utilities module
- Pass state/config as parameters instead of importing directly

---

#### 6.1.2 Core Module Violates Action Dependency Rule

**Rule:** `Core -> Actions [NO] NOT allowed (use mappings indirection)`

**Violations:**
- `lua/kubectl/state.lua:1` → `kubectl.actions.commands`
- `lua/kubectl/client/init.lua:1` → `kubectl.actions.commands`

**Impact:** Creates direct coupling between core state/client and actions layer.

---

### 6.2 Warning Violations

#### 6.2.1 Resources Cross-Require Other Resources

**Rule:** `Resources -> Resources [!!] only base_resource`

**Violations:**
- `containers/init.lua:6` → `kubectl.resources.pods`
- `containers/mappings.lua:3` → `kubectl.resources.pods`
- `pods/mappings.lua:1` → `kubectl.resources.containers`
- `overview/definition.lua:4` → `kubectl.views.nodes.definition`

**Note:** The pods ↔ containers cross-reference in mappings is legitimate for navigation between related resources.

---

### 6.3 Clean Areas

- **Rust Layer:** No violations found
- **Pattern Conformance:** 33/34 resources (97%) use `BaseResource.extend`

---

## 7. Consolidated Action Items

### 7.1 Priority 1: Critical (Must Fix)

| # | Issue | Location | Effort |
|---|-------|----------|--------|
| 1 | Replace `unwrap()` calls with proper error handling | Rust: cronjob, delete, node, pod, secret, configmap, serviceaccount | Medium |
| 2 | Fix timer resource leak in statusline | `statusline/init.lua:16-22` | Small |
| 3 | Add LSP client cleanup | `lsp/init.lua:139-144` | Small |
| 4 | Fix syntax error | `structs.rs:121` | Trivial |
| 5 | Enable diagnostics by default | `diagnostics/init.lua:183` | Trivial |
| 6 | Fix log session resource leak | `session.lua:84` | Small |

### 7.2 Priority 2: High (Should Fix)

| # | Issue | Location | Effort |
|---|-------|----------|--------|
| 7 | Add buffer validity checks in async callbacks | `resource_factory.lua`, `mappings.lua` | Small |
| 8 | Replace emojis with text symbols | `hover/init.lua:24-26` | Trivial |
| 9 | Add `series.last_observed_time` to event logic | `statusline.rs:62-66` | Small |
| 10 | Add error logging for statusline failures | `lib.rs:369-378` | Trivial |
| 11 | Add stale request cancellation to completion | `lsp/init.lua:89-101` | Small |
| 12 | Add max bound for histogram buckets | `log_session.rs:186` | Trivial |
| 13 | Report failed pods in multi-pod mode | `log_session.rs:54-56` | Small |
| 14 | Deprecate sync `get_all` function | `lib.rs:263` | Medium |

### 7.3 Priority 3: Medium (Nice to Have)

| # | Issue | Location | Effort |
|---|-------|----------|--------|
| 15 | Make statusline refresh interval configurable | `statusline/init.lua`, `config.lua` | Small |
| 16 | Add picker registry cleanup on TabClosed | `state.lua:376-396` | Small |
| 17 | Use rounding instead of truncation | `statusline.rs:78-79` | Trivial |
| 18 | Add error hover content for failed fetches | `hover/init.lua:133-169` | Small |
| 19 | Standardize poisoned lock handling | Various Rust files | Medium |
| 20 | Fix state initialization race condition | `state.lua:97-107` | Medium |

### 7.4 Priority 4: Architectural (Future Refactoring)

| # | Issue | Location | Effort |
|---|-------|----------|--------|
| 21 | Refactor utils to be truly leaf modules | `lua/kubectl/utils/` | Large |
| 22 | Remove state.lua dependency on actions.commands | `state.lua`, `client/init.lua` | Large |
| 23 | Document mappings cross-reference pattern | Architecture docs | Small |
| 24 | Add visual feedback for stale statusline data | Lua + Rust statusline | Medium |

---

## Appendix A: Test Scenarios

### Logs Feature
1. Rapid follow toggle - Check for timer leaks
2. Very wide terminal - Test histogram with width > 1000
3. Multi-pod with same names - Verify error messages distinguish namespaces
4. Buffer deleted during stream - Ensure no crashes
5. Invalid duration input (e.g., "5x") - Check user feedback

### LSP Feature
1. Fast typing in filter prompt - Verify no duplicate/stale results
2. Switch contexts - Verify namespace completion updates
3. Hover on unhealthy pod - Verify diagnostic section appends
4. Close buffer during hover fetch - Verify no errors
5. Fresh install - Verify diagnostics show immediately

### Statusline Feature
1. Open/close plugin rapidly - Check timer cleanup
2. Large cluster with many events - Monitor performance
3. Network failure during refresh - Verify graceful degradation
4. Context switch - Verify metrics update

---

## Appendix B: Files Referenced

### Rust Files
- `kubectl-client/src/lib.rs`
- `kubectl-client/src/structs.rs`
- `kubectl-client/src/statusline.rs`
- `kubectl-client/src/sort.rs`
- `kubectl-client/src/dao/cronjob.rs`
- `kubectl-client/src/cmd/delete.rs`
- `kubectl-client/src/cmd/log_session.rs`
- `kubectl-client/src/processors/node.rs`
- `kubectl-client/src/processors/pod.rs`
- `kubectl-client/src/processors/secret.rs`
- `kubectl-client/src/processors/configmap.rs`
- `kubectl-client/src/processors/serviceaccount.rs`
- `kubectl-client/src/processors/event.rs`
- `kubectl-client/src/metrics/nodes.rs`
- `kubectl-client/src/hover/formatters.rs`

### Lua Files
- `lua/kubectl/init.lua`
- `lua/kubectl/state.lua`
- `lua/kubectl/config.lua`
- `lua/kubectl/mappings.lua`
- `lua/kubectl/resource_factory.lua`
- `lua/kubectl/resource_manager.lua`
- `lua/kubectl/client/init.lua`
- `lua/kubectl/views/statusline/init.lua`
- `lua/kubectl/views/logs/session.lua`
- `lua/kubectl/lsp/init.lua`
- `lua/kubectl/lsp/hover/init.lua`
- `lua/kubectl/lsp/diagnostics/init.lua`
- `lua/kubectl/lsp/code_actions/init.lua`
- `lua/kubectl/resources/pods/init.lua`
- `lua/kubectl/resources/pods/mappings.lua`
- `lua/kubectl/resources/containers/init.lua`
- `lua/kubectl/resources/pod_logs/mappings.lua`
- `lua/kubectl/utils/tables.lua`
- `lua/kubectl/utils/terminal.lua`
- `lua/kubectl/utils/events.lua`
- `lua/kubectl/utils/grid.lua`
- `lua/kubectl/utils/time.lua`
- `lua/kubectl/utils/url.lua`
- `lua/kubectl/utils/marks.lua`
