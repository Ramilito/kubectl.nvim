# Describe Feature Investigation & Improvement Plan

## Overview

This document captures the investigation into kubectl.nvim's describe feature implementation and outlines potential improvements. The describe feature uses a 3-layer architecture spanning Lua, Rust, and Go.

---

## Current Architecture

### Data Flow

```
User (gd keypress)
    │
    ├──→ lua/kubectl/mappings.lua:147 - Call view.Desc(name, ns)
    │
    ├──→ lua/kubectl/resources/base_resource.lua:50-54
    │    └─→ Build GVK from definition
    │
    ├──→ lua/kubectl/views/describe/session.lua:169-201 - M.view()
    │    ├─ Create framed buffer layout
    │    ├─ Show hints
    │    └─ Create session
    │
    ├──→ client.describe_session() [Lua → Rust FFI]
    │    │
    │    ├──→ kubectl-client/src/describe_session.rs
    │    │    ├─ Parse config (name, ns, context, gvk)
    │    │    ├─ Call Go FFI synchronously (fail-fast)
    │    │    └─ Spawn polling task (2s interval)
    │    │
    │    └──→ POLLING LOOP (Tokio task):
    │         ├─ call_describe(args) → Go FFI
    │         ├─ Hash content (SHA256)
    │         ├─ If changed: send via mpsc channel
    │         └─ On error: exponential backoff (2s → 120s)
    │
    ├──→ go/kubedescribe.go - DescribeResource()
    │    ├─ getRestConfig(context) [cached]
    │    ├─ Create GVR → GVK mapper [cached]
    │    ├─ Get kubectl describer [cached]
    │    └─ d.Describe() with ShowEvents: true
    │
    └──→ lua/kubectl/views/describe/session.lua - Timer (200ms)
         ├─ rust_session:read_content() [non-blocking]
         ├─ If content: buffers.set_content()
         └─ Auto-cleanup on buffer close
```

### Key Files

| Layer | File | Responsibility |
|-------|------|----------------|
| Lua | `lua/kubectl/mappings.lua` | Keybinding (`gd`) |
| Lua | `lua/kubectl/resources/base_resource.lua` | `Desc()` method |
| Lua | `lua/kubectl/views/describe/session.lua` | Session management, UI |
| Lua | `lua/kubectl/resources/desc/mappings.lua` | Describe-specific mappings |
| Lua | `lua/kubectl/resource_factory.lua` | `view_framed()` layout |
| Rust | `kubectl-client/src/describe_session.rs` | DescribeSession, polling task |
| Rust | `kubectl-client/src/streaming.rs` | StreamingSession generic |
| Go | `go/kubedescribe.go` | kubectl FFI wrapper |

---

## Identified Issues

### Lua Layer

| Issue | Location | Impact |
|-------|----------|--------|
| **No manual refresh** | `desc/mappings.lua` | `gr` only toggles auto-refresh, can't force reload |
| **Fixed 200ms polling** | `session.lua:105` | No user control over refresh rate |
| **Missing buf_name** | `buffers.lua` framed_buffer | Generic refresh logic fails for framed buffers |
| **Not integrated with loop system** | `session.lua` uses custom timer | Inconsistent UX, state not persisted in session |
| **Stale session race** | `session.lua:169-201` | Rapid resource switching leaves old sessions running |
| **LSP pattern bug** | `init.lua:155` | Pattern `_describe$` doesn't match filetype `k8s_desc` |
| **No error handling** | `session.lua:86-96` | Silent failure on rust session creation |
| **Session key collision** | `session.lua:12-14` | Uses only buffer number, could collide |

### Rust/Go Layer

| Issue | Location | Impact |
|-------|----------|--------|
| **Polling overhead** | `describe_session.rs:19` | Full describe + hash every 2s, even with no changes |
| **Go FFI blocking** | `call_describe()` | `spawn_blocking` holds threadpool slot until Go returns |
| **No watch support** | Architecture | Misses Kubernetes native `?watch=true` API |
| **Memory allocations** | FFI boundary | Full output copied across FFI each poll |
| **No cache eviction** | `kubedescribe.go:23-27` | Unbounded sync.Map caches, memory leak potential |
| **Error hiding** | `describe_session.rs:183-189` | Exponential backoff up to 120s hides errors |
| **No telemetry** | Go layer | Can't debug performance issues |
| **String copying** | FFI | C string allocation in Go, free in Rust |

### UX Issues

| Issue | Description |
|-------|-------------|
| **No syntax highlighting** | Uses generic `yaml` syntax, but describe output isn't YAML |
| **No folding** | Long outputs (especially Events) hard to navigate |
| **No section jumping** | Can't jump directly to Events or other sections |
| **No related resource navigation** | Can't click on referenced resources (Secrets, ConfigMaps) |
| **Events at bottom** | Important for debugging but buried in output |

