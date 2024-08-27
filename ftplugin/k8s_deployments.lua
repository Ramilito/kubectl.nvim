local api = vim.api
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.deployments.definition")
local deployment_view = require("kubectl.views.deployments")
local loop = require("kubectl.utils.loop")
local root_view = require("kubectl.views.root")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  local config = require("kubectl.config")
  local km = config.options.keymaps
  local gl = km.global
  local dp = km.deployments
  api.nvim_buf_set_keymap(bufnr, "n", gl.help.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(gl.help.key),
    callback = function()
      view.Hints(definition.hints)
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", dp.view_pods.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(dp.view_pods),
    callback = function()
      local name, ns = deployment_view.getCurrentSelection()
      view.set_and_open_pod_selector("deployments", name, ns)
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", gl.go_up.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(gl.go_up.key),
    callback = function()
      root_view.View()
    end,
  })

  -- Only works _if_ their is only _one_ container and that image is the _same_ as the deployment
  api.nvim_buf_set_keymap(bufnr, "n", dp.set_image.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(dp.set_image),
    callback = function()
      local name, ns = deployment_view.getCurrentSelection()

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
  })

  api.nvim_buf_set_keymap(bufnr, "n", dp.scale.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(dp.scale),
    callback = function()
      local name, ns = deployment_view.getCurrentSelection()

      local current_replicas = commands.execute_shell_command(
        "kubectl",
        { "get", "deploy", name, "-n", ns, "-o", 'jsonpath="{.spec.replicas}"' }
      )

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
            commands.shell_command_async(
              "kubectl",
              { "scale", "deployment/" .. name, "--replicas=" .. input, "-n", ns },
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

  api.nvim_buf_set_keymap(bufnr, "n", dp.restart.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(dp.restart),
    callback = function()
      local name, ns = deployment_view.getCurrentSelection()
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
    loop.start_loop(deployment_view.Draw)
  end
end

init()
