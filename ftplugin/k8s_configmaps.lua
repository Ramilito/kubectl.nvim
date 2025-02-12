local configmaps_view = require("kubectl.views.configmaps")
local loop = require("kubectl.utils.loop")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(configmaps_view.Draw)
  end
end

init()
