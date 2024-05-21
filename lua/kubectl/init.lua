local view = require("kubectl.view")
local config = require("kubectl.config")

local M = {}

function M.open()
	view.Pods()
end

function M.setup(options)
	config.setup(options)
end

return M