---

## Improvement Suggestions

### Quick Wins (Low Effort)

#### 1. Add Manual Refresh Option
- **Change**: Add `gR` or `<C-r>` for force refresh, keep `gr` for toggle
- **Location**: `lua/kubectl/resources/desc/mappings.lua`
- **Effort**: ~30 minutes

#### 2. Increase Rust Poll Interval
- **Change**: 2s → 5s (60% reduction in overhead)
- **Location**: `kubectl-client/src/describe_session.rs:19`
- **Effort**: ~5 minutes

#### 3. Configurable Lua Polling
- **Change**: Add `config.options.describe.polling_interval`
- **Location**: `lua/kubectl/config.lua`, `session.lua`
- **Effort**: ~1 hour

#### 4. Fix LSP Pattern
- **Change**: `_describe$` → `_desc$` or add `k8s_desc` to skip list
- **Location**: `lua/kubectl/init.lua:155`
- **Effort**: ~5 minutes

### Medium Effort Improvements

#### 5. Stale Session Prevention
- **Change**: Add `current_request_id` pattern (like LogSession)
- **Location**: `lua/kubectl/views/describe/session.lua`
- **Effort**: ~2-3 hours

#### 6. Add Go Cache Bounds
- **Change**: Use LRU cache with limit (e.g., 100 entries)
- **Location**: `go/kubedescribe.go`
- **Effort**: ~2 hours

#### 7. Better Error Propagation
- **Change**: Show notification on failure, add retry with visible status
- **Location**: `session.lua:86-96`
- **Effort**: ~2 hours

#### 8. Integrate with Loop System
- **Change**: Replace custom timer with `loop.start_loop_for_buffer()`
- **Location**: `session.lua`, `loop.lua`
- **Effort**: ~4-6 hours

#### 9. Custom Syntax Highlighting
- **Change**: Create `k8s_describe` filetype with proper highlighting
- **Location**: New syntax file, `resource_factory.lua`
- **Effort**: ~4-6 hours
- **Highlights**: Section headers, status values, timestamps, resource refs

### High-Impact Strategic Improvements

#### 10. Hybrid Watch Strategy
- **Change**: Use kube-rs `Api::watch()` on single resource, only describe on event
- **Location**: `kubectl-client/src/describe_session.rs`
- **Effort**: ~1-2 days
- **Benefit**: Eliminates idle polling entirely

#### 11. Section-Based Updates
- **Change**: Parse describe into sections, update only changed sections
- **Location**: Both Lua and Rust layers
- **Effort**: ~3-5 days
- **Benefit**: Collapsible folding, faster updates

#### 12. Jump to Related Resources
- **Change**: Parse resource refs, `gd` on `SecretName: my-secret` → jumps to secret
- **Location**: `lua/kubectl/resources/desc/mappings.lua`
- **Effort**: ~1-2 days
- **Benefit**: Better navigation workflow

#### 13. Events Section Improvements
- **Change**: Add `ge` to jump to Events, option to show Events first
- **Location**: `desc/mappings.lua`, `session.lua`
- **Effort**: ~4-6 hours
- **Benefit**: Faster debugging workflow

---

## Comparison: DescribeSession vs LogSession

The LogSession implementation demonstrates better patterns:

| Aspect | DescribeSession | LogSession |
|--------|-----------------|------------|
| Data Source | Polling Go FFI | Kubernetes streaming API |
| Change Detection | SHA256 hash | Native stream updates |
| Concurrency | spawn_blocking per poll | Async stream with backpressure |
| Batch Processing | Single string | `try_recv_batch(100)` |
| Error Handling | Exponential backoff | Stream reconnection |
| Memory | Full output per poll | Incremental line-by-line |
| Cancellation | AtomicBool check | Tokio task cancellation |

---

## Recommended Priority Order

1. **Immediate** (no code): Monitor actual usage patterns
2. **Quick wins** (1 day): Items 1-4 above
3. **Medium term** (1 week): Items 5-9, especially stale session prevention
4. **Strategic** (2-4 weeks): Hybrid watch strategy (item 10)

> **Note**: Pure Rust describe was considered but deemed not viable. kubectl's describe logic is 5k+ lines of code handling all resource types - not practical to replicate.

---

## Metrics to Track (Future)

- Polls per second per session
- Go FFI call duration (p50, p99)
- Hash collision rate (no change detected)
- Cache memory usage in Go layer
- Number of concurrent describe sessions

---

## Notes

- Investigation conducted: 2026-01-23
- Subagents used: `lua`, `rust`
- Current implementation is functional and reliable
- Go FFI for describe is here to stay (kubectl describe is 5k+ lines, not practical to reimplement)
