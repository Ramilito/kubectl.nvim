local commands = require("kubectl.actions.commands")
local manager = require("kubectl.resource_manager")

local M = {}

local client_methods = {
  deployment = "deployment_set_images",
  daemonset = "daemonset_set_images",
  statefulset = "statefulset_set_images",
}

--- Set image action for deployment-like resources
---@param resource_type string "deployment" | "daemonset" | "statefulset"
---@param gvk table The GVK for the resource
---@param name string Resource name
---@param ns string Resource namespace
function M.set_image(resource_type, gvk, name, ns)
  local def = {
    resource = resource_type .. "_set_image",
    display = "Set image: " .. name .. "-" .. "?",
    ft = "k8s_action",
    ns = ns,
  }
  local builder = manager.get_or_create(def.resource)

  commands.run_async("get_single_async", { gvk = gvk, namespace = ns, name = name, output = "Json" }, function(data)
    if not data then
      return
    end
    builder.data = data
    builder.decodeJson()

    local container_images = {}
    if builder.data.spec.template.spec.containers then
      for _, container in ipairs(builder.data.spec.template.spec.containers) do
        table.insert(container_images, { name = container.name, image = container.image, init = false })
      end
    end

    if builder.data.spec.template.spec.initContainers then
      for _, container in ipairs(builder.data.spec.template.spec.initContainers) do
        table.insert(container_images, { name = container.name, image = container.image, init = true })
      end
    end

    vim.schedule(function()
      local params = {}
      for _, container in ipairs(container_images) do
        table.insert(params, {
          text = container.name,
          value = container.image,
          init = container.init,
          options = {},
          type = "positional",
        })
      end

      builder.data = {}
      builder.action_view(def, params, function(args)
        local image_spec = {}
        for _, container in ipairs(args) do
          table.insert(image_spec, {
            name = container.text,
            image = container.value,
            init = container.init,
          })
        end

        local client = require("kubectl.client")
        local method = client_methods[resource_type]
        local status = client[method](name, ns, image_spec)
        if status then
          vim.notify(status)
        end
      end)
    end)
  end)
end

return M
