local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local mappings = require("kubectl.mappings")
local replicaset_view = require("kubectl.views.replicasets")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views")
local err_msg = "Failed to extract ReplicaSet name or namespace."

local M = {}

M.overrides = {
  ["<Plug>(kubectl.select)"] = {
    noremap = true,
    silent = true,
    desc = "Go to pods",
    callback = function()
      local name, ns = replicaset_view.getCurrentSelection()
      if not name or not ns then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      state.setFilter("")
      view.set_and_open_pod_selector(name, ns)
    end,
  },
  -- Only works _if_ their is only _one_ container and that image is the _same_ as the replicaset
  ["<Plug>(kubectl.set_image)"] = {
    noremap = true,
    silent = true,
    desc = "Set image",
    callback = function()
      local name, ns = replicaset_view.getCurrentSelection()
      if not name or not ns then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      local container_images = {}

      local resource = tables.find_resource(state.instance.data, name, ns)
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
            local set_image = { "set", "image", "replicaset/" .. name, name .. "=" .. input, "-n", ns }
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
      local name, ns = replicaset_view.getCurrentSelection()
      if not name or not ns then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      local resource = tables.find_resource(state.instance.data, name, ns)
      if not resource then
        return
      end

      local current_replicas = tostring(resource.spec.replicas)
      vim.ui.input({ prompt = "Scale replicas: ", default = current_replicas }, function(input)
        if not input then
          return
        end
        buffers.confirmation_buffer(
          string.format("Are you sure that you want to scale the replicaset to %s replicas?", input),
          "prompt",
          function(confirm)
            if not confirm then
              return
            end
            commands.shell_command_async(
              "kubectl",
              { "scale", "replicaset/" .. name, "--replicas=" .. input, "-n", ns },
              function(response)
                vim.schedule(function()
                  vim.notify(response)
                end)
              end
            )
          end
        )
      end)
    end,
  },
  ["<Plug>(kubectl.rollout_restart)"] = {
    noremap = true,
    silent = true,
    desc = "Rollout restart",
    callback = function()
      local name, ns = replicaset_view.getCurrentSelection()
      if not name or not ns then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      buffers.confirmation_buffer(
        "Are you sure that you want to restart the replicaset: " .. name,
        "prompt",
        function(confirm)
          if confirm then
            commands.shell_command_async(
              "kubectl",
              { "rollout", "restart", "replicaset/" .. name, "-n", ns },
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

function M.register()
  mappings.map_if_plug_not_set("n", "gi", "<Plug>(kubectl.set_image)")
  mappings.map_if_plug_not_set("n", "grr", "<Plug>(kubectl.rollout_restart)")
  mappings.map_if_plug_not_set("n", "gss", "<Plug>(kubectl.scale)")
end

return M
