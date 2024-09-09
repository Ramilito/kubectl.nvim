local ResourceBuilder = require("kubectl.resourcebuilder")
local definition = require("kubectl.views.root.definition")
local grid = require("kubectl.utils.grid")
local timeme = require("kubectl.utils.timeme")

local M = {}

function M.View()
  timeme.start()
  ResourceBuilder:new(definition.resource)
    :display(definition.ft, definition.resource)
    :setCmd(definition.url, definition.cmd)
    :fetchAsync(function(builder)
      builder:decodeJson():process(definition.processRow):sort()
      vim.schedule(function()
        builder.prettyData, builder.extmarks =
          grid.pretty_print(definition.processRow(builder.data), definition.getSections())
        builder:addHints(definition.hints, true, true, true):setContent(nil)
      end)

      timeme.stop()
    end)
end

return M
