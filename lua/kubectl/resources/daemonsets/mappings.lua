local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local daemonset_view = require("kubectl.resources.daemonsets")
local mappings = require("kubectl.mappings")

local M = {}
local err_msg = "Failed to extract pod name or namespace."

M.overrides = {
  ["<Plug>(kubectl.set_image)"] = {
    noremap = true,
    silent = true,
    desc = "Set image",
    callback = function()
      local name, ns = daemonset_view.getCurrentSelection()
      if not name or not ns then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      daemonset_view.SetImage(name, ns)
    end,
  },

  ["<Plug>(kubectl.rollout_restart)"] = {
    noremap = true,
    silent = true,
    desc = "Rollout restart",
    callback = function()
      local name, ns = daemonset_view.getCurrentSelection()
      buffers.confirmation_buffer(
        "Are you sure that you want to restart the daemonset: " .. name,
        "prompt",
        function(confirm)
          if confirm then
            commands.run_async("restart_async", {
              daemonset_view.definition.gvk.k,
              daemonset_view.definition.gvk.g,
              daemonset_view.definition.gvk.v,
              name,
              ns,
            }, function(response)
              vim.schedule(function()
                vim.notify(response)
              end)
            end)
          end
        end
      )
    end,
  },
}

M.register = function()
  mappings.map_if_plug_not_set("n", "gi", "<Plug>(kubectl.set_image)")
  mappings.map_if_plug_not_set("n", "grr", "<Plug>(kubectl.rollout_restart)")
end

return M
