# Testing Agent

Use this agent for ANY task involving writing, modifying, or running tests in kubectl.nvim.

## Framework

**Plenary.nvim busted-style testing** - tests run inside Neovim headlessly using `PlenaryBustedDirectory`.

## Running Tests

```bash
make test           # Run all tests
make prepare        # Clone plenary.nvim if missing (auto-run by make test)
```

Manual single file:
```bash
nvim --headless -c "PlenaryBustedFile tests/path/to_spec.lua"
```

## Test File Structure

**Location:** `tests/` directory, mirroring `lua/kubectl/` structure
**Naming:** `*_spec.lua` suffix required
**Entry point:** `tests/minimal_init.vim` (sets up runtimepath + plenary)

```
tests/
├── minimal_init.vim          # Test setup
├── config_spec.lua           # lua/kubectl/config.lua tests
├── utils/
│   ├── string_spec.lua       # lua/kubectl/utils/string.lua tests
│   ├── time_spec.lua
│   └── url_spec.lua
└── actions/
    ├── buffers_spec.lua      # lua/kubectl/actions/buffers.lua tests
    ├── commands_spec.lua
    └── layout_spec.lua
```

## Test Syntax

### Basic Structure

```lua
describe("module.name", function()
  local module_under_test

  before_each(function()
    -- Clear module cache for fresh state each test
    package.loaded["kubectl.module"] = nil
    module_under_test = require("kubectl.module")
  end)

  after_each(function()
    -- Cleanup: delete buffers, close windows, restore state
  end)

  describe("function_name", function()
    it("describes expected behavior", function()
      -- test code
    end)
  end)
end)
```

### Assertions (luassert)

```lua
-- Equality
assert.are.equal(expected, actual)      -- strict equality
assert.are.same({a=1}, {a=1})           -- deep table equality

-- Truthiness
assert.is_true(value)
assert.is_false(value)
assert.is_nil(value)
assert.is_not_nil(value)

-- Type checks
assert.is_table(value)
assert.is_string(value)
assert.is_number(value)
assert.is_function(value)

-- Error handling
assert.has_error(function() error("boom") end)
assert.has_no_error(function() end)
```

## Mocking Patterns

### Pattern 1: Replace package.loaded (most common)

Use when the module under test requires dependencies you want to mock:

```lua
before_each(function()
  -- Clear caches
  package.loaded["kubectl.actions.buffers"] = nil
  package.loaded["kubectl.state"] = nil

  -- Mock dependency BEFORE requiring module under test
  package.loaded["kubectl.state"] = {
    get_buffer_state = function() return {} end,
    set_buffer_selections = function() end,
  }

  -- Now require the module (it gets mocked state)
  buffers = require("kubectl.actions.buffers")
end)
```

### Pattern 2: Modify loaded module state

Use when testing how module reacts to different config values:

```lua
before_each(function()
  package.loaded["kubectl.config"] = nil
  local config = require("kubectl.config")

  -- Save original for restoration
  original_options = vim.deepcopy(config.options)

  -- Override specific values
  config.options = {
    kubectl_cmd = { cmd = "kubectl", env = {}, args = {} },
  }
end)

after_each(function()
  local config = require("kubectl.config")
  config.options = original_options
end)
```

### Pattern 3: Neovim API for buffer/window tests

```lua
before_each(function()
  -- Create test buffer
  test_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(test_buf, "kubectl://test_buffer")
end)

after_each(function()
  -- Clean up kubectl:// buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name:match("^kubectl://") then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end

  -- Clean up extra windows
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= vim.api.nvim_get_current_win() then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end)
```

## Exporting Local Functions for Testing

When you need to test a function that is local to a module, export it on the module table. This makes it accessible to tests while keeping it "private" by convention.

**Source file:**
```lua
-- lua/kubectl/utils/foo.lua
local M = {}

-- Local helper function (not normally exposed)
local function parse_value(input)
  -- implementation
  return result
end

function M.public_function(input)
  return parse_value(input)
end

-- Export local functions for testing
M._parse_value = parse_value

return M
```

**Test file:**
```lua
-- tests/utils/foo_spec.lua
local foo = require("kubectl.utils.foo")

describe("utils.foo", function()
  describe("_parse_value", function()
    it("parses input correctly", function()
      assert.are.equal("expected", foo._parse_value("input"))
    end)
  end)
end)
```

**Convention:** Prefix exported-for-testing functions with `_` to signal they are internal and not part of the public API.

## Writing New Tests

### 1. Create test file

Mirror the source file path:
- Source: `lua/kubectl/utils/string.lua`
- Test: `tests/utils/string_spec.lua`

### 2. Identify dependencies to mock

Read the source file and note all `require()` calls. Decide which need mocking.

### 3. Write tests

```lua
-- tests/utils/foo_spec.lua
local foo = require("kubectl.utils.foo")

describe("utils.foo", function()
  describe("bar", function()
    it("returns expected value for normal input", function()
      assert.are.equal("expected", foo.bar("input"))
    end)

    it("handles nil input", function()
      assert.is_nil(foo.bar(nil))
    end)

    it("handles empty string", function()
      assert.are.equal("", foo.bar(""))
    end)
  end)
end)
```

### 4. Run and verify

```bash
make test
```

## Test Categories

### Unit tests (pure functions)
- `tests/utils/` - string, time, url utilities
- `tests/config_spec.lua` - configuration handling
- No mocking needed for pure functions

### Integration tests (Neovim interaction)
- `tests/actions/` - buffer management, layout, commands
- Require mocking dependencies and Neovim cleanup
- Use `before_each`/`after_each` for isolation

## Common Pitfalls

1. **Forgetting to clear package.loaded** - Tests bleed state into each other
2. **Mock AFTER requiring** - Mock must be set BEFORE `require()` of module under test
3. **Not cleaning up buffers/windows** - Causes subsequent tests to fail
4. **Testing unexported functions** - If you need to test a local function, export it with a `_` prefix (see "Exporting Local Functions for Testing" above)

## LSP Warnings

The LSP will show "undefined global" warnings for `describe`, `it`, `before_each`, `after_each` - these are injected by plenary at runtime. Ignore these warnings in test files.
