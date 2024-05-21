-- k8s_deployments.lua in ~/.config/nvim/ftplugin
local view = require("kubectl.view.view")

vim.api.nvim_buf_set_keymap(0, "n", "<CR>", "", {
	noremap = true,
	silent = true,
	desc = "kgp",
	callback = function()
		view.Pods()
	end,
})
