local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.pods.definition")
local timeme = require("kubectl.utils.timeme")

local M = {}
M.selection = {}

function M.Pods(cancellationToken)
  timeme.start()
  ResourceBuilder:new("pods", {
    "{{BASE}}/api/v1/{{NAMESPACE}}pods?pretty=false",
    "-w",
    "\n",
  }):fetchAsync(function(self)
    self:decodeJson():process(definition.processRow):sort():prettyPrint(definition.getHeaders):setFilter()
    vim.schedule(function()
      self
        :addHints({
          { key = "<l>", desc = "logs" },
          { key = "<d>", desc = "describe" },
          { key = "<t>", desc = "top" },
          { key = "<enter>", desc = "containers" },
        }, true, true)
        :display("k8s_pods", "Pods", cancellationToken)
      timeme.stop()
    end)
  end)
end

function M.PodTop()
  ResourceBuilder:new("top", "top pods -A"):fetch():splitData():displayFloat("k8s_top", "Top", "")
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

  local args = "logs --follow --since=1s " .. M.selection.pod .. " -n " .. M.selection.ns
  commands.shell_command_async("kubectl", args, handle_output)
end

function M.selectPod(pod_name, namespace)
  M.selection = { pod = pod_name, ns = namespace }
end

function M.PodLogs()
  ResourceBuilder:new("logs", {
    "{{BASE}}/api/v1/namespaces/" .. M.selection.ns .. "/pods/" .. M.selection.pod .. "/log" .. "?pretty=true",
  }, { contentType = "text/html" }):fetchAsync(function(self)
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
  -- local data = commands.execute_shell_command(
  --   "curl",
  --   "-X 'GET' 'http://localhost:8080/api/v1/namespaces/tools/pods/echoserver-fb487f4c-d6hdv' -H 'accept: application/yaml'"
  -- )
  --
  -- ResourceBuilder:new("", {}, {}):setData(data):splitData():displayFloat("",pod_name, "yaml")
  ResourceBuilder:new("desc", {
    "{{BASE}}/api/v1/namespaces/" .. namespace .. "/pods/" .. pod_name,
  }, { contentType = "yaml" }):fetchAsync(function(self)
    self:splitData()
    vim.schedule(function()
      self:displayFloat("k8s_pod_desc", pod_name, "yaml")
    end)
  end)
end

return M
