local tables = require("kubectl.view.tables")

local M = {}

local actions = require("kubectl.actions")

function M.filter()
	local hints = tables.generateHints({
		{ key = "<enter>", desc = "apply" },
	}, false, false)
	actions.open_filter("Filter: ", "k8s_filter", { is_float = true, title = "Filter", hints = hints })
end

return M
