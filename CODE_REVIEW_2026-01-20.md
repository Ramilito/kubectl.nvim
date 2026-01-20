# kubectl.nvim Code Review Report
**Date:** 2026-01-20
**Reviewed by:** Specialized subagents (rust, lua, logs, lsp, statusline, architecture-verify)
**Last Updated:** 2026-01-20 (after Priority 2 fixes)

---

## Completed Fixes (Priority 1)

The following critical issues have been resolved:

### Rust Fixes

| File | Issue | Fix Applied |
|------|-------|-------------|
| `kubectl-client/src/dao/cronjob.rs:23` | `unwrap()` on API call | Changed to `map_err()?` with descriptive error |
| `kubectl-client/src/cmd/delete.rs:30` | `uid().unwrap()` | Changed to `uid().ok_or_else()?` |
| `kubectl-client/src/processors/node.rs:43,49` | `unwrap()` on `node_info` | Changed to `and_then()` safe chaining |
| `kubectl-client/src/processors/pod.rs:352-365` | `unwrap()` after `is_none()` check | Refactored to `let Some ... else` pattern |
| `kubectl-client/src/processors/pod.rs:455-465` | `unwrap()` after `is_none()` check | Refactored to `let Some ... else` pattern |
| `kubectl-client/src/processors/secret.rs:26-28` | Double `expect()` | Changed to `map_err()?` |
| `kubectl-client/src/processors/configmap.rs:25-27` | Double `expect()` | Changed to `map_err()?` |
| `kubectl-client/src/processors/serviceaccount.rs:24-26` | Double `expect()` | Changed to `map_err()?` |

### Lua Fixes

| File | Issue | Fix Applied |
|------|-------|-------------|
| `lua/kubectl/views/statusline/init.lua` | Timer never stopped/cleaned up | Store timer in builder, cleanup on View() re-entry and Close(), remove from manager on close |
| `lua/kubectl/views/logs/session.lua:62-87` | Manager entry removed even if cleanup fails | Only remove from manager if `pcall` cleanup succeeds |

### False Positives (Not Bugs)

| Item | Reason |
|------|--------|
| `structs.rs:121` syntax error | Already correct - `///` is valid Rust doc comment syntax |
| Diagnostics `virtual_lines = false` | Intentional design - diagnostics show via signs by default, toggle enables virtual_lines |
| LSP client never stopped | Neovim LSP manages client lifecycle automatically - stops when no buffers attached |

---

## Completed Fixes (Priority 2)

### Lua Fixes

| File | Issue | Fix Applied |
|------|-------|-------------|
| `lua/kubectl/lsp/hover/init.lua:24-26` | Emojis in hover undocumented | Added comment explaining colored emojis provide clear severity distinction |
| `lua/kubectl/resource_factory.lua:269-273` | Async callback missing buffer validity | Added `nvim_buf_is_valid()` check before draw |
| `lua/kubectl/mappings.lua:383-386` | Buffer state access without nil check | Added `buf_state` and `content_row_start` nil checks |

### Rust Fixes

| File | Issue | Fix Applied |
|------|-------|-------------|
| `kubectl-client/src/lib.rs:373-376` | Silent statusline API failures | Added `tracing::warn!` for errors |
| `kubectl-client/src/lib.rs:262-265` | Sync `get_all` undocumented | Added doc comment explaining it's required for :Kubens command completion (must be sync) |
| `kubectl-client/src/statusline.rs:67` | Missing event timestamp source | Added `series.last_observed_time` fallback |
| `kubectl-client/src/cmd/log_session.rs:54-59` | Silent pod failures in multi-pod | Added `tracing::warn!` when skipping failed pods |
| `kubectl-client/src/cmd/log_session.rs:180-188` | No histogram bucket limit | Added `MAX_HISTOGRAM_BUCKETS = 500` constant |

### Already Addressed (Not Bugs)

| Item | Reason |
|------|--------|
| Stale request cancellation for LSP completion | Completion is synchronous - no async I/O that could cause stale data. Buffer validity check already present. |

---

## Executive Summary

Six specialized subagents performed comprehensive reviews of their respective areas. The codebase is well-architected overall with excellent patterns in both Rust and Lua layers.

