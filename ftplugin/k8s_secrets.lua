local loop = require("kubectl.utils.loop")
local secrets_view = require("kubectl.views.secrets")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(secrets_view.Draw)
  end
end

init()
