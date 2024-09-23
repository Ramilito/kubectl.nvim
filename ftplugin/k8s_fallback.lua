local fallback_view = require("kubectl.views.fallback")
local loop = require("kubectl.utils.loop")

--- Set key mappings for the buffer
local function set_keymaps(_) end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(fallback_view.Draw)
  end
end

init()
