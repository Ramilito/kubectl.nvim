-- Feature Tier: Tests recovery from unavailable Kubernetes contexts
-- Guards the user-facing feature of returning to context selection after a failed context switch

local new_set = MiniTest.new_set
local expect = MiniTest.expect
local commands = require("kubectl.actions.commands")
local client = require("kubectl.client")
local contexts = require("kubectl.resources.contexts")
local manager = require("kubectl.resource_manager")
local splash = require("kubectl.splash")
local state = require("kubectl.state")

local T = new_set()

T["context switching"] = new_set()

local function selector_is_visible()
  local selector = manager.get("contexts")
  if not selector or not vim.api.nvim_buf_is_valid(selector.buf_nr) then
    return false
  end
  for _, line in ipairs(vim.api.nvim_buf_get_lines(selector.buf_nr, 0, -1, false)) do
    if line:find("docker-desktop", 1, true) then
      return vim.bo[selector.buf_nr].filetype == "k8s_contexts"
    end
  end
  return false
end

local function splash_shows_error()
  local splash_view = manager.get("splash")
  if not splash.is_open() or not splash_view or not vim.api.nvim_buf_is_valid(splash_view.buf_nr) then
    return false
  end
  for _, line in ipairs(vim.api.nvim_buf_get_lines(splash_view.buf_nr, 0, -1, false)) do
    if line:find("Failed to load context", 1, true) then
      return true
    end
  end
  return false
end

local function mock_unavailable_context()
  ---@diagnostic disable-next-line: duplicate-set-field
  commands.run_async = function(method_name, _, callback)
    assert(method_name == "get_config_async", "unexpected async command: " .. method_name)
    callback(vim.json.encode({
      ["current-context"] = "available",
      contexts = {
        { name = "available", context = { cluster = "kind", user = "user", namespace = "default" } },
        { name = "docker-desktop", context = { cluster = "docker-desktop", user = "user" } },
      },
    }))
  end
  client.set_implementation = function(callback)
    callback(false)
  end
end

local function restore_test_state(originals)
  commands.run_async = originals.run_async
  client.set_implementation = originals.set_implementation
  state.context["current-context"] = originals.context
  contexts.contexts = originals.contexts
  manager.close_all()
end

T["context switching"]["shows the error briefly before reopening context selection"] = function()
  local originals = {
    run_async = commands.run_async,
    set_implementation = client.set_implementation,
    context = state.context["current-context"],
    contexts = vim.deepcopy(contexts.contexts),
  }
  local ok, err = xpcall(function()
    mock_unavailable_context()
    contexts.change_context("docker-desktop")
    assert(vim.wait(500, splash_shows_error), "context failure message was not shown")
    assert(not vim.wait(1000, selector_is_visible), "context selector reopened before the error could be read")
    assert(vim.wait(2500, selector_is_visible), "context selector did not reopen after the error message")
  end, debug.traceback)
  restore_test_state(originals)

  if not ok then
    error(err)
  end
  local selector = manager.get("contexts")
  expect.equality(selector, nil)
end

return T
