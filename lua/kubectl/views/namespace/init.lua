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
    :addHints({
      { key = "<enter>", desc = "apply" },
    }, false, false)
    :prettyPrint(definition.getHeaders)
    :displayFloat("k8s_namespace", "Namespace", "", true)
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
  commands.shell_command("kubectl", { "config", "set-context", "--current", "--namespace=" .. name }, handle_output)
end

return M
