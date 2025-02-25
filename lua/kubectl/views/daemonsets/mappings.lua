local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local daemonset_def = require("kubectl.views.daemonsets.definition")
local daemonset_view = require("kubectl.views.daemonsets")
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
      local name, ns = daemonset_view.getCurrentSelection()
      state.setFilter("")
      view.set_and_open_pod_selector(name, ns)
    end,
  },
  -- Only works _if_ there is only _one_ container and that image is the _same_ as the daemonset
  ["<Plug>(kubectl.set_image)"] = {
    noremap = true,
    silent = true,
    desc = "Set image",
    callback = function()
      local name, ns = daemonset_view.getCurrentSelection()
      local resource = tables.find_resource(state.instance[daemonset_def.resource].data, name, ns)
      if not resource then
        return
      end

      local containers = {}

      for _, container in ipairs(resource.spec.template.spec.containers) do
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
  },
  ["<Plug>(kubectl.rollout_restart)"] = {
    noremap = true,
    silent = true,
    desc = "Rollout restart",
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
  },
}

M.register = function()
  mappings.map_if_plug_not_set("n", "gi", "<Plug>(kubectl.set_image)")
  mappings.map_if_plug_not_set("n", "grr", "<Plug>(kubectl.rollout_restart)")
end

return M
