local ResourceBuilder = require("kubectl.resourcebuilder")
local actions = require("kubectl.actions.actions")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.pods.definition")

local M = {}
M.selection = {}

function M.selectContainer(name)
  M.selection = name
end

function M.podContainers(pod, ns)
  ResourceBuilder:new("containers", { "get", "pods", pod, "-n", ns, "-o=json" })
    :fetch()
    :decodeJson()
    :process(definition.processContainerRow)
    :prettyPrint(definition.getContainerHeaders)
    :addHints({
      { key = "<l>", desc = "logs" },
      { key = "<enter>", desc = "exec" },
    }, false, false)
    :displayFloat("k8s_containers", pod, "", true)
end

function M.tailContainerLogs(pod, ns)
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(buf), 0 })

  local function handle_output(data)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        local line_count = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, { data })
        vim.api.nvim_set_option_value("modified", false, { buf = buf })
        vim.api.nvim_win_set_cursor(0, { line_count + 1, 0 })
      end
    end)
  end

  local args = { "logs", "--follow", "--since=1s", pod, "-c", M.selection, "-n", ns }
  commands.shell_command("kubectl", args, handle_output)
end

function M.execContainer(pod, ns)
  actions.floating_buffer({ "" }, "k8s_container_exec", { title = "ssh " .. M.selection })
  commands.execute_terminal("kubectl", { "exec", "-it", pod, "-n", ns, "-c ", M.selection, "--", "/bin/sh" })
end

function M.containerLogs(pod, ns)
  ResourceBuilder:new("containerLogs", { "logs", pod, "-n", ns, "-c", M.selection })
    :fetch()
    :splitData()
    :addHints({
      { key = "<f>", desc = "Follow" },
    }, false, false)
    :displayFloat("k8s_container_logs", "logs" .. pod, "less")
end

return M
