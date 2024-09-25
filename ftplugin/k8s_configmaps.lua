local configmaps_view = require("kubectl.views.configmaps")
local loop = require("kubectl.utils.loop")

--- Set key mappings for the buffer
local function set_keymaps(_) end

--- Initialize the module
local function init()
  set_keymaps(0)

  if not loop.is_running() then
    loop.start_loop(configmaps_view.Draw)
  end
end

init()
