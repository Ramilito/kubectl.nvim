local buffers = require("kubectl.actions.buffers")
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

function M.exec(pod, ns)
  if config.options.terminal_cmd then
    local args = { "exec", "-it", pod, "-n", ns, "-c ", M.selection, "--", "/bin/sh" }
    local command = commands.configure_command("kubectl", {}, args)
    vim.fn.jobstart(config.options.terminal_cmd .. " " .. table.concat(command.args, " "))
  else
    local client = require("kubectl.client")
    local buf, win = buffers.tab_buffer("k8s_container_exec", pod .. ": " .. M.selection .. " | " .. ns)
    local ok, sess = pcall(client.exec, ns, pod, M.selection, { "/bin/sh" })
    if not ok then
      vim.notify(sess, vim.log.levels.ERROR)
      return
    elseif sess == nil then
      vim.notify("exec failed: " .. tostring(sess), vim.log.levels.ERROR)
      return
    end
    local chan = vim.api.nvim_open_term(buf, {
      on_input = function(_, _, _, bytes)
        sess:write(bytes)
      end,
    })
    vim.cmd.startinsert()

    local timer = vim.uv.new_timer()
    timer:start(
      0,
      30,
      vim.schedule_wrap(function()
        while true do
          local chunk = sess:read_chunk()
          if chunk then
            vim.api.nvim_chan_send(chan, chunk)
          else
            break
          end
        end
        -- vim.notify(
        --   "sess:open(): " .. vim.inspect(sess:open()) .. " timer:is_closing(): " .. vim.inspect(timer:is_closing())
        -- )

        -- if not sess:open() and not timer:is_closing() then
        --   timer:stop()
        --   timer:close()
        --   --   vim.api.nvim_chan_send(chan, "\r\n[process exited]\r\n")
        --   --   if vim.api.nvim_win_is_valid(win) then
        --   --     vim.api.nvim_win_close(win, true)
        --   --   end
        -- end
      end)
    )
  end
end

function M.debug(pod, ns)
  local def = {
    resource = "kubectl_debug",
    ft = "k8s_action",
    display = "Debug: " .. pod .. "-" .. M.selection .. "?",
    cmd = { "debug", pod, "-n", ns },
  }

  local builder = manager.get_or_create(def.resource)

  local data = {
    { text = "name:", value = M.selection .. "-debug", cmd = "-c", type = "option" },
    { text = "image:", value = "busybox", cmd = "--image", type = "option" },
    { text = "stdin:", value = "true", cmd = "--stdin", type = "flag" },
    { text = "tty:", value = "true", cmd = "--tty", type = "flag" },
    { text = "shell:", value = "/bin/sh", options = { "/bin/sh", "/bin/bash" }, cmd = "--", type = "positional" },
  }

  builder.action_view(def, data, function(args)
    vim.schedule(function()
      local client = require("kubectl.client")
      local buf, win = buffers.floating_buffer("k8s_container_debug", pod .. ": " .. M.selection .. " | " .. ns)
      -- TODO: connect image from arguments
      local ok, sess = pcall(client.debug, ns, pod, "busybox", M.selection)
      if not ok then
        vim.notify(sess, vim.log.levels.ERROR)
        return
      elseif sess == nil then
        vim.notify("debug failed: " .. tostring(sess), vim.log.levels.ERROR)
        return
      end

      local chan = vim.api.nvim_open_term(buf, {
        on_input = function(_, _, _, bytes)
          sess:write(bytes)
        end,
      })
      vim.cmd.startinsert()

      local timer = vim.uv.new_timer()
      timer:start(
        0,
        30,
        vim.schedule_wrap(function()
          while true do
            local chunk = sess:read_chunk()
            if chunk then
              vim.api.nvim_chan_send(chan, chunk)
            else
              break
            end
          end
          if not sess:open() then
            timer:stop()
            timer:close()
            vim.api.nvim_chan_send(chan, "\r\n[process exited]\r\n")
            if vim.api.nvim_win_is_valid(win) then
              vim.api.nvim_win_close(win, true)
            end
          end
        end)
      )
    end)
  end)
end

return M
