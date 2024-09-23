local loop = require("kubectl.utils.loop")
local secrets_view = require("kubectl.views.secrets")

--- Set key mappings for the buffer
local function set_keymaps(_) end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(secrets_view.Draw)
  end
end

init()
