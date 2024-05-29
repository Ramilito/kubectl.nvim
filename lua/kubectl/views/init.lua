local actions = require("kubectl.actions.actions")
local commands = require("kubectl.actions.commands")
local find = require("kubectl.utils.find")

local M = {}

function M.Hints(hint)
  actions.floating_buffer(hint, "k8s_hints", { title = "Hints" })
end

function M.UserCmd(args)
  local results = commands.execute_shell_command("kubectl", args)
  local pretty = vim.split(results, "\n")
  actions.buffer(find.filter_line(pretty, FILTER), "k8s_usercmd", { title = "UserCmd" })
end

return M
