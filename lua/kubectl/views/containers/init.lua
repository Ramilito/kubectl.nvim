local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local definition = require("kubectl.views.containers.definition")
local pod_view = require("kubectl.views.pods")

local M = {
  selection = {},
  definition = {
    ft = "k8s_" .. "containers",
    gvk = { g = pod_view.definition.gvk.g, v = pod_view.definition.gvk.v, k = pod_view.definition.gvk.k },
    headers = {
      "NAME",
      "IMAGE",
      "READY",
      "STATE",
      "TYPE",
      "RESTARTS",
      "PORTS",
      "AGE",
    },
    processRow = definition.processRow,
    cmd = "get_async",
    hints = {
      { key = "<Plug>(kubectl.logs)", desc = "logs" },
      { key = "<Plug>(kubectl.debug)", desc = "debug" },
      { key = "<Plug>(kubectl.select)", desc = "exec" },
    },
  },
  log_since = config.options.logs.since,
  show_previous = "false",
}

function M.selectContainer(name)
  M.selection = name
end

function M.View(pod, ns)
  M.definition.display_name = pod
  M.definition.resource = "pods | " .. pod .. " | " .. ns
  local gvk = M.definition.gvk

  ResourceBuilder:view_float(M.definition, { args = { gvk.k, ns, pod, "json" } })
end

function M.exec(pod, ns)
  local args = { "exec", "-it", pod, "-n", ns, "-c ", M.selection, "--", "/bin/sh" }
  local cmd = "kubectl"

  if config.options.terminal_cmd then
    local command = commands.configure_command(cmd, {}, args)
    vim.fn.jobstart(config.options.terminal_cmd .. " " .. table.concat(command.args, " "))
  else
    buffers.floating_buffer("k8s_container_exec", pod .. ": " .. M.selection .. " | " .. ns)

    -- local client = require("kubectl.client")
    -- client.exec(pod, { "sh", "-c", "echo echo Hello from Lua; exec /bin/sh" })
    commands.execute_terminal(cmd, args)
  end
end

function M.debug(pod, ns)
  local builder = ResourceBuilder:new("kubectl_debug")

  local debug_def = {
    ft = "k8s_action",
    display = "Debug: " .. pod .. "-" .. M.selection .. "?",
    resource = pod,
    cmd = { "debug", pod, "-n", ns },
  }
  local data = {
    { text = "name:", value = M.selection .. "-debug", cmd = "-c", type = "option" },
    { text = "image:", value = "busybox", cmd = "--image", type = "option" },
    { text = "stdin:", value = "true", cmd = "--stdin", type = "flag" },
    { text = "tty:", value = "true", cmd = "--tty", type = "flag" },
    { text = "shell:", value = "/bin/sh", options = { "/bin/sh", "/bin/bash" }, cmd = "--", type = "positional" },
  }

  builder:action_view(debug_def, data, function(args)
    vim.schedule(function()
      buffers.floating_buffer(debug_def.ft, "debug " .. M.selection)
      commands.execute_terminal("kubectl", args)
    end)
  end)
end

return M
