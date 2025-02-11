local daemonset_view = require("kubectl.views.daemonsets")
local loop = require("kubectl.utils.loop")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(daemonset_view.Draw)
  end
end

init()