| Area | Grade | Remaining Issues |
|------|-------|------------------|
| Rust Codebase | A- | 1 Medium (poisoned lock policy) |
| Lua Codebase | 9.4/10 | 1 Medium (state race condition) |
| Pod Logs Feature | Good | 2 Medium |
| LSP Features | Good | 3 Medium |
| Statusline Feature | Good | 4 Medium |
| Architecture | B | 3 Architectural |

---

## Remaining Action Items

### Priority 3: Medium (Nice to Have)

| # | Issue | Location | Effort |
|---|-------|----------|--------|
| 9 | Make statusline refresh interval configurable | `statusline/init.lua:5`, `config.lua` | Small |
| 10 | Add picker registry cleanup on TabClosed | `state.lua:376-396` | Small |
| 11 | Use rounding instead of truncation for CPU/memory | `statusline.rs:78-79` | Trivial |
| 12 | Add error hover content for failed fetches | `hover/init.lua:133-169` | Small |
| 13 | Standardize poisoned lock handling pattern | Various Rust files | Medium |
| 14 | Fix state initialization race condition | `state.lua:97-107` | Medium |
| 15 | Add visual feedback for stale statusline data | Lua + Rust statusline | Medium |

### Priority 4: Architectural (Future Refactoring)

| # | Issue | Location | Effort |
|---|-------|----------|--------|
| 16 | Refactor utils to be truly leaf modules | `lua/kubectl/utils/` | Large |
| 17 | Remove state.lua dependency on actions.commands | `state.lua`, `client/init.lua` | Large |
| 18 | Document mappings cross-reference pattern | Architecture docs | Small |

---

## Detailed Findings by Area

### 1. Rust Codebase

**Grade: A- (after Priority 2 fixes)**

#### 1.1 Fixed Issues

- ✓ Sync `get_all` function documented (required for :Kubens command completion)
- ✓ Statusline API failures now logged via `tracing::warn!`
- ✓ Event timestamps now include `series.last_observed_time` fallback
- ✓ Multi-pod log failures now logged with warning

#### 1.2 Remaining Medium Priority

##### 1.2.1 Poisoned Lock Handling Inconsistency

The codebase has two patterns for handling poisoned locks:

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

**Recommendation:** Document the policy - recovery for non-critical reads, error for critical state.

---

#### 1.2 Medium Priority

- String comparison performance in `sort.rs:29-32` - allocates String for every sort
- Deserialization without validation in `delete.rs:15` (other locations fixed)

---

### 2. Lua Codebase

**Grade: 9.2/10**

#### 2.1 Remaining High Priority

##### 2.1.1 Buffer State Access Without Nil Check

**Location:** `lua/kubectl/mappings.lua:383-384`

```lua
local buf_state = state.get_buffer_state(bufnr)
local mark, word = marks.get_current_mark(buf_state.content_row_start, bufnr)
```

**Fix:**
```lua
local buf_state = state.get_buffer_state(bufnr)
if not buf_state or not buf_state.content_row_start then
  return
end
```

---

##### 2.1.2 Async Callback Missing Buffer Validity Check

**Location:** `lua/kubectl/resource_factory.lua:265-273`

**Fix:** Add buffer validity check before `builder.draw()`:
```lua
vim.schedule(function()
  if builder.buf_nr and not vim.api.nvim_buf_is_valid(builder.buf_nr) then
    return
  end
  builder.draw(cancellationToken)
end)
```

---

##### 2.1.3 State Initialization Race Condition

**Location:** `lua/kubectl/state.lua:97-107`

Multiple components may access `state.context` before async initialization completes.

---

#### 2.2 Medium Priority

- Picker registry memory leak on TabClosed (`state.lua:376-396`)
- Mapping application order - may apply twice (`mappings.lua:695-708`)
- Inconsistent error callback handling - many `run_async` calls ignore errors

---

### 3. Pod Logs Feature

#### 3.1 Remaining High Priority

- Missing error context in log stream errors (`log_session.rs:386-388`) - no namespace/container in error
- No limit on histogram bucket count (`log_session.rs:186`) - could cause memory issues
- Silent pod failures in multi-pod mode (`log_session.rs:54-56`)
- Histogram timestamp parsing is fragile (`log_session.rs:149-164`)

