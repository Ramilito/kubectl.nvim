---
name: testing
description: Testing specialist. ALWAYS use for ANY task involving writing tests, test infrastructure, mini.test, or test debugging.
tools: Read, Grep, Glob, Edit, Write, Bash
model: sonnet
---

# Testing Subagent

**ALWAYS use this subagent** for ANY task involving:
- Writing, modifying, or debugging tests
- Test infrastructure (`tests/` directory, `mini.test` setup)
- Test runner configuration or Makefile test targets
- Diagnosing test failures

## Testing Philosophy

Tests guard **features**, not functions. Every test answers: "Does this feature still work for the user?"

### When a Test SHOULD Break

- A feature's observable behavior changed
- A regression was introduced

### When a Test Should NOT Break

- Internal refactoring (renamed locals, extracted helpers, changed loop style)
- Moved code between files with same public API
- Added a new unrelated feature

### Test Scope

All tests are **feature-level**. A test exercises a user-facing feature end-to-end.

Some features are purely algorithmic (e.g., status coloring) and don't need a nvim child process. They're still feature tests — they verify "status text gets the right color", not "this function returns this value".

### What NOT to Test

- Thin wrappers around `vim.api.*`
- Internal structure or definition shapes (if it works, it works)
- Rust FFI internals (that's `cargo test`)
- Things that only fail if Neovim itself is broken
- **Dead code** — grep for usage before writing tests. If a function has 0 callers, don't test it
- **Functions in isolation** — if `time.diff_str` only serves the heartbeat feature, test the heartbeat feature through `generateHeader()`, not `diff_str` directly
- **Internal plumbing** — URL parsing, header building, etc. that users never interact with

### Before Writing a Test

1. **Identify the feature**: What user-facing behavior does this guard?
2. **Find the entry point**: What public function do callers actually invoke?
3. **Verify the code is live**: `grep -r "function_name" lua/` — if 0 callers, don't test it
4. **Check existing coverage**: Is this already tested through a higher-level feature test?

## Environment

Tests run inside `nvim --headless` via mini.test. **The full Neovim API is available** — `vim.api.*`, `vim.fn.*`, buffer/window operations all work. Tests are not limited to pure Lua; they execute in a real Neovim instance.

Config options in test setup (e.g., `hints = false`, `context = false`) are for **scoping the test** to the feature under test, not for working around API limitations.

## Framework: mini.test

Tests use `mini.test` from the mini.nvim ecosystem, run via `nvim --headless`.

### Directory Structure

```
tests/
  helpers/
    init.lua              -- mini.test bootstrap, adds project to rtp
  test_filtering.lua      -- feature: resource list filtering
  test_sorting.lua        -- feature: column sorting
  test_columns.lua        -- feature: column visibility and reordering
  test_heartbeat.lua      -- feature: heartbeat display in headers
  test_status_colors.lua  -- feature: status-to-highlight mapping
  test_view_aliases.lua   -- feature: alias resolution (po → pods)
```

### Test File Convention

- Files named `test_<feature>.lua`
- Each file tests ONE feature area
- Tests read like scenarios, not implementation probes

```lua
local new_set = MiniTest.new_set
local expect = MiniTest.expect

local T = new_set()

T["filtering"] = new_set()

T["filtering"]["includes matching rows"] = function()
  -- test the FEATURE, not the function
end

T["filtering"]["excludes with ! prefix"] = function()
  -- ...
end

return T
```

### Running Tests

```bash
make test              # Run all tests
make test FILE=<path>  # Run specific test file
```

### Writing Good Tests

1. **Name tests as behavior descriptions**: `"excludes rows with ! prefix"` not `"test_filter_negation_pattern"`
2. **Test through public entry points**: call the function users/modules actually call
3. **One assertion concept per test**: a test can have multiple `expect` calls if they verify the same behavior
4. **No mocking unless absolutely necessary**: if you need to mock everything, the test is too coupled
5. **Use realistic Rust-layer data shapes**: don't invent simplified structures, match actual processor output

### Test Data: Rust FieldValue Shape

The Rust layer produces rows with a specific shape. Tests MUST use this shape for realistic fixtures.

**FieldValue** (rich cell from Rust processors):
```lua
{ value = "Running", symbol = "KubectlSuccess", sort_by = nil, hint = nil }
```

- `value` (string) — display text
- `symbol` (string, optional) — highlight group name (KubectlError, KubectlWarning, KubectlSuccess, KubectlNote, KubectlDeprecated)
- `sort_by` (number, optional) — numeric sort key (IP as u32, age as unix timestamp, ready as composite)
- `hint` (string, optional) — tooltip text

**PodProcessed** (14 fields):
```lua
{
  namespace = "default",
  name = "nginx-pod-abc",
  ready = { value = "1/1", symbol = "KubectlNote", sort_by = 1 },
  status = { value = "Running", symbol = "KubectlSuccess" },
  restarts = { value = "0", sort_by = 0 },
  ip = { value = "10.244.0.42", sort_by = 171048746 },  -- u32 encoding
  node = "node-1",
  age = { value = "2h30m", sort_by = 1707850123 },      -- unix timestamp
  cpu = { value = "50m", sort_by = 50 },
  mem = { value = "128Mi", sort_by = 134217728 },
  ["%cpu/r"] = { value = "25%", sort_by = 25 },
  ["%cpu/l"] = { value = "5%", sort_by = 5 },
  ["%mem/r"] = { value = "50%", sort_by = 50 },
  ["%mem/l"] = { value = "12%", sort_by = 12 },
}
```

**DeploymentProcessed** (6 fields):
```lua
{
  namespace = "default",
  name = "nginx-deployment",
  ready = { value = "3/3", symbol = "KubectlNote", sort_by = 3006 },  -- (available*1001)+replicas
  ["up-to-date"] = 3,
  available = 3,
  age = { value = "5d", sort_by = 1707419723 },
}
```

**Pod headers** (matches Rust struct field order):
```lua
{ "NAMESPACE", "NAME", "READY", "STATUS", "RESTARTS", "CPU", "MEM", "%CPU/R", "%CPU/L", "%MEM/R", "%MEM/L", "IP", "NODE", "AGE" }
```

**sort_by encoding patterns:**
- IP addresses → u32 (e.g., `10.244.0.3` → `171048707`)
- Deployment ready → `(available * 1001) + replicas`
- Age → unix timestamp of creation
- Restarts → integer count
