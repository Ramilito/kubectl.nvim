local loop = require("kubectl.utils.loop")

--- Initialize the module
local function init()
  if not loop.is_running() then
    loop.start_loop(function()
      print("Refreshing")
    end)
  end
end

init()
