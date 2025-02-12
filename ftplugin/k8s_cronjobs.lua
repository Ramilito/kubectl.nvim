local cronjob_view = require("kubectl.views.cronjobs")
local loop = require("kubectl.utils.loop")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(cronjob_view.Draw)
  end
end

init()
