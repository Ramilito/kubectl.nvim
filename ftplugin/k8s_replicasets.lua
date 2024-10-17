local api = vim.api
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local loop = require("kubectl.utils.loop")
local replicaset_view = require("kubectl.views.replicasets")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views")

local mappings = require("kubectl.mappings")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.select)", "", {
    noremap = true,
    silent = true,
    desc = "Go to pods",
    callback = function()
      local name, ns = replicaset_view.getCurrentSelection()
      state.setFilter("")
      view.set_and_open_pod_selector(name, ns)
    end,
  })

  -- Only works _if_ their is only _one_ container and that image is the _same_ as the replicaset
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.set_image)", "", {
    noremap = true,
    silent = true,
    desc = "Set image",
    callback = function()
      local name, ns = replicaset_view.getCurrentSelection()
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
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.scale)", "", {
    noremap = true,
    silent = true,
    desc = "Scale replicas",
    callback = function()
      local name, ns = replicaset_view.getCurrentSelection()
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
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.rollout_restart)", "", {
    noremap = true,
    silent = true,
    desc = "Rollout restart",
    callback = function()
      local name, ns = replicaset_view.getCurrentSelection()
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
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(replicaset_view.Draw)
  end
end

init()

vim.schedule(function()
  mappings.map_if_plug_not_set("n", "gi", "<Plug>(kubectl.set_image)")
  mappings.map_if_plug_not_set("n", "grr", "<Plug>(kubectl.rollout_restart)")
  mappings.map_if_plug_not_set("n", "gss", "<Plug>(kubectl.scale)")
end)
