local deployment_view = require("kubectl.views.deployments")
local loop = require("kubectl.utils.loop")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(deployment_view.Draw)
  end
end

init()
