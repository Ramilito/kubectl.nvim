local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local deployment_view = require("kubectl.resources.deployments")
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
    callback = mapping_helpers.safe_callback(deployment_view, deployment_view.SetImage),
  },

  ["<Plug>(kubectl.scale)"] = {
    noremap = true,
    silent = true,
    desc = "Scale replicas",
    callback = function()
      local name, ns = deployment_view.getCurrentSelection()
      local builder = manager.get_or_create("deployment_scale")
      commands.run_async(
        "get_single_async",
        { gvk = deployment_view.definition.gvk, namespace = ns, name = name, output = "Json" },
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
                string.format("Are you sure that you want to scale the deployment to %s replicas?", input),
                "prompt",
                function(confirm)
                  if not confirm then
                    return
                  end

                  commands.run_async("scale_async", {
                    gvk = deployment_view.definition.gvk,
                    name = name,
                    namespace = ns,
                    replicas = tonumber(input),
                  }, function(result, err)
                    vim.schedule(function()
                      if err then
                        vim.notify("could not scale resource: ", err)
                      else
                        vim.notify(result)
                      end
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
      local name, ns = deployment_view.getCurrentSelection()
      local builder = manager.get_or_create("deployment_restart")

      local def = {
        resource = "deployment_restart",
        display = "Restart deployment",
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
          gvk = deployment_view.definition.gvk,
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
  mappings.map_if_plug_not_set("n", "gss", "<Plug>(kubectl.scale)")
end

return M
