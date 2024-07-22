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
            { key = "<gl>", desc = "logs" },
            { key = "<gd>", desc = "describe" },
            { key = "<gu>", desc = "usage" },
            { key = "<enter>", desc = "containers" },
            { key = "<gp>", desc = "port forward" },
            { key = "<gk>", desc = "kill pod" },
          }, true, true, true)
          :display("k8s_pods", "Pods", cancellationToken)
        M.PortForward()
      end)
    end)
end

function M.PodTop()
  ResourceBuilder:new("top")
    :displayFloat("k8s_top", "Top", "")
    :setCmd({ "top", "pods", "-A" })
    :fetchAsync(function(self)
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
          }, false, false, false)
          :displayFloat("k8s_pod_logs", M.selection.pod, "less")
      end)
    end)
end

function M.PortForward()
  local function on_exit(result)
    local port_forwards = {}

    for line in result:gmatch("[^\r\n]+") do
      if line:find("kubectl port%-forward") then
        local resource, port = line:match("pods/([^%s]+)%s+(%d+:%d+)")
        if resource and port then
          table.insert(port_forwards, { resource = resource, port = port })
        end
      end
    end

    if #port_forwards > 0 then
      vim.schedule(function()
        local hl = require("kubectl.actions.highlight")
        local bufnr = vim.api.nvim_get_current_buf()
        local ns_id = vim.api.nvim_create_namespace("pod_pf")
        vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

        for _, pf in ipairs(port_forwards) do
          for row, line in ipairs(lines) do
            local col = line:find(pf.resource, 1, true)
            if col then
              vim.api.nvim_buf_set_extmark(
                bufnr,
                ns_id,
                row - 1,
                col + #pf.resource - 1,
                { virt_text = { { " ⇄ ", hl.symbols.success } }, virt_text_pos = "overlay" }
              )
            end
          end
        end
      end)
    end
  end

  -- TODO: Support windows?
  if vim.fn.has("win32") ~= 1 then
    local args = { "-eo", "args" }
    commands.shell_command_async("ps", args, on_exit)
  end
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
