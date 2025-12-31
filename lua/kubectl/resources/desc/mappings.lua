local describe_session = require("kubectl.views.describe.session")
local mappings = require("kubectl.mappings")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.refresh)"] = {
    noremap = true,
    silent = true,
    desc = "Toggle auto-refresh",
    callback = function()
      local is_running = describe_session.toggle()
      if is_running == nil then
        vim.notify("No describe session for this buffer", vim.log.levels.WARN)
      elseif is_running then
        vim.notify("Auto-refresh enabled", vim.log.levels.INFO)
      else
        vim.notify("Auto-refresh disabled", vim.log.levels.INFO)
      end
    end,
  },
}

function M.register()
  mappings.map_if_plug_not_set("n", "gr", "<Plug>(kubectl.refresh)")
end

return M
