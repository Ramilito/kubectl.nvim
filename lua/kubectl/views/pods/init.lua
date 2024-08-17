local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.pods.definition")
local root_definition = require("kubectl.views.definition")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}
M.selection = {}
M.builder = nil
M.handle = nil
M.pfs = {}
M.event_queue = {}

-- Function to process the event queue
local function process_event_queue()
  table.sort(M.event_queue, function(a, b)
    return tonumber(a.object.metadata.resourceVersion) < tonumber(b.object.metadata.resourceVersion)
  end)

  while #M.event_queue > 0 do
    local event = table.remove(M.event_queue, 1)

    if event.type == "ADDED" then
      table.insert(M.builder.data.items, event.object)
    elseif event.type == "DELETED" then
      for index, value in ipairs(M.builder.data.items) do
        if value.metadata.name == event.object.metadata.name then
          table.remove(M.builder.data.items, index)
          break
        end
      end
    elseif event.type == "MODIFIED" then
      for index, value in ipairs(M.builder.data.items) do
        if value.metadata.name == event.object.metadata.name then
          M.builder.data.items[index] = event.object
          break
        end
      end
    end

    -- Redraw UI after processing an event
    vim.schedule(function()
      M.Draw()
    end)
  end
end

function M.View(cancellationToken)
  M.pfs = {}
  root_definition.getPFData(M.pfs, true, "pods")
  M.builder = ResourceBuilder:new(definition.resource)
    :display(definition.ft, definition.display_name, cancellationToken)
    :setCmd(definition.url, "curl")
    :fetchAsync(function(builder)
      M.builder = builder
      M.builder:decodeJson()
      vim.schedule(function()
        M.informer(M.builder.data.metadata.resourceVersion)
        -- Set up a loop to periodically process the event queue
        vim.loop.new_timer():start(
          1000,
          2000,
          vim.schedule_wrap(function()
            process_event_queue()
          end)
        )
        M.Draw(cancellationToken)
      end)
    end)
end

function M.Draw(cancellationToken)
  M.builder
    :process(definition.processRow)
    :sort()
    :prettyPrint(definition.getHeaders)
    :addHints(definition.hints, true, true, true)

  root_definition.setPortForwards(M.builder.extmarks, M.builder.prettyData, M.pfs)

  M.builder:setContent(cancellationToken)
end

local function split_json_objects(input)
  local objects = {}
  local pattern = '}{"type":"'
  local start = 1

  while true do
    local split_point = input:find(pattern, start, true)

    if not split_point then
      -- If no more split points, add the rest of the string as the last JSON object
      table.insert(objects, input:sub(start))
      break
    end

    -- Add the JSON object up to the split point to the objects table
    table.insert(objects, input:sub(start, split_point))

    -- Move the start point to the next character after '}{'
    start = split_point + 1
  end

  return objects
end

function M.informer(version)
  local args = {
    "-N",
    "-X",
    "GET",
    "-sS",
    "-H",
    "Content-Type: application/json",
    state.getProxyUrl() .. "/api/v1/pods/?pretty=false&watch=true&resourceVersion=" .. version,
  }

  if M.handle then
    return
  end

  local leftovers = ""
  M.handle = commands.shell_command_async(M.builder.cmd, args, function() end, function(result)
    if leftovers ~= "" then
      result = leftovers .. result
      leftovers = ""
    end

    local rows = split_json_objects(result:gsub("\n", ""))

    -- Process each JSON object found in the result
    local success, data = pcall(vim.json.decode, rows[1])
    if success then
      table.insert(M.event_queue, data)
    else
      -- Handle decoding errors
      print(data, rows[1])
      vim.schedule(function()
        vim.notify("Informer failed to parse event, please refresh the view", vim.log.levels.ERROR)
      end)
    end

    for i = 2, #rows do
      leftovers = leftovers .. rows[i]
    end
  end)
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
