local view = require("kubectl.view")
local config = require("kubectl.config")
local commands = require("kubectl.commands")

local M = {}

-- kubectl config view --minify -o jsonpath='{range .clusters[*]}{"cluster_name: "}{.name}{"\ncluster: "}{.cluster}{"\n"}{end}{range .contexts[*]}{"context: "}{.context}{"\n"}{end}{range .users[*]}{"user_name: "}{.name}{"\n"}{end}'
KUBE_CONFIG = commands.execute_shell_command("kubectl", {
	"config",
	"view",
	"--minify",
	"-o",
	'jsonpath=\'{range .clusters[*]}{"Cluster: "}{.name}{end} \z
                {range .contexts[*]}{"\\nContext: "}{.context.cluster}{"\\nUsers: "}{.context.user}{end}\'',
})
function M.open()
	view.Pods()
end

function M.setup(options)
	config.setup(options)
end

return M