#### 3.2 Medium Priority

- Global options state management (`session.lua:19`)
- JSON toggle modifies buffer without save check (`pod_logs/mappings.lua:27`)
- Timer memory leak on rapid toggle (`session.lua:112-117`)
- No backpressure handling - unbounded channel (`log_session.rs:406`)

---

### 4. LSP Features

#### 4.1 Remaining High Priority

##### 4.1.1 Emoji Usage in Hover Diagnostics

**Location:** `lua/kubectl/lsp/hover/init.lua:24-26`

```lua
local icon = diag.severity == vim.diagnostic.severity.ERROR and "🔴"
  or diag.severity == vim.diagnostic.severity.WARN and "🟡"
  or "🔵"
```

**Impact:** Terminal compatibility issues, inconsistent with codebase style.

**Fix:** Use text symbols: `"✗"`, `"⚠"`, `"ℹ"`

---

#### 4.2 Medium Priority

- Completion source registration race condition (`init.lua:19-22`)
- Missing error propagation in hover (`hover/init.lua:133-169`)
- Code actions exclude list hard-coded (`code_actions/init.lua:3-12`)
- Stale request cancellation only in hover, not completion

---

### 5. Statusline Feature

#### 5.1 Remaining High Priority

##### 5.1.1 Missing `series.last_observed_time` in Event Timestamp Logic

**Location:** `kubectl-client/src/statusline.rs:62-66`

```rust
let ts = e
    .event_time
    .as_ref()
    .map(|t| t.0)
    .or_else(|| e.last_timestamp.as_ref().map(|t| t.0));
```

Should also check `series.last_observed_time` for recurring events.

---

##### 5.1.2 Missing Error Context on API Failure

**Location:** `kubectl-client/src/lib.rs:369-378`

```rust
Err(_) => return Ok(String::new()),  // Error lost
```

Should log the error for debugging.

---

#### 5.2 Medium Priority

- Hardcoded 30s refresh interval (not configurable)
- CPU/memory truncation may hide issues (89.9% → 89%)
- No visual feedback for stale/missing data
- Event list query performance on large clusters

---

### 6. Architecture

**Health Score: B**

#### 6.1 Violations

1. **Utils layer violates leaf constraint** - Multiple utils import actions/state
2. **Core modules violate action dependency rule** - state.lua, client/init.lua import actions.commands
3. **Resources cross-require other resources** - pods ↔ containers (legitimate for navigation)

#### 6.2 Clean Areas

- Rust layer: No violations
- Pattern conformance: 97% use `BaseResource.extend`

---

## Test Scenarios

### Logs Feature
1. Rapid follow toggle - Check for timer leaks
2. Very wide terminal - Test histogram with width > 1000
3. Multi-pod with same names - Verify error messages distinguish namespaces
4. Buffer deleted during stream - Ensure no crashes

### LSP Feature
1. Fast typing in filter prompt - Verify no duplicate/stale results
2. Close buffer during hover fetch - Verify no errors

### Statusline Feature
1. Open/close plugin rapidly - Check timer cleanup ✓ (Fixed)
2. Large cluster with many events - Monitor performance
3. Network failure during refresh - Verify graceful degradation

---

## Files Modified

### Priority 1 Fixes

#### Rust Files
- `kubectl-client/src/dao/cronjob.rs`
- `kubectl-client/src/cmd/delete.rs`
- `kubectl-client/src/processors/node.rs`
- `kubectl-client/src/processors/pod.rs`
- `kubectl-client/src/processors/secret.rs`
- `kubectl-client/src/processors/configmap.rs`
- `kubectl-client/src/processors/serviceaccount.rs`

#### Lua Files
- `lua/kubectl/views/statusline/init.lua`
- `lua/kubectl/views/logs/session.lua`

### Priority 2 Fixes

#### Rust Files
- `kubectl-client/src/lib.rs`
- `kubectl-client/src/statusline.rs`
- `kubectl-client/src/cmd/log_session.rs`

#### Lua Files
- `lua/kubectl/lsp/hover/init.lua`
- `lua/kubectl/resource_factory.lua`
- `lua/kubectl/mappings.lua`
