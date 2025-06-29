local commands = require("kubectl.actions.commands")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local resource = "nodes"

---@class Module
local M = {
  definition = {
    resource = resource,
    display_name = string.upper(resource),
    ft = "k8s_" .. resource,
    gvk = { g = "", v = "v1", k = "Node" },
    child_view = {
      name = "pods",
      predicate = function(name)
        return "spec.nodeName=" .. name
      end,
    },
    hints = {
      { key = "<Plug>(kubectl.cordon)", desc = "cordon", long_desc = "Cordon selected node" },
      { key = "<Plug>(kubectl.uncordon)", desc = "uncordon", long_desc = "UnCordon selected node" },
      { key = "<Plug>(kubectl.drain)", desc = "drain", long_desc = "Drain selected node" },
    },
    headers = {
      "NAME",
      "STATUS",
      "ROLES",
      "AGE",
      "VERSION",
      "INTERNAL-IP",
      "EXTERNAL-IP",
      "OS-IMAGE",
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

function M.Drain(node)
  local builder = manager.get(M.definition.resource)
  local node_def = {
    ft = "k8s_action",
    display = "Drain node: " .. node .. "?",
    resource = node,
  }
  local data = {
    { text = "grace period:", value = "-1", type = "option" },
    { text = "timeout sec:", value = "5", type = "option" },
    { text = "ignore daemonset:", value = "false", type = "flag" },
    { text = "delete emptydir data:", value = "false", type = "flag" },
    { text = "force:", value = "false", type = "flag" },
    { text = "dry run:", value = "false", type = "flag" },
  }
  if builder then
    builder.action_view(node_def, data, function(args)
      local cmd_args = {
        context = state.context["current-context"],
        node = node,
        grace = args[1].value,
        timeout = args[2].value,
        ignore_ds = args[3].value == "true" and true or false,
        delete_emptydir = args[4].value == "true" and true or false,
        force = args[5].value == "true" and true or false,
        dry_run = args[6].value == "true" and true or false,
      }
      commands.run_async("drain_node_async", cmd_args, function(ok)
        vim.schedule(function()
          vim.notify(ok, vim.log.levels.INFO)
        end)
      end)
    end)
  end
end

function M.UnCordon(node)
  local client = require("kubectl.client")
  local ok = client.uncordon_node(node)
  vim.schedule(function()
    vim.notify(ok, vim.log.levels.INFO)
  end)
end

function M.Cordon(node)
  local client = require("kubectl.client")
  local ok = client.cordon_node(node)
  vim.schedule(function()
    vim.notify(ok, vim.log.levels.INFO)
  end)
end

function M.Desc(node, _, reload)
  local def = {
    resource = M.definition.resource .. "_desc",
    display_name = M.definition.resource .. " |" .. node,
    ft = "k8s_desc",
    syntax = "yaml",
    cmd = "describe_async",
  }

  local builder = manager.get_or_create(def.resource)
  builder.view_float(def, {
    args = {
      context = state.context["current-context"],
      gvk = { k = M.definition.resource, g = M.definition.gvk.g, v = M.definition.gvk.v },
      namespace = nil,
      name = node,
    },
    reload = reload,
  })
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(1)
end

return M
