local fallback_view = require("kubectl.views.fallback")
local loop = require("kubectl.utils.loop")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(fallback_view.Draw)
  end
end

init()
