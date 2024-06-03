local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local actions = require("kubectl.actions.actions")
local definition = require("kubectl.views.pods.definition")

local M = {}
local selection = {}

function M.Pods()
  ResourceBuilder:new("pods", { "get", "pods", "-A", "-o=json" })
    :fetch()
    :decodeJson()
    :process(definition.processRow)
    :sort(SORTBY)
    :prettyPrint(definition.getHeaders)
    :addHints({
      { key = "<l>", desc = "logs" },
      { key = "<d>", desc = "describe" },
      { key = "<t>", desc = "top" },
      { key = "<enter>", desc = "containers" },
    }, true, true)
    :setFilter(FILTER)
    :display("k8s_pods", "Pods")
end

function M.PodTop()
  ResourceBuilder:new("top", { "top", "pods", "-A" }):fetch():splitData():displayFloat("k8s_top", "Top", "")
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

  commands.shell_command(
    "kubectl",
    { "logs", "--follow", "--since=1s", selection.pod, "-n", selection.ns },
    handle_output
  )
end

function M.selectPod(pod_name, namespace)
  selection = { pod = pod_name, ns = namespace }
end

function M.PodLogs()
  ResourceBuilder:new("logs", { "logs", selection.pod, "-n", selection.ns })
    :fetch()
    :splitData()
    :addHints({
      { key = "<f>", desc = "Follow" },
    }, false, false)
    :displayFloat("k8s_pod_logs", selection.pod, "less")
end

function M.PodDesc(pod_name, namespace)
  ResourceBuilder:new("desc", { "describe", "pod", pod_name, "-n", namespace })
    :fetch()
    :splitData()
    :displayFloat("k8s_pod_desc", pod_name, "yaml")
end

function M.ExecContainer(container_name)
  actions.floating_buffer("", "k8s_container_exec", { title = "ssh " .. container_name })
  commands.execute_terminal(
    "kubectl",
    { "exec", "-it", selection.pod, "-n", selection.ns, "-c ", container_name, "--", "/bin/sh" }
  )
end

function M.ContainerLogs(container_name)
  ResourceBuilder:new("containerLogs", { "logs", selection.pod, "-n", selection.ns, "-c", container_name })
    :fetch()
    :splitData()
    :addHints({
      { key = "<f>", desc = "Follow" },
    }, false, false)
    :displayFloat("k8s_container_logs", "logs" .. selection.pod, "less")
end

function M.PodContainers()
  ResourceBuilder:new("containers", { "get", "pods", selection.pod, "-n", selection.ns, "-o=json" })
    :fetch()
    :decodeJson()
    :process(definition.processContainerRow)
    :prettyPrint(definition.getContainerHeaders)
    :addHints({
      { key = "<l>", desc = "logs" },
      { key = "<enter>", desc = "exec" },
    }, false, false)
    :displayFloat("k8s_containers", selection.pod, "", true)
end

return M
