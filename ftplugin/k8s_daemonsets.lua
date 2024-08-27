local api = vim.api
local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local daemonset_view = require("kubectl.views.daemonsets")
local definition = require("kubectl.views.daemonsets.definition")
local loop = require("kubectl.utils.loop")
local root_view = require("kubectl.views.root")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  local config = require("kubectl.config")
  local gl = config.options.keymaps.global
  local ds = config.options.keymaps.daemonsets
  api.nvim_buf_set_keymap(bufnr, "n", gl.help.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(gl.help),
    callback = function()
      view.Hints(definition.hints)
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", ds.view_pods.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(ds.view_pods),
    callback = function()
      local name, ns = daemonset_view.getCurrentSelection()
      view.set_and_open_pod_selector("daemonsets", name, ns)
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", gl.go_up.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(gl.go_up),
    callback = function()
      root_view.View()
    end,
  })

  -- Only works _if_ there is only _one_ container and that image is the _same_ as the daemonset
  api.nvim_buf_set_keymap(bufnr, "n", ds.set_image.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(ds.set_image),
    callback = function()
      local name, ns = daemonset_view.getCurrentSelection()

      local self = ResourceBuilder:new("daemonset_images")
        :setCmd({
          "{{BASE}}/apis/apps/v1/namespaces/" .. ns .. "/daemonsets/" .. name .. "?pretty=false",
        }, "curl")
        :fetch()
        :decodeJson()

      local containers = {}

      for _, container in ipairs(self.data.spec.template.spec.containers) do
        table.insert(containers, { image = container.image, name = container.name })
      end

      if #containers > 1 then
        vim.notify("Setting new container image for multiple containers are NOT supported yet", vim.log.levels.WARN)
      else
        vim.ui.input({ prompt = "Update image ", default = containers[1].image }, function(input)
          if input ~= nil then
            buffers.confirmation_buffer("Are you sure that you want to update the image?", "prompt", function(confirm)
              if confirm then
                local set_image = { "set", "image", "daemonset/" .. name, containers[1].name .. "=" .. input, "-n", ns }
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

  api.nvim_buf_set_keymap(bufnr, "n", ds.restart.key, "", {
    noremap = true,
    silent = true,
    desc = config.get_desc(ds.restart),
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
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(daemonset_view.Draw)
  end
end

init()
