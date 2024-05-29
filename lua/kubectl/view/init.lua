local actions = require("kubectl.actions")
local commands = require("kubectl.commands")
local find = require("kubectl.utils.find")

local M = {}

function M.Hints(hint)
  actions.new_buffer(hint, "k8s_hints", { is_float = true, title = "Hints" })
end

function M.UserCmd(args)
  local results = commands.execute_shell_command("kubectl", args)
  local pretty = vim.split(results, "\n")
  actions.new_buffer(find.filter_line(pretty, FILTER), "k8s_usercmd", { is_float = false, title = "UserCmd" })
end

return M
