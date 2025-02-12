local helm_view = require("kubectl.views.helm")
local loop = require("kubectl.utils.loop")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(helm_view.Draw)
  end
end

init()
