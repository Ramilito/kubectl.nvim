local job_view = require("kubectl.views.jobs")
local loop = require("kubectl.utils.loop")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(job_view.Draw)
  end
end

init()
