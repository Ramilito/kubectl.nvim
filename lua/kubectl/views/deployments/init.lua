local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local resource = "deployments"
local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    gvk = { g = "apps", v = "v1", k = "deployment" },
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
  ResourceBuilder:view(M.definition, cancellationToken)
end

function M.Draw(cancellationToken)
  if state.instance[M.definition.resource] then
    state.instance[M.definition.resource]:draw(M.definition, cancellationToken)
  end
end

function M.SetImage(name, ns)
  local builder = ResourceBuilder:new("deployment_scale")

  local def = {
    ft = "k8s_action",
    display = "Set image: " .. name .. "-" .. "?",
    resource = name,
    ns = ns,
    group = M.definition.group,
    version = M.definition.version,
  }

  commands.run_async("get_single_async", { M.definition.gvk.k, ns, name, "Json" }, function(data)
    if not data then
      return
    end
    builder.data = data
    builder:decodeJson()

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
      table.insert(builder.data, " ")
      builder:action_view(def, params, function(args)
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
    resource = M.definition.resource .. " | " .. name .. " | " .. ns,
    ft = "k8s_desc",
    syntax = "yaml",
    cmd = "describe_async",
  }
  ResourceBuilder:view_float(def, {
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
