local api_resources_view = require("kubectl.views.api-resources")
local loop = require("kubectl.utils.loop")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(api_resources_view.Draw)
  end
end

init()
