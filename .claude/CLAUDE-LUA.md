# CLAUDE-LUA.md

Guidance for working with the Lua/Neovim plugin codebase (`lua/kubectl/`).

## Plugin Structure

### Entry Point

`init.lua` - Plugin setup, commands (`:Kubectl`, `:Kubens`, `:Kubectx`), autocommands, and keymap registration.

### Core Modules

- `config.lua` - Default configuration with user overrides via `setup()`
- `state.lua` - Global runtime state, session persistence, filter/sort state
- `resource_factory.lua` - Builder pattern for constructing resource views
- `mappings.lua` - Global keybinding definitions using `<Plug>` format

### Resource Pattern

Each Kubernetes resource in `lua/kubectl/resources/<resource>/` follows:

```
<resource>/
├── init.lua        # View(), Draw(), Desc() functions
├── definition.lua  # Resource metadata (GVK, headers, hints)
└── mappings.lua    # Resource-specific keybindings
```

**Definition structure:**
```lua
M.definition = {
  resource = "pods",
  display_name = "PODS",
  ft = "k8s_pods",           -- filetype for buffer
  gvk = { g = "", v = "v1", k = "Pod" },
  hints = { ... },           -- help text shown in header
  headers = { ... },         -- column definitions
}
```

**Standard functions:**
```lua
function M.View(cancellationToken)   -- Create and show view
function M.Draw(cancellationToken)   -- Refresh existing view
function M.Desc(name, ns, reload)    -- Show resource description
```

## Resource Factory (Builder Pattern)

The factory in `resource_factory.lua` provides a fluent API:

```lua
local factory = require("kubectl.resource_factory")
factory.new("pods")
  .setCmd(args, "kubectl")
  .fetch()
  .decodeJson()
  .process(processFunc)
  .sort()
  .prettyPrint(win_nr)
  .addHints(hints, true, true)
  .addDivider(true)
  .displayContent(win_nr, cancellationToken)
```

**Key methods:**
- `.view(definition, token)` - Create buffer, start reflector, draw
- `.draw(token)` - Refresh data via Rust async call
- `.view_float(definition, opts)` - Floating window variant
- `.action_view(definition, data, callback)` - Action modal

## Rust Client Integration

The Rust dylib is loaded via `lua/kubectl/client/rust/init.lua`:
```lua
local client = require("kubectl.client.rust")  -- loads kubectl_client dylib
```

**Calling Rust functions:**
```lua
local commands = require("kubectl.actions.commands")

-- Async call (preferred)
commands.run_async("get_table_async", { gvk = def.gvk, namespace = ns }, function(data, err)
  if err then return end
  -- process data
end)

-- Sync call (blocks Neovim)
local result = commands.shell_command("kubectl", args)
```

## Filetypes

Plugin creates `k8s_*` filetypes for buffer identification:
- `k8s_pods`, `k8s_deployments`, `k8s_services`, etc.
- Used for filetype-specific autocommands and keymaps

## State Management

`state.lua` holds runtime state:
```lua
state.ns              -- current namespace ("All" or specific)
state.context         -- current kubectl context
state.filter          -- text filter
state.filter_label    -- label selectors
state.sortby          -- per-resource sort configuration
```

Session persistence via `kubectl.json` in Neovim data directory.

## Keymapping Convention

Use `<Plug>` mappings for user customization:
```lua
k("n", "gd", "<Plug>(kubectl.describe)", opts)
k("n", "gl", "<Plug>(kubectl.logs)", opts)
```

Register in `mappings.lua`, apply via FileType autocommand on `k8s_*` pattern.

## View System

Views in `lua/kubectl/views/` provide UI components:
- `filter/` - Filter input interface
- `namespace/` - Namespace selector
- `portforward/` - Port forward manager
- `header/` - Top header display
- `action/` - Action modal dialogs

## User Events

Emit events for extensibility:
```lua
vim.api.nvim_exec_autocmds("User", { pattern = "K8sResourceSelected", data = { kind, name, ns } })
vim.api.nvim_exec_autocmds("User", { pattern = "K8sContextChanged", data = { context } })
vim.api.nvim_exec_autocmds("User", { pattern = "K8sCacheLoaded" })
```

## Cancellation Tokens

Views accept cancellation tokens to abort rendering if buffer closed:
```lua
function M.View(cancellationToken)
  if cancellationToken and cancellationToken() then
    return nil
  end
  -- continue rendering
end
```

## Utilities

- `utils/tables.lua` - Table pretty-printing, header generation
- `utils/string.lua` - String manipulation
- `utils/find.lua` - Filtering logic
- `utils/url.lua` - URL building for kubectl/curl commands
- `utils/events.lua` - Event system helpers

## Code Style

- 2-space indentation (stylua)
- 120 column width
- LuaJIT/Lua 5.1 runtime
- Type annotations via `---@param`, `---@return` comments

## Defensive Patterns

### Buffer Validity After Async

Always check buffer validity in async callbacks - buffer may be deleted during async operation:
```lua
commands.run_async("some_function", args, function(content)
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    -- Safe to use buf
  end)
end)
```

### Stale Request Cancellation

Prevent showing outdated data when user triggers rapid requests:
```lua
local current_request_id = 0

function M.fetch_data(callback)
  current_request_id = current_request_id + 1
  local request_id = current_request_id

  commands.run_async(..., function(data)
    vim.schedule(function()
      if request_id ~= current_request_id then
        return  -- Stale request, newer one in flight
      end
      callback(data)
    end)
  end)
end
```

### Buffer State Nil Checks

Always check buffer state exists before accessing fields:
```lua
local buf_state = state.get_buffer_state(bufnr)
if not buf_state or not buf_state.content_row_start then
  return nil
end
```

### Column/Array Bounds Checking

Guard against nil when accessing parsed arrays:
```lua
local col_value = columns[index]
if not col_value then
  return nil
end
local trimmed = vim.trim(col_value)
```

### pcall Return Validation

Check module exists after pcall (module may return nil):
```lua
local ok, module = pcall(require, "some.module")
if ok and module and module.field then
  -- Safe to use module.field
end
```

### Numeric String Comparisons

Use `tonumber()` when comparing parsed numeric strings:
```lua
local current, total = val:match("^(%d+)/(%d+)$")
if current and total and tonumber(current) ~= tonumber(total) then
  -- Properly compares as numbers, not strings
end
```

### LSP Callback Protocol

Always call LSP callbacks, even for unhandled methods:
```lua
function srv.request(method, params, callback)
  if handlers[method] then
    handlers[method](method, params, callback)
  else
    callback(nil, nil)  -- Don't leave client waiting
  end
end
```
