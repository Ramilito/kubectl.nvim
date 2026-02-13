-- Feature Tier: Tests resource view keymap registration
-- Guards the user-facing feature of correct keybindings for each resource type

local new_set = MiniTest.new_set
local expect = MiniTest.expect
local mappings = require("kubectl.mappings")

local T = new_set()

-- Helper to create a buffer and setup mappings for a view
local function setup_view(view_name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  mappings.setup({ match = "k8s_" .. view_name, buf = buf })
  return buf
end

-- Helper to check if a key mapping exists on current buffer
local function has_mapping(lhs, mode)
  mode = mode or "n"
  local map = vim.fn.maparg(lhs, mode, false, true)
  return map and map.lhs ~= nil and map.lhs ~= ""
end

-- Helper to check if a mapping's rhs contains a plug target
local function maps_to_plug(lhs, plug_target, mode)
  mode = mode or "n"
  local map = vim.fn.maparg(lhs, mode, false, true)
  if map and map.rhs then
    return map.rhs:find(plug_target, 1, true) ~= nil
  end
  return false
end

-- Helper to check if a <Plug> callback exists as a buffer-local mapping
local function has_plug_mapping(plug_target, mode)
  mode = mode or "n"
  local map = vim.fn.maparg(plug_target, mode, false, true)
  return map and map.callback ~= nil
end

T["keymaps"] = new_set()

T["keymaps"]["pods view registers gl for logs"] = function()
  local buf = setup_view("pods")
  expect.equality(has_mapping("gl", "n"), true)
  expect.equality(maps_to_plug("gl", "<Plug>(kubectl.logs)", "n"), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["pods view registers gp for portforward"] = function()
  local buf = setup_view("pods")
  expect.equality(has_mapping("gp", "n"), true)
  expect.equality(maps_to_plug("gp", "<Plug>(kubectl.portforward)", "n"), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["pods view registers cr for select"] = function()
  local buf = setup_view("pods")
  expect.equality(has_mapping("<cr>", "n"), true)
  expect.equality(maps_to_plug("<cr>", "<Plug>(kubectl.select)", "n"), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["deployments view registers gi for set_image"] = function()
  local buf = setup_view("deployments")
  expect.equality(has_mapping("gi", "n"), true)
  expect.equality(maps_to_plug("gi", "<Plug>(kubectl.set_image)", "n"), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["deployments view registers grr for rollout_restart"] = function()
  local buf = setup_view("deployments")
  expect.equality(has_mapping("grr", "n"), true)
  expect.equality(maps_to_plug("grr", "<Plug>(kubectl.rollout_restart)", "n"), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["deployments view registers gss for scale"] = function()
  local buf = setup_view("deployments")
  expect.equality(has_mapping("gss", "n"), true)
  expect.equality(maps_to_plug("gss", "<Plug>(kubectl.scale)", "n"), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["nodes view registers gR for drain"] = function()
  local buf = setup_view("nodes")
  expect.equality(has_mapping("gR", "n"), true)
  expect.equality(maps_to_plug("gR", "<Plug>(kubectl.drain)", "n"), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["nodes view registers gO for cordon"] = function()
  local buf = setup_view("nodes")
  expect.equality(has_mapping("gO", "n"), true)
  expect.equality(maps_to_plug("gO", "<Plug>(kubectl.cordon)", "n"), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["nodes view registers gU for uncordon"] = function()
  local buf = setup_view("nodes")
  expect.equality(has_mapping("gU", "n"), true)
  expect.equality(maps_to_plug("gU", "<Plug>(kubectl.uncordon)", "n"), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["nodes view registers gS for shell"] = function()
  local buf = setup_view("nodes")
  expect.equality(has_mapping("gS", "n"), true)
  expect.equality(maps_to_plug("gS", "<Plug>(kubectl.shell)", "n"), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["global keymaps registered on pods view"] = function()
  local buf = setup_view("pods")
  -- Test a few representative global mappings
  expect.equality(has_mapping("gd", "n"), true) -- describe
  expect.equality(maps_to_plug("gd", "<Plug>(kubectl.describe)", "n"), true)
  expect.equality(has_mapping("gD", "n"), true) -- delete
  expect.equality(maps_to_plug("gD", "<Plug>(kubectl.delete)", "n"), true)
  expect.equality(has_mapping("gs", "n"), true) -- sort
  expect.equality(maps_to_plug("gs", "<Plug>(kubectl.sort)", "n"), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["global keymaps registered on deployments view"] = function()
  local buf = setup_view("deployments")
  -- Verify globals work on different resource types
  expect.equality(has_mapping("gy", "n"), true) -- yaml
  expect.equality(maps_to_plug("gy", "<Plug>(kubectl.yaml)", "n"), true)
  expect.equality(has_mapping("ge", "n"), true) -- edit
  expect.equality(maps_to_plug("ge", "<Plug>(kubectl.edit)", "n"), true)
  expect.equality(has_mapping("gr", "n"), true) -- refresh
  expect.equality(maps_to_plug("gr", "<Plug>(kubectl.refresh)", "n"), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["control keymaps registered on all views"] = function()
  local buf = setup_view("pods")
  -- Test control-key mappings
  expect.equality(has_mapping("<C-f>", "n"), true) -- filter
  expect.equality(maps_to_plug("<C-f>", "<Plug>(kubectl.filter_view)", "n"), true)
  expect.equality(has_mapping("<C-n>", "n"), true) -- namespace
  expect.equality(maps_to_plug("<C-n>", "<Plug>(kubectl.namespace_view)", "n"), true)
  expect.equality(has_mapping("<C-a>", "n"), true) -- alias
  expect.equality(maps_to_plug("<C-a>", "<Plug>(kubectl.alias_view)", "n"), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["tab keymaps registered on all views"] = function()
  local buf = setup_view("pods")
  expect.equality(has_mapping("<Tab>", "n"), true)
  expect.equality(maps_to_plug("<Tab>", "<Plug>(kubectl.tab)", "n"), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["pods view has logs Plug callback"] = function()
  local buf = setup_view("pods")
  expect.equality(has_plug_mapping("<Plug>(kubectl.logs)", "n"), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["deployments view has set_image Plug callback"] = function()
  local buf = setup_view("deployments")
  expect.equality(has_plug_mapping("<Plug>(kubectl.set_image)", "n"), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["deployments view does not have logs Plug"] = function()
  local buf = setup_view("deployments")
  -- Deployments don't override logs - it's pods-specific
  -- Neither gl mapping nor <Plug>(kubectl.logs) should exist
  expect.equality(has_mapping("gl", "n"), false)
  expect.equality(has_plug_mapping("<Plug>(kubectl.logs)", "n"), false)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["user remap protection works"] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)

  -- User manually maps something to <Plug>(kubectl.logs) BEFORE setup
  vim.keymap.set("n", "gL", "<Plug>(kubectl.logs)", { buffer = buf })

  -- Now setup the view
  mappings.setup({ match = "k8s_pods", buf = buf })

  -- The default gl binding should NOT be set because user already mapped to this plug target
  expect.equality(has_mapping("gl", "n"), false)
  -- But the user's mapping should still work
  expect.equality(has_mapping("gL", "n"), true)
  expect.equality(maps_to_plug("gL", "<Plug>(kubectl.logs)", "n"), true)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["resource-specific bindings override global select"] = function()
  -- Pods override <cr> with their own select behavior
  local buf = setup_view("pods")
  expect.equality(has_mapping("<cr>", "n"), true)
  -- The pods override should win (it goes to containers view)
  expect.equality(has_plug_mapping("<Plug>(kubectl.select)", "n"), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["visual mode filter mapping exists"] = function()
  local buf = setup_view("pods")
  expect.equality(has_mapping("<C-f>", "v"), true)
  expect.equality(maps_to_plug("<C-f>", "<Plug>(kubectl.filter_term)", "v"), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["keymaps"]["fallback view gets global mappings only"] = function()
  -- A view without specific mappings should still get globals
  local buf = setup_view("clusterroles") -- likely no custom mappings
  expect.equality(has_mapping("gd", "n"), true) -- describe
  expect.equality(has_mapping("gD", "n"), true) -- delete
  expect.equality(has_mapping("gs", "n"), true) -- sort
  vim.api.nvim_buf_delete(buf, { force = true })
end

return T
