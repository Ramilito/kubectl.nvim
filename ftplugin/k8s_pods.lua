local loop = require("kubectl.utils.loop")
local mappings = require("kubectl.mappings")
local pod_view = require("kubectl.views.pods")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(pod_view.Draw)
  end
end

init()

