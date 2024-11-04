local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local definition = require("kubectl.views.containers.definition")

local M = {
  selection = {},
  log_since = config.options.logs.since,
  show_previous = "false",
}

function M.selectContainer(name)
  M.selection = name
end

function M.View(pod, ns)
  definition.display_name = pod
  definition.url = { "{{BASE}}/api/v1/namespaces/" .. ns .. "/pods/" .. pod }

  ResourceBuilder:view_float(definition)
end

function M.exec(pod, ns)
  buffers.floating_buffer("k8s_container_exec", "ssh " .. M.selection)
  commands.execute_terminal("kubectl", { "exec", "-it", pod, "-n", ns, "-c ", M.selection, "--", "/bin/sh" })
end

function M.debug(pod, ns)
  local builder = ResourceBuilder:new("kubectl_debug")

  local debug_def = {
    ft = "k8s_container_debug",
    display = "Debug: " .. pod .. "-" .. M.selection .. "?",
    resource = pod,
    cmd = { "debug", pod, "-n", ns },
  }
  local data = {
    { text = "name:", value = M.selection .. "-debug", cmd = "-c" },
    { text = "image:", value = "busybox", cmd = "--image" },
    { text = "stdin", enum = { "true", "false" }, cmd = "--stdin" },
    { text = "tty", enum = { "true", "false" }, cmd = "--tty" },
    { text = "shell", enum = { "/bin/sh", "/bin/bash" }, cmd = "--" },
  }

  builder:action_view(debug_def, data, function(args)
    vim.schedule(function()
      buffers.floating_buffer(debug_def.ft, "debug " .. M.selection)
      commands.execute_terminal("kubectl", args)
    end)
  end)
end

function M.logs(pod, ns, reload)
  local since_last_char = string.sub(M.log_since, -1)
  if since_last_char == "s" then
    M.log_since = string.sub(M.log_since, 1, -2)
  elseif since_last_char == "m" then
    M.log_since = tostring(tonumber(string.sub(M.log_since, 1, -2)) * 60)
  elseif since_last_char == "h" then
    M.log_since = tostring(tonumber(string.sub(M.log_since, 1, -2)) * 60 * 60)
  end
  ResourceBuilder:view_float({
    resource = "containerLogs",
    ft = "k8s_container_logs",
    url = {
      "{{BASE}}/api/v1/namespaces/"
        .. ns
        .. "/pods/"
        .. pod
        .. "/log/?container="
        .. M.selection
        .. "&pretty=true"
        .. "&sinceSeconds="
        .. M.log_since
        .. "&previous="
        .. M.show_previous,
    },
    syntax = "less",
    hints = {
      { key = "<Plug>(kubectl.follow)", desc = "Follow" },
      { key = "<Plug>(kubectl.history)", desc = "History [" .. M.log_since .. "]" },
      { key = "<Plug>(kubectl.wrap)", desc = "Wrap" },
      { key = "<Plug>(kubectl.previous_logs)", desc = "Previous[" .. M.show_previous .. "]" },
    },
  }, { reload = reload })
end

return M
