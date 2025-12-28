local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local manager = require("kubectl.resource_manager")
local mapping_helpers = require("kubectl.utils.mapping_helpers")
local mappings = require("kubectl.mappings")
local statefulset_view = require("kubectl.resources.statefulsets")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.set_image)"] = {
    noremap = true,
    silent = true,
    desc = "Set image",
    callback = mapping_helpers.safe_callback(statefulset_view, statefulset_view.SetImage),
  },

  ["<Plug>(kubectl.scale)"] = {
    noremap = true,
    silent = true,
    desc = "Scale replicas",
    callback = function()
      local name, ns = statefulset_view.getCurrentSelection()
      local builder = manager.get_or_create("statefulset_scale")
      commands.run_async(
        "get_single_async",
        { gvk = statefulset_view.definition.gvk, namespace = ns, name = name, output = "Json" },
        function(data)
          if not data then
            return
          end
          builder.data = data
          builder.decodeJson()
          local current_replicas = tostring(builder.data.spec.replicas)

          vim.schedule(function()
            vim.ui.input({ prompt = "Scale replicas: ", default = current_replicas }, function(input)
              if not input then
                return
              end
              buffers.confirmation_buffer(
                string.format("Are you sure that you want to scale the statefulset to %s replicas?", input),
                "prompt",
                function(confirm)
                  if not confirm then
                    return
                  end

                  commands.run_async("scale_async", {
                    gvk = statefulset_view.definition.gvk,
                    name = name,
                    namespace = ns,
                    replicas = tonumber(input),
                  }, function(response)
                    vim.schedule(function()
                      vim.notify(response)
                    end)
                  end)
                end
              )
            end)
          end)
        end
      )
    end,
  },

  ["<Plug>(kubectl.rollout_restart)"] = {
    noremap = true,
    silent = true,
    desc = "Rollout restart",
    callback = function()
      local name, ns = statefulset_view.getCurrentSelection()
      buffers.confirmation_buffer(
        "Are you sure that you want to restart the statefulset: " .. name,
        "prompt",
        function(confirm)
          if confirm then
            commands.run_async("restart_async", {
              gvk = statefulset_view.definition.gvk,
              name = name,
              namespace = ns,
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
  mappings.map_if_plug_not_set("n", "gss", "<Plug>(kubectl.scale)")
end

return M
