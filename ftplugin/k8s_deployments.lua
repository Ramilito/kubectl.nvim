local api = vim.api
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local deployment_view = require("kubectl.views.deployments")
local loop = require("kubectl.utils.loop")
local pod_view = require("kubectl.views.pods")
local root_view = require("kubectl.views.root")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "g?", "", {
    noremap = true,
    silent = true,
    desc = "Help",
    callback = function()
      view.Hints({
        { key = "<grr>", desc = "Restart selected deployment" },
        { key = "<gd>", desc = "Describe selected deployment" },
        { key = "<enter>", desc = "Opens pods view" },
      })
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "gd", "", {
    noremap = true,
    silent = true,
    desc = "Describe resource",
    callback = function()
      local namespace, deployment_name = tables.getCurrentSelection(unpack({ 1, 2 }))
      if deployment_name and namespace then
        deployment_view.DeploymentDesc(deployment_name, namespace)
      else
        vim.api.nvim_err_writeln("Failed to describe pod name or namespace.")
      end
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<CR>", "", {
    noremap = true,
    silent = true,
    desc = "Go to pods",
    callback = function()
      pod_view.View()
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<bs>", "", {
    noremap = true,
    silent = true,
    desc = "Go up",
    callback = function()
      root_view.View()
    end,
  })

  -- Only works _if_ their is only _one_ container and that image is the _same_ as the deployment
  api.nvim_buf_set_keymap(bufnr, "n", "gi", "", {
    noremap = true,
    silent = true,
    desc = "Set image",
    callback = function()
      local ns, name = tables.getCurrentSelection(unpack({ 1, 2 }))

      local get_images = "get deploy "
        .. name
        .. " -n "
        .. ns
        .. ' -o jsonpath="{.spec.template.spec.containers[*].image}"'

      local container_images = {}

      for image in commands.execute_shell_command("kubectl", get_images):gmatch("[^\r\n]+") do
        table.insert(container_images, image)
      end

      if #container_images > 1 then
        vim.notify("Setting new container image for multiple containers are NOT supported yet", vim.log.levels.WARN)
      else
        vim.ui.input({ prompt = "Update image", default = container_images[1] }, function(input)
          if input ~= nil then
            buffers.confirmation_buffer("Are you sure that you want to update the image?", "prompt", function(confirm)
              if confirm then
                local set_image = { "set", "image", "deployment/" .. name, name .. "=" .. input, "-n", ns }
                commands.shell_command_async("kubectl", set_image, function(response)
                  vim.schedule(function()
                    vim.notify(response)
                  end)
                end)
              end
            end)
          end
        end)
      end
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "grr", "", {
    noremap = true,
    silent = true,
    desc = "Rollout restart",
    callback = function()
      local ns, name = tables.getCurrentSelection(unpack({ 1, 2 }))
      buffers.confirmation_buffer(
        "Are you sure that you want to restart the deployment: " .. name,
        "prompt",
        function(confirm)
          if confirm then
            commands.shell_command_async(
              "kubectl",
              { "rollout", "restart", "deployment/" .. name, "-n", ns },
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
    loop.start_loop(deployment_view.View)
  end
end

init()
