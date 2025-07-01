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
  builder.view_float(M.definition, { args = { kind = gvk.k, name = pod, namespace = ns } })
end

local function attach_session(sess, buf, win)
  local chan = vim.api.nvim_open_term(buf, {
    on_input = function(_, _, _, data)
      sess:write(data)
    end,
  })
  vim.cmd.startinsert()

  local timer = vim.uv.new_timer()
  if not timer then
    vim.notify("kubectl‑client error: could not create timer", vim.log.levels.ERROR)
    return
  end
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
      if not sess:open() and timer and not timer:is_closing() then
        timer:stop()
        timer:close()
        vim.api.nvim_chan_send(chan, "\r\n[process exited]\r\n")
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end
    end)
  )
end

local function spawn_terminal(title, key, fn, ...)
  local ok, sess = pcall(fn, ...)
  if not ok or sess == nil then
    vim.notify("kubectl‑client error: " .. tostring(sess), vim.log.levels.ERROR)
    return
  end
  local buf, win = buffers.tab_buffer(key, title)
  attach_session(sess, buf, win)
end

function M.exec(pod, ns)
  if config.options.terminal_cmd then
    local args = { "exec", "-it", pod, "-n", ns, "-c", M.selection, "--", "/bin/sh" }
    local cmd = commands.configure_command("kubectl", {}, args)
    vim.fn.jobstart(config.options.terminal_cmd .. " " .. table.concat(cmd.args, " "))
    return
  end

  spawn_terminal(
    string.format("%s: %s | %s", pod, M.selection, ns),
    "k8s_container_exec",
    client.exec,
    ns,
    pod,
    M.selection,
    { "sh", "-c", "command -v bash >/dev/null 2>&1 && exec bash || exec sh" }
  )
end

function M.debug(pod, ns)
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

<<<<<<< HEAD
  builder.action_view(def, data, function(_args)
    print("args: " .. vim.inspect(_args))
||||||| 32e660a
  builder.action_view(def, data, function(args)
=======
  builder.action_view(def, data, function(_args)
>>>>>>> rami/v2.0.0
    vim.schedule(function()
      spawn_terminal(
        string.format("%s: %s | %s", pod, M.selection, ns),
        "k8s_container_debug",
        client.debug, -- fn
        ns,
        pod,
        "busybox",
        M.selection
      )
    end)
  end)
end

return M
