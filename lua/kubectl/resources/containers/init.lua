local buffers = require("kubectl.actions.buffers")
local client = require("kubectl.client")
local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local definition = require("kubectl.resources.containers.definition")
local manager = require("kubectl.resource_manager")
local pod_view = require("kubectl.resources.pods")

local resource = "containers"

local M = {
  selection = {},
  definition = {
    resource = resource,
    ft = "k8s_" .. resource,
    gvk = { g = pod_view.definition.gvk.g, v = pod_view.definition.gvk.v, k = pod_view.definition.gvk.k },
    headers = {
      "NAME",
      "IMAGE",
      "READY",
      "STATE",
      "TYPE",
      "RESTARTS",
      "PORTS",
      "CPU",
      "MEM",
      "CPU/RL",
      "MEM/RL",
      "%CPU/R",
      "%CPU/L",
      "%MEM/R",
      "%MEM/L",
      "AGE",
    },
    processRow = definition.processRow,
    cmd = "get_container_table_async",
    hints = {
      { key = "<Plug>(kubectl.logs)", desc = "logs" },
      { key = "<Plug>(kubectl.debug)", desc = "debug" },
      { key = "<Plug>(kubectl.select)", desc = "exec" },
      { key = "<Plug>(kubectl.select_fullscreen)", desc = "exec" },
    },
  },
  log_since = config.options.logs.since,
  show_previous = "false",
}

function M.selectContainer(name)
  M.selection = name
end

function M.View(pod, ns)
  M.definition.display_name = "pods | " .. pod .. " | " .. ns
  local gvk = M.definition.gvk
  local builder = manager.get_or_create(M.definition.resource)
  builder.view_float(M.definition, { args = { gvk = gvk, name = pod, namespace = ns } })
end

local function attach_session(sess, buf, win)
  local chan = vim.api.nvim_open_term(buf, {
    on_input = function(_, _, _, data)
      sess:write(data)
    end,
  })
  vim.cmd.startinsert()

  local timer = vim.uv.new_timer()
  timer:start(
    0,
    30,
    vim.schedule_wrap(function()
      repeat
        local chunk = sess:read_chunk()
        if chunk then
          vim.api.nvim_chan_send(chan, chunk)
        end
      until not chunk
      if not sess:open() then
        timer:stop()
        if not timer:is_closing() then
          timer:close()
        end
        vim.api.nvim_chan_send(chan, "\r\n[process exited]\r\n")
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end
    end)
  )
end

local function spawn_terminal(title, key, fn, is_fullscreen, ...)
  local ok, sess = pcall(fn, ...)
  if not ok or sess == nil then
    vim.notify("kubectl‑client error: " .. tostring(sess), vim.log.levels.ERROR)
    return
  end
  local buf, win
  local state = require("kubectl.state")
  if is_fullscreen then
    buf, win = buffers.buffer(key, title)
    state.set_buffer_state(buf, title, buffers.buffer, { key, title })
  else
    buf, win = buffers.floating_buffer(key, title)
    state.set_buffer_state(buf, title, buffers.floating_buffer, { key, title })
  end

  vim.api.nvim_set_current_buf(buf)
  vim.schedule(function()
    attach_session(sess, buf, win)
  end)
end

function M.exec(pod, ns, is_fullscreen)
  if config.options.terminal_cmd then
    local args = { "exec", "-it", pod, "-n", ns, "-c", M.selection, "--", "/bin/sh" }
    local cmd = commands.configure_command("kubectl", {}, args)
    vim.fn.jobstart(config.options.terminal_cmd .. " " .. table.concat(cmd.args, " "))
    return
  end

  spawn_terminal(
    string.format("%s | %s: %s | %s", "container", pod, M.selection, ns),
    "k8s_exec",
    client.exec,
    is_fullscreen,
    ns,
    pod,
    M.selection,
    { "sh", "-c", "command -v bash >/dev/null 2>&1 && exec bash || exec sh" }
  )
end

function M.debug(pod, ns, is_fullscreen)
  local def = {
    resource = "kubectl_debug",
    ft = "k8s_action",
    display = "Debug: " .. pod .. " - " .. M.selection .. " ?",
    cmd = { "debug", pod, "-n", ns },
  }

  local builder = manager.get_or_create(def.resource)

  local data = {
    { text = "name:", value = M.selection .. "-debug", cmd = "-c", type = "option" },
    { text = "image:", value = "busybox", cmd = "--image", type = "option" },
    { text = "stdin:", value = "true", cmd = "--stdin", type = "flag" },
    { text = "tty:", value = "true", cmd = "--tty", type = "flag" },
    {
      text = "shell:",
      value = "/bin/sh",
      options = { "/bin/sh", "/bin/bash" },
      cmd = "--",
      type = "positional",
    },
  }

  builder.action_view(def, data, function(_args)
    vim.schedule(function()
      spawn_terminal(
        string.format("%s | %s: %s | %s", "container", pod, M.selection, ns),
        "k8s_debug",
        client.debug,
        is_fullscreen,
        ns,
        pod,
        "busybox",
        M.selection
      )
    end)
  end)
end

return M
