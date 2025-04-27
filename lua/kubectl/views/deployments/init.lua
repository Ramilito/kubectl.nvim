local commands = require("kubectl.actions.commands")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local resource = "deployments"

---@class Module
local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    gvk = { g = "apps", v = "v1", k = "Deployment" },
    hints = {
      { key = "<Plug>(kubectl.set_image)", desc = "set image", long_desc = "Change deployment image" },
      { key = "<Plug>(kubectl.rollout_restart)", desc = "restart", long_desc = "Restart selected deployment" },
      { key = "<Plug>(kubectl.scale)", desc = "scale", long_desc = "Scale replicas" },
      { key = "<Plug>(kubectl.select)", desc = "pods", long_desc = "Opens pods view" },
    },
    headers = {
      "NAMESPACE",
      "NAME",
      "READY",
      "UP-TO-DATE",
      "AVAILABLE",
      "AGE",
    },
  },
}

function M.View(cancellationToken)
  local builder = manager.get_or_create(M.definition.resource)
  builder.view(M.definition, cancellationToken)
end

function M.Draw(cancellationToken)
  local builder = manager.get(M.definition.resource)
  if builder then
    builder.draw(cancellationToken)
  end
end

function M.SetImage(name, ns)
  local def = {
    resource = "deployment_set_image",
    display = "Set image: " .. name .. "-" .. "?",
    ft = "k8s_action",
    ns = ns,
    group = M.definition.group,
    version = M.definition.version,
  }
  local builder = manager.get_or_create(def.resource)

  commands.run_async("get_single_async", { M.definition.gvk.k, ns, name, "Json" }, function(data)
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
        local status = client.deployment_set_images(name, ns, image_spec)
        if status then
          vim.notify(status)
        end
      end)
    end)
  end)
end

function M.Desc(name, ns, reload)
  local def = {
    resource = M.definition.resource .. "_desc",
    display_name = M.definition.resource .. " | " .. name .. " | " .. ns,
    ft = "k8s_desc",
    syntax = "yaml",
    cmd = "describe_async",
  }
  local builder = manager.get_or_create(def.resource)
  builder.view_float(def, {
    args = {
      state.context["current-context"],
      M.definition.resource,
      ns,
      name,
      M.definition.gvk.g,
      M.definition.gvk.v,
    },
    reload = reload,
  })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
