local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.pods.definition")

local M = {}
M.selection = {}

function M.View(cancellationToken)
  ResourceBuilder:new("pods")
    :setCmd({
      "{{BASE}}/api/v1/{{NAMESPACE}}pods?pretty=false",
      "-w",
      "\n",
    }, "curl")
    :fetchAsync(function(self)
      self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders)
      vim.schedule(function()
        self
          :addHints({
            { key = "<l>", desc = "logs" },
            { key = "<d>", desc = "describe" },
            { key = "<t>", desc = "top" },
            { key = "<enter>", desc = "containers" },
            { key = "<shift-f>", desc = "port forward" },
            { key = "<C-k>", desc = "kill pod" },
          }, true, true)
          :display("k8s_pods", "Pods", cancellationToken)
      end)
    end)
end

function M.PodTop()
  ResourceBuilder:new("top"):setCmd({ "top", "pods", "-A" }):fetchAsync(function(self)
    vim.schedule(function()
      self:splitData():displayFloat("k8s_top", "Top", "")
    end)
  end)
end

function M.TailLogs()
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

  local args = { "logs", "--follow", "--since=1s", M.selection.pod, "-n", M.selection.ns }
  local handle = commands.shell_command_async("kubectl", args, nil, handle_output)

  vim.notify("Start tailing: " .. M.selection.pod, vim.log.levels.INFO)
  vim.api.nvim_create_autocmd("BufWinLeave", {
    buffer = buf,
    callback = function()
      handle:kill(2)
      vim.notify("Stopped tailing: " .. M.selection.pod, vim.log.levels.INFO)
    end,
  })
end

function M.selectPod(pod_name, namespace)
  M.selection = { pod = pod_name, ns = namespace }
end

function M.PodLogs()
  ResourceBuilder:new("logs")
    :displayFloat("k8s_pod_logs", M.selection.pod, "less")
    :setCmd({
      "{{BASE}}/api/v1/namespaces/" .. M.selection.ns .. "/pods/" .. M.selection.pod .. "/log" .. "?pretty=true",
    }, "curl", "text/html")
    :fetchAsync(function(self)
      self:splitData()
      vim.schedule(function()
        self
          :addHints({
            { key = "<f>", desc = "Follow" },
          }, false, false)
          :displayFloat("k8s_pod_logs", M.selection.pod, "less")
      end)
    end)
end

function M.Edit(name, namespace)
  buffers.floating_buffer({}, {}, "k8s_pod_edit", { title = name, syntax = "yaml" })
  commands.execute_terminal("kubectl", { "edit", "pod/" .. name, "-n", namespace })
end

function M.PodDesc(pod_name, namespace)
  ResourceBuilder:new("desc")
    :displayFloat("k8s_pod_desc", pod_name, "yaml")
    :setCmd({ "describe", "pod", pod_name, "-n", namespace })
    :fetchAsync(function(self)
      self:splitData()
      vim.schedule(function()
        self:displayFloat("k8s_pod_desc", pod_name, "yaml")
      end)
    end)
end

return M
