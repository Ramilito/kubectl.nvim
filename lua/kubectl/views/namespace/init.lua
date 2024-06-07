local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.namespace.definition")

local M = {}

function M.Namespace()
  ResourceBuilder:new("namespace", { "get", "ns", "-o", "json" })
    :fetch()
    :decodeJson()
    :process(definition.processRow)
    :sort(SORTBY)
    :prettyPrint(definition.getHeaders)
    :displayFloat("k8s_namespace", "Namespace", "", true)

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(win, { 2, 0 })
end
function M.changeNamespace(name)
  local function handle_output(_)
    vim.schedule(function()
      NAMESPACE = name
      local win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_close(win, true)
      vim.api.nvim_input("R")
    end)
  end
  if name == "All" then
    NAMESPACE = "All"

    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_input("R")
  else
    commands.shell_command_async("kubectl", { "config", "set-context", "--current", "--namespace=" .. name }, handle_output)
  end
end

return M
