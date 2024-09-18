local loop = require("kubectl.utils.loop")
local overview_view = require("kubectl.views.overview")

--- Set key mappings for the buffer
local function set_keymaps(_) end

--- Initialize the module
local function init()
  set_keymaps(0)

  if not loop.is_running() then
    loop.start_loop(overview_view.View, { interval = 15000 })
  end
end

init()
