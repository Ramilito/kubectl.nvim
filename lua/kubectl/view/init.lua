local actions = require("kubectl.actions")

local M = {}

function M.Hints(hint)
	actions.new_buffer(hint, "k8s_hints", { is_float = true, title = "Hints" })
end



return M
