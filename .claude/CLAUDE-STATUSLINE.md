# CLAUDE-STATUSLINE.md

Guidance for working with the kubectl.nvim statusline feature.

## When to Use This Guide

Consult this guide when working on:
- Statusline content, layout, or formatting
- Cluster health indicators
- Statusline refresh timing or performance
- Adding new metrics to the statusline

## File Map

| Layer | File | Purpose |
|-------|------|---------|
| Rust | `kubectl-client/src/statusline.rs` | Statusline struct, metrics aggregation |
| Rust | `kubectl-client/src/lib.rs` | Exposes `get_statusline_async` to Lua |
| Lua | `lua/kubectl/views/statusline/init.lua` | Timer, rendering, highlight formatting |
| Lua | `lua/kubectl/config.lua:129-131` | Config defaults (`statusline.enabled`) |
| Lua | `lua/kubectl/init.lua:13,21-23` | View initialization on plugin start |

## Data Flow

```
Lua                              Rust (dylib)
───────────────────────────────────────────────────────────
View() ──► timer:start() ───────► (waits 5s)
Draw() ──► get_statusline_async ─► Aggregate node stats + events
                                  └─► Query Warning events (1h window)
process() ◄── JSON response ◄────┘
vim.o.statusline = formatted
```

## Current Metrics

| Metric | Source | Display |
|--------|--------|---------|
| `ready` / `not_ready` | `node_stats()` snapshot | Node count with health dot |
| `cpu_pct` | Average across nodes | Percentage |
| `mem_pct` | Average across nodes | Percentage |
| `crit_events` | Warning events in last hour | Count |

## Rust: Statusline Struct

```rust
pub struct Statusline {
    pub ready: u16,
    pub not_ready: u16,
    pub cpu_pct: u16,
    pub mem_pct: u16,
    pub crit_events: u32,
}
```

The `get_statusline()` async function:
1. Reads from the global `node_stats()` informer snapshot
2. Aggregates node readiness and resource usage
3. Queries all Warning events, filters to last hour
4. Returns serialized JSON to Lua

## Lua: View Lifecycle

**View()** - `statusline/init.lua:8-23`
- Saves original statusline/laststatus settings
- Sets `laststatus = 3` (global statusline)
- Starts timer: 5s initial delay, 30s interval

**Draw()** - `statusline/init.lua:25-38`
- Calls `get_statusline_async` via commands.run_async
- Decodes JSON, formats via `process()`
- Sets `vim.o.statusline`

**Close()** - `statusline/init.lua:41-52`
- Restores original statusline settings

**process()** - `statusline/init.lua:54-101`
- Formats metrics with highlight groups
- Uses `hl.symbols.success` / `hl.symbols.error` for coloring
- Centers output with `%=...%=`

## Configuration

```lua
-- In config.lua defaults
statusline = {
  enabled = false,  -- Disabled by default
}

-- Hardcoded in statusline/init.lua
M.interval = 30000  -- 30 second refresh
```

## Highlight Groups

| Condition | Highlight |
|-----------|-----------|
| All nodes ready | `hl.symbols.success` (green) |
| Any node not ready | `hl.symbols.error` (red) |
| CPU < 90% | `hl.symbols.success` |
| CPU >= 90% | `hl.symbols.error` |
| MEM < 90% | `hl.symbols.success` |
| MEM >= 90% | `hl.symbols.error` |
| Events = 0 | `hl.symbols.success` |
| Events > 0 | `hl.symbols.error` |

## Current Limitations

1. **Static interval** - 30s hardcoded, not configurable
2. **No namespace awareness** - Events are cluster-wide
3. **No clickable regions** - Pure display, no interaction
4. **No pod metrics** - Only node-level aggregation
5. **Limited event filtering** - All Warning events, no severity distinction
6. **Timer not cleaned up** - Timer continues even if statusline disabled mid-session

## Common Tasks

### Adding a New Metric

1. Add field to `Statusline` struct in `statusline.rs`
2. Compute value in `get_statusline()` async function
3. Update `process()` in Lua to format and display
4. Add highlight threshold logic if applicable

### Making Interval Configurable

1. Add `interval` field to `StatuslineConfig` in `config.lua`
2. Read from config in `View()` instead of `M.interval`
3. Update defaults and type annotations

### Adding Namespace-Scoped Events

1. Accept namespace param in `get_statusline()`
2. Use namespaced `Api<Event>` instead of `Api::all()`
3. Pass current namespace from Lua state
