local loop = require("kubectl.utils.loop")
local sa_view = require("kubectl.views.sa")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(sa_view.Draw)
  end
end

init()
