local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local deployment_view = require("kubectl.views.deployments")
local mappings = require("kubectl.mappings")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.select)"] = {
    noremap = true,
    silent = true,
    desc = "Go to pods",
    callback = function()
      local name, ns = deployment_view.getCurrentSelection()
      state.setFilter("")
      view.set_and_open_pod_selector(name, ns)
    end,
  },

  -- Only works _if_ their is only _one_ container and that image is the _same_ as the deployment
  ["<Plug>(kubectl.set_image)"] = {
    noremap = true,
    silent = true,
    desc = "Set image",
    callback = function()
      local name, ns = deployment_view.getCurrentSelection()
      local container_images = {}

      local resource = tables.find_resource(state.instance[deployment_view.definition.resource].data, name, ns)
      if not resource then
        return
      end

      for _, container in ipairs(resource.spec.template.spec.containers) do
        if container.image ~= container_images[1] then
          table.insert(container_images, container.image)
        end
      end

      if #container_images > 1 then
        vim.notify("Setting new container image for multiple containers is NOT supported yet", vim.log.levels.WARN)
      else
        vim.ui.input({ prompt = "Update image ", default = container_images[1] }, function(input)
          if not input then
            return
          end
          buffers.confirmation_buffer("Are you sure that you want to update the image?", "prompt", function(confirm)
            if not confirm then
              return
            end
            local set_image = { "set", "image", "deployment/" .. name, name .. "=" .. input, "-n", ns }
            commands.shell_command_async("kubectl", set_image, function(response)
              vim.schedule(function()
                vim.notify(response)
              end)
            end)
          end)
        end)
      end
    end,
  },

  ["<Plug>(kubectl.scale)"] = {
    noremap = true,
    silent = true,
    desc = "Scale replicas",
    callback = function()
      local name, ns = deployment_view.getCurrentSelection()
      local builder = ResourceBuilder:new("deployment_scale")
      commands.run_async("get_async", { deployment_view.definition.gvk.k, ns, name, "Json" }, function(data)
        if not data then
          return
        end
        builder.data = data
        builder:decodeJson()
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
                  deployment_view.definition.gvk.k,
                  deployment_view.definition.gvk.g,
                  deployment_view.definition.gvk.v,
                  name,
                  ns,
                  input,
                }, function(response)
                  vim.schedule(function()
                    vim.notify(response)
                  end)
                end)
              end
            )
          end)
        end)
      end)
    end,
  },
  ["<Plug>(kubectl.rollout_restart)"] = {
    noremap = true,
    silent = true,
    desc = "Rollout restart",
    callback = function()
      local name, ns = deployment_view.getCurrentSelection()
      buffers.confirmation_buffer(
        "Are you sure that you want to restart the deployment: " .. name,
        "prompt",
        function(confirm)
          if confirm then
            commands.run_async("restart_async", {
              deployment_view.definition.gvk.k,
              deployment_view.definition.gvk.g,
              deployment_view.definition.gvk.v,
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
  mappings.map_if_plug_not_set("n", "gss", "<Plug>(kubectl.scale)")
end

return M
