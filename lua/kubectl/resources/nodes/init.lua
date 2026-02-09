local BaseResource = require("kubectl.resources.base_resource")
local commands = require("kubectl.actions.commands")
local hl = require("kubectl.actions.highlight")
local kubectl_client = require("kubectl.client")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local terminal = require("kubectl.utils.terminal")

local resource = "nodes"

local M = BaseResource.extend({
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
    { key = "<Plug>(kubectl.shell)", desc = "shell", long_desc = "Shell into selected node" },
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
})

function M.Drain(node)
  local builder = manager.get(M.definition.resource)
  local node_def = {
    ft = "k8s_action",
    display = "Drain node: " .. node .. "?",
    resource = node,
  }
  local data = {
    { text = "grace period:", value = "-1", type = "option", hl = hl.symbols.pending },
    { text = "timeout sec:", value = "5", type = "option", hl = hl.symbols.pending },
    { text = "ignore daemonset:", value = "false", type = "flag", hl = hl.symbols.pending },
    { text = "delete emptydir data:", value = "false", type = "flag", hl = hl.symbols.pending },
    { text = "force:", value = "false", type = "flag", hl = hl.symbols.pending },
    { text = "dry run:", value = "false", type = "flag", hl = hl.symbols.pending },
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

function M.Shell(node)
  local def = {
    resource = "node_shell",
    ft = "k8s_action",
    display = "Shell into node: " .. node .. "?",
  }

  local builder = manager.get_or_create(def.resource)

  local data = {
    { text = "namespace:", value = "default", type = "option", hl = hl.symbols.pending },
    { text = "image:", value = "busybox:latest", type = "option", hl = hl.symbols.pending },
    { text = "cpu limit:", value = "", type = "option", hl = hl.symbols.pending },
    { text = "mem limit:", value = "", type = "option", hl = hl.symbols.pending },
  }

  builder.action_view(def, data, function(args)
    vim.schedule(function()
      local shell_config = {
        node = node,
        namespace = args[1].value,
        image = args[2].value,
        cpu_limit = args[3].value ~= "" and args[3].value or nil,
        mem_limit = args[4].value ~= "" and args[4].value or nil,
      }
      terminal.spawn_terminal(
        string.format("node-shell | %s", node),
        "k8s_node_shell",
        kubectl_client.node_shell,
        false,
        shell_config
      )
    end)
  end)
end

return M
