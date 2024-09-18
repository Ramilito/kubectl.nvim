local api = vim.api
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local deployment_view = require("kubectl.views.deployments")
local loop = require("kubectl.utils.loop")
local overview_view = require("kubectl.views.overview")
local view = require("kubectl.views")

local mappings = require("kubectl.mappings")

mappings.map_if_plug_not_set("n", "gi", "<Plug>(kubectl.set_image)")
mappings.map_if_plug_not_set("n", "grr", "<Plug>(kubectl.rollout_restart)")
mappings.map_if_plug_not_set("n", "gss", "<Plug>(kubectl.scale)")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.select)", "", {
    noremap = true,
    silent = true,
    desc = "Go to pods",
    callback = function()
      local name, ns = deployment_view.getCurrentSelection()
      view.set_and_open_pod_selector("deployments", name, ns)
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.go_up)", "", {
    noremap = true,
    silent = true,
    desc = "Go up",
    callback = function()
      overview_view.View()
    end,
  })

  -- Only works _if_ their is only _one_ container and that image is the _same_ as the deployment
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.set_image)", "", {
    noremap = true,
    silent = true,
    desc = "Set image",
    callback = function()
      local name, ns = deployment_view.getCurrentSelection()
      local container_images = {}
      local get_images_args = {
        "get",
        "deploy",
        name,
        "-n",
        ns,
        '--output=jsonpath={range .spec.template.spec.containers[*]}{.image}{"\\n"}{end}',
      }

      local images = vim.split(commands.shell_command("kubectl", get_images_args), "\n")
      for _, image in ipairs(images) do
        if image ~= "" then
          table.insert(container_images, image)
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
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.scale)", "", {
    noremap = true,
    silent = true,
    desc = "Scale replicas",
    callback = function()
      local name, ns = deployment_view.getCurrentSelection()

      local current_replicas =
        commands.shell_command("kubectl", { "get", "deploy", name, "-n", ns, "-o", "jsonpath={.spec.replicas}" })
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

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.rollout_restart)", "", {
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
