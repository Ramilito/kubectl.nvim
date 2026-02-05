local commands = require("kubectl.actions.commands")
local daemonset_view = require("kubectl.resources.daemonsets")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local mapping_helpers = require("kubectl.utils.mapping_helpers")
local mappings = require("kubectl.mappings")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.set_image)"] = {
    noremap = true,
    silent = true,
    desc = "Set image",
    callback = mapping_helpers.safe_callback(daemonset_view, daemonset_view.SetImage),
  },

  ["<Plug>(kubectl.rollout_restart)"] = {
    noremap = true,
    silent = true,
    desc = "Rollout restart",
    callback = function()
      local name, ns = daemonset_view.getCurrentSelection()
      local builder = manager.get_or_create("daemonset_restart")

      local def = {
        resource = "daemonset_restart",
        display = "Restart daemonset",
        ft = "k8s_action",
      }

      local action_data = {
        {
          text = "",
          value = ns .. "/" .. name,
          type = "positional",
          hl = hl.symbols.pending,
        },
      }

      builder.data = {}
      builder.action_view(def, action_data, function()
        commands.run_async("restart_async", {
          gvk = daemonset_view.definition.gvk,
          name = name,
          namespace = ns,
        }, function(response)
          vim.schedule(function()
            vim.notify(response)
          end)
        end)
      end)
    end,
  },
}

M.register = function()
  mappings.map_if_plug_not_set("n", "gi", "<Plug>(kubectl.set_image)")
  mappings.map_if_plug_not_set("n", "grr", "<Plug>(kubectl.rollout_restart)")
end

return M
