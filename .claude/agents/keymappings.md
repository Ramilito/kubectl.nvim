---
name: keymappings
description: Keymappings specialist. ALWAYS use for ANY task involving adding, modifying, or removing keybindings in views or resources.
tools: Read, Grep, Glob, Edit, Write
model: haiku
---

# Keymappings Guidance

**ALWAYS use this subagent** for ANY task involving:
- Adding new keybindings to a view or resource
- Modifying existing keybindings
- Understanding how keybindings work in this codebase

## File Map

| File | Purpose |
|------|---------|
| `lua/kubectl/mappings.lua` | Global mappings, `map_if_plug_not_set()`, `register()` |
| `lua/kubectl/resources/<name>/mappings.lua` | Resource-specific overrides |
| `lua/kubectl/views/<name>/mappings.lua` | View-specific overrides |
| `lua/kubectl/views/<name>/init.lua` | View definition with `hints` array |

## Pattern: Adding a Keybinding

### Step 1: Define the Plug mapping in `mappings.lua`

```lua
M.overrides = {
  ["<Plug>(kubectl.my_action)"] = {
    desc = "short description",  -- Used in help view
    callback = function()
      -- Implementation
    end,
  },
}
```

### Step 2: Register the key in `M.register()`

```lua
M.register = function()
  mappings.map_if_plug_not_set("n", "gX", "<Plug>(kubectl.my_action)")
end
```

### Step 3: Add hint in view's `init.lua`

```lua
M.definition = {
  hints = {
    { key = "<Plug>(kubectl.my_action)", desc = "my action" },
  },
}
```

## Key Rules

1. **Always use `<Plug>(kubectl.*)` format** - Never map raw keys directly in overrides
2. **Use `mappings.map_if_plug_not_set()`** - Respects user customizations
3. **Hints reference `<Plug>` keys** - System resolves to actual keys automatically
4. **Short descriptions** - `desc` in overrides should be 2-4 words

## Common Key Conventions

| Prefix | Purpose | Examples |
|--------|---------|----------|
| `g` | Go/Get actions | `gd` describe, `gy` yaml, `gl` logs |
| `<C->` | Views/Navigation | `<C-n>` namespace, `<C-f>` filter |
| `<cr>` | Select/Enter | Primary action |
| `1-6` | Quick view switch | Deployments, Pods, etc. |

## Example: Complete Mapping File

```lua
local mappings = require("kubectl.mappings")
local M = {}

M.overrides = {
  ["<Plug>(kubectl.my_action)"] = {
    desc = "do something",
    callback = function()
      local view = require("kubectl.views.myview")
      -- implementation
    end,
  },
}

M.register = function()
  mappings.map_if_plug_not_set("n", "gX", "<Plug>(kubectl.my_action)")
end

return M
```

## Checklist

- [ ] Plug mapping defined in `M.overrides`
- [ ] Key registered in `M.register()` using `map_if_plug_not_set`
- [ ] Hint added to view's `hints` array (if user-facing)
- [ ] Description is short (2-4 words)
