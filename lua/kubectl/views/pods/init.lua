local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.pods.definition")

local M = {}
M.selection = {}

function M.Pods(cancellationToken)
  ResourceBuilder:new("pods")
    :setCmd({
      "{{BASE}}/api/v1/{{NAMESPACE}}pods?pretty=false",
      "-w",
      "\n",
    }, "curl")
    :fetchAsync(function(self)
      self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders):setFilter()
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
          :postRender()
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
        vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, { data })
        vim.api.nvim_set_option_value("modified", false, { buf = buf })
        vim.api.nvim_win_set_cursor(0, { line_count + 1, 0 })
      end
    end)
  end

  local args = { "logs", "--follow", "--since=1s", M.selection.pod, "-n", M.selection.ns }
  commands.shell_command_async("kubectl", args, handle_output)
end

function M.selectPod(pod_name, namespace)
  M.selection = { pod = pod_name, ns = namespace }
end

function M.PodLogs()
  ResourceBuilder:new("logs")
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

function M.PodDesc(pod_name, namespace)
  ResourceBuilder:new("desc"):setCmd({ "describe", "pod", pod_name, "-n", namespace }):fetchAsync(function(self)
    self:splitData()
    vim.schedule(function()
      self:displayFloat("k8s_pod_desc", pod_name, "yaml")
    end)
  end)
end

return M
