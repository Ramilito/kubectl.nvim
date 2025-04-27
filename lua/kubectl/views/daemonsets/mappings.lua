local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local daemonset_view = require("kubectl.views.daemonsets")
local mappings = require("kubectl.mappings")
local state = require("kubectl.state")
local view = require("kubectl.views")

local M = {}
local err_msg = "Failed to extract pod name or namespace."

M.overrides = {
  ["<Plug>(kubectl.select)"] = {
    noremap = true,
    silent = true,
    desc = "Go to pods",
    callback = function()
      local name, ns = daemonset_view.getCurrentSelection()
      state.setFilter("")
      view.set_and_open_pod_selector(name, ns)
    end,
  },
  -- Only works _if_ there is only _one_ container and that image is the _same_ as the daemonset
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
            commands.shell_command_async(
              "kubectl",
              { "rollout", "restart", "daemonset/" .. name, "-n", ns },
              function(response)
                vim.schedule(function()
                  vim.notify(response)
                end)
              end
            )
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
