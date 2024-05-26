local view = require("kubectl.pods.views")
local config = require("kubectl.config")
local commands = require("kubectl.commands")

local M = {}

KUBE_CONFIG = commands.execute_shell_command("kubectl", {
	"config",
	"view",
	"--minify",
	"-o",
	'jsonpath=\'{range .clusters[*]}{"Cluster: "}{.name}{end} \z
                {range .contexts[*]}{"\\nContext: "}{.context.cluster}{"\\nUsers:   "}{.context.user}{end}\'',
})
function M.open()
	view.Pods()
end

function M.setup(options)
	config.setup(options)
end

return M
