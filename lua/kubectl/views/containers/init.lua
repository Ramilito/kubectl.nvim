local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.containers.definition")

local M = { is_tailing = false, tail_handle = nil }
M.selection = {}

function M.selectContainer(name)
  M.selection = name
end

function M.View(pod, ns)
  definition.display_name = pod
  definition.url = { "{{BASE}}/api/v1/namespaces/" .. ns .. "/pods/" .. pod }

  ResourceBuilder:view_float(definition)
end

function M.tailLogs(pod, ns)
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(buf), 0 })

  local function handle_output(data)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        local line_count = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, vim.split(data, "\n"))
        vim.api.nvim_set_option_value("modified", false, { buf = buf })
        vim.api.nvim_win_set_cursor(0, { line_count + 1, 0 })
      end
    end)
  end

  local function stop_tailing(handle)
    handle:kill(2)
    vim.notify("Stopped tailing : " .. pod .. "-c " .. M.selection, vim.log.levels.INFO)
  end

  local should_tail = not M.is_tailing
  local group = vim.api.nvim_create_augroup("__kubectl_tailing", { clear = false })
  if should_tail then
    M.is_tailing = true
    local args = { "logs", "--follow", "--since=1s", pod, "-c", M.selection, "-n", ns }
    M.tail_handle = commands.shell_command_async("kubectl", args, nil, handle_output)

    vim.notify("Start tailing : " .. pod .. "-c " .. M.selection, vim.log.levels.INFO)
    vim.api.nvim_create_autocmd("BufWinLeave", {
      group = group,
      buffer = buf,
      callback = function()
        stop_tailing(M.tail_handle)
      end,
    })
  else
    M.is_tailing = false
    vim.api.nvim_clear_autocmds({ group = group })
    stop_tailing(M.tail_handle)
  end
end

function M.exec(pod, ns)
  buffers.floating_buffer("k8s_container_exec", "ssh " .. M.selection)
  commands.execute_terminal("kubectl", { "exec", "-it", pod, "-n", ns, "-c ", M.selection, "--", "/bin/sh" })
end

function M.logs(pod, ns)
  ResourceBuilder:view_float({
    resource = "containerLogs",
    ft = "k8s_container_logs",
    url = {
      "{{BASE}}/api/v1/namespaces/" .. ns .. "/pods/" .. pod .. "/log/?container=" .. M.selection .. "&pretty=true",
    },
    syntax = "less",
    hints = {
      { key = "<f>", desc = "Follow" },
      { key = "<gw>", desc = "Wrap" },
    },
  })
end

return M
