local commands = require("kubectl.commands")
local config = require("kubectl.config")
local pod_view = require("kubectl.pods.views")
local filter_view = require("kubectl.filter.view")
local view = require("kubectl.view")

local M = {}

KUBE_CONFIG = commands.execute_shell_command("kubectl", {
	"config",
	"view",
	"--minify",
	"-o",
	'jsonpath=\'{range .clusters[*]}{"Cluster: "}{.name}{end} \z
                {range .contexts[*]}{"\\nContext: "}{.context.cluster}{"\\nUsers:   "}{.context.user}{end}\'',
})
FILTER = ""
function M.open()
	pod_view.Pods()
end

function M.setup(options)
	config.setup(options)
end

vim.api.nvim_create_user_command("Kubectl", function(opts)
	view.UserCmd(opts.fargs)
end, {
	nargs = "*",
})

local group = vim.api.nvim_create_augroup("Kubectl", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
	group = group,
	pattern = "k8s_*",
	callback = function()
		vim.api.nvim_buf_set_keymap(0, "n", "<C-f>", "", {
			noremap = true,
			silent = true,
			callback = function()
				filter_view.filter()
			end,
		})
	end,
})

return M
