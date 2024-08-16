local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.pods.definition")
local tables = require("kubectl.utils.tables")

local M = {}
M.selection = {}
M.builder = nil
M.handle = nil

function M.View(cancellationToken)
  M.builder = ResourceBuilder:new(definition.resource)
    :display(definition.ft, definition.display_name, cancellationToken)
    :setCmd(definition.url, "curl")
    :fetchAsync(function(builder)
      M.builder = builder
      M.builder:decodeJson()
      vim.schedule(function()
        M.informer(M.builder.data.metadata.resourceVersion)
        M.Draw(cancellationToken)
      end)
    end)
end

local args = {}
function M.informer(version)
  for _, value in ipairs(M.builder.args) do
    if value ~= "curl" then
      table.insert(args, value)
    end
  end
  table.insert(args, "-N")

  args[#M.builder.args - 1] = M.builder.args[#M.builder.args]
    .. "&watch=true&allowWatchBookmarks=false"
    .. "&resourceVersion="
    .. version

  if M.handle then
    return
  end

  M.handle = commands.shell_command_async(M.builder.cmd, args, function() end, function(result)
    local success, data = pcall(vim.json.decode, result)
    if not success then
      return
    end

    if data.type == "DELETED" then
      for index, value in ipairs(M.builder.data.items) do
        if value.metadata.name == data.object.metadata.name then
          table.remove(M.builder.data.items, index)
        end
      end
    end

    if data.type == "MODIFIED" then
      for index, value in ipairs(M.builder.data.items) do
        if value.metadata.name == data.object.metadata.name then
          M.builder.data.items[index] = data.object
        end
      end
    end

    if data.type == "ADDED" then
      table.insert(M.builder.data.items, data.object)
    end

    vim.schedule(function()
      M.Draw()
    end)
  end)
end

function M.Draw(cancellationToken)
  M.builder
    :process(definition.processRow)
    :sort()
    :prettyPrint(definition.getHeaders)
    :addHints(definition.hints, true, true, true)
    :setContent(cancellationToken)
end

function M.Top()
  ResourceBuilder:new("top"):displayFloat("k8s_top", "Top"):setCmd({ "top", "pods", "-A" }):fetchAsync(function(self)
    vim.schedule(function()
      self:splitData():setContentRaw()
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

function M.Logs()
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
          :setContentRaw()
      end)
    end)
end

function M.Edit(name, ns)
  buffers.floating_buffer("k8s_pod_edit", name, "yaml")
  commands.execute_terminal("kubectl", { "edit", "pod/" .. name, "-n", ns })
end

function M.Desc(name, ns)
  ResourceBuilder:new("desc")
    :displayFloat("k8s_pod_desc", name, "yaml")
    :setCmd({ "describe", "pod", name, "-n", ns })
    :fetchAsync(function(self)
      self:splitData()
      vim.schedule(function()
        self:setContentRaw()
      end)
    end)
end

--- Get current seletion for view
---@return string|nil
function M.getCurrentSelection()
  return tables.getCurrentSelection(2, 1)
end

return M
