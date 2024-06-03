local ResourceBuilder = require("kubectl.resourcebuilder")
local actions = require("kubectl.actions.actions")

local M = {}

function M.Hints(hint)
  actions.floating_buffer(hint, "k8s_hints", { title = "Hints" })
end

function M.UserCmd(args)
  local builder = ResourceBuilder:new("k8s_usercmd", args):fetch():splitData()
  builder.prettyData = builder.data
  builder:display("k8s_usercmd", "UserCmd")
end

return M
