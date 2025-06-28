local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local helm_view = require("kubectl.resources.helm")
local mappings = require("kubectl.mappings")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.delete)"] = {
    noremap = true,
    silent = true,
    desc = "Uninstall helm deployment",
    callback = function()
      local name, ns = helm_view.getCurrentSelection()
      buffers.confirmation_buffer(
        string.format("Are you sure that you want to uninstall the helm deployment: %s in namespace %s?", name, ns),
        "prompt",
        function(confirm)
          if confirm then
            commands.shell_command_async("helm", { "uninstall", name, "-n", ns }, function(response)
              vim.schedule(function()
                vim.notify(response)
              end)
            end)
          end
        end
      )
    end,
  },

  ["<Plug>(kubectl.describe)"] = {
    noremap = true,
    silent = true,
    desc = "Describe",
    callback = function()
      local name, ns = helm_view.getCurrentSelection()
      helm_view.Desc(name, ns)
    end,
  },

  ["<Plug>(kubectl.values)"] = {
    noremap = true,
    silent = true,
    desc = "Get helm values",
    callback = function()
      local name, ns = helm_view.getCurrentSelection()
      helm_view.Values(name, ns)
    end,
  },
}
function M.register()
  mappings.map_if_plug_not_set("n", "gv", "<Plug>(kubectl.values)")
  mappings.map_if_plug_not_set("n", "gd", "<Plug>(kubectl.describe)")
end

return M
