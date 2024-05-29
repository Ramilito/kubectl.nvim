local tables = require("kubectl.view.tables")

local M = {}

local actions = require("kubectl.actions")

function M.filter()
	local hints = tables.generateHints({
		{ key = "<l>", desc = "logs" },
		{ key = "<d>", desc = "desc" },
		{ key = "<t>", desc = "top" },
		{ key = "<enter>", desc = "containers" },
	}, false, false)
	actions.open_filter("Filter: ", "k8s_filter", { is_float = true, title = "Filter", hints = hints })
end

return M
