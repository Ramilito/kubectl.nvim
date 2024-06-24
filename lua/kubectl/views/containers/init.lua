local ResourceBuilder = require("kubectl.resourcebuilder")
local actions = require("kubectl.actions.actions")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.containers.definition")

local M = {}
M.selection = {}

function M.selectContainer(name)
  M.selection = name
end

function M.containers(pod, ns)
  ResourceBuilder:new("containers", { "get", "--raw", "/api/v1/namespaces/" .. ns .. "/pods/" .. pod }):fetchAsync(function(self)
    self:decodeJson():process(definition.processContainerRow):prettyPrint(definition.getContainerHeaders)

    vim.schedule(function()
      self
        :addHints({
          { key = "<l>", desc = "logs" },
          { key = "<enter>", desc = "exec" },
        }, false, false)
        :displayFloat("k8s_containers", pod, "", true)
    end)
  end)
end

function M.tailLogs(pod, ns)
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

  local args = "logs --follow --since=1s " .. pod .. " -c " .. M.selection .. " -n " .. ns
  commands.shell_command_async("kubectl", args, handle_output)
end

function M.exec(pod, ns)
  actions.floating_buffer({ "" }, "k8s_container_exec", { title = "ssh " .. M.selection })
  commands.execute_terminal("kubectl", { "exec", "-it", pod, "-n", ns, "-c ", M.selection, "--", "/bin/sh" })
end

function M.logs(pod, ns)
  ResourceBuilder
    :new("containerLogs", { "get", "--raw", "/api/v1/namespaces/" .. ns .. "/pods/" .. pod .. "/log/?container=" .. M.selection })
    :fetchAsync(function(self)
      self:splitData()
      vim.schedule(function()
        self
          :addHints({
            { key = "<f>", desc = "Follow" },
          }, false, false)
          :displayFloat("k8s_container_logs", "logs" .. pod, "less")
      end)
    end)
end

return M
