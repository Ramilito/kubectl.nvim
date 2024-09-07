local commands = require("kubectl.actions.commands")
local event_handler = require("kubectl.actions.eventhandler").handler

local M = {
  event_queue = "",
  handle = nil,
  max_retries = 10,
  lock = false,
  parse_retries = 0,
}

local function release_lock()
  M.lock = false
end

local function acquire_lock()
  while M.lock do
    vim.wait(10)
  end
  M.lock = true
end

local function split_events(input)
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

local function decode_json_objects(json_strings)
  local decoded_events = {}

  for _, json_string in ipairs(json_strings) do
    local success, decoded_event = pcall(vim.json.decode, json_string, { luanil = { object = true, array = true } })
    if success then
      table.insert(decoded_events, decoded_event)
    else
      return nil, decoded_event
    end
  end

  return decoded_events
end

local function process_event(builder, event)
  local event_name = event.object.metadata.name

  -- TODO: prettify this code
  if builder.data.kind == "Table" then
    local target = builder.data
    if event.type == "ADDED" then
      table.insert(target.rows, { object = event.object, cells = target.rows[1].cells })
    elseif event.type == "DELETED" then
      for index, row in ipairs(target.rows) do
        if row.object.metadata.name == event_name then
          table.remove(target.rows, index)
          break
        end
      end
    elseif event.type == "MODIFIED" then
      for index, row in ipairs(target.rows) do
        if row.object.metadata.name == event_name then
          target.rows[index].object = event.object
          break
        end
      end
    end
  else
    local target = builder.data.items
    if event.type == "ADDED" then
      table.insert(target, event.object)
    elseif event.type == "DELETED" then
      for index, item in ipairs(target) do
        if item.metadata.name == event_name then
          table.remove(target, index)
          break
        end
      end
    elseif event.type == "MODIFIED" then
      for index, item in ipairs(target) do
        if item.metadata.name == event_name then
          target[index] = event.object
          break
        end
      end
    end
  end

  event_handler:emit(event.type, event)
end

local function sort_events_by_resource_version(events)
  table.sort(events, function(event_a, event_b)
    return tonumber(event_a.object.metadata.resourceVersion) < tonumber(event_b.object.metadata.resourceVersion)
  end)
end

function M.process(builder)
  M.parse_retries = M.parse_retries + 1
  if M.event_queue == "" or not builder.data then
    return
  end

  local event_queue_content = M.event_queue:gsub("\n", "")
  M.event_queue = ""

  local json_objects = split_events(event_queue_content)
  local decoded_events, decode_error = decode_json_objects(json_objects)

  if not decoded_events then
    if M.parse_retries < M.max_retries then
      return M.process(builder)
    else
      print(decode_error)
      return
    end
  end

  M.parse_retries = 0

  sort_events_by_resource_version(decoded_events)

  if decoded_events then
    for _, event in ipairs(decoded_events) do
      process_event(builder, event)
    end
  end
end

local function on_err(err, data)
  vim.schedule(function()
    vim.notify(
      string.format("Error occurred while watching %s %s, refresh view to fix", err or "", data or ""),
      vim.log.levels.ERROR
    )
  end)
end

local function on_stdout(result)
  acquire_lock()
  M.event_queue = M.event_queue .. result
  release_lock()
end

local function on_exit() end

function M.start(builder)
  if not builder.data or not builder.data.metadata then
    return
  end
  if M.handle then
    M.stop()
  end

  local args = { "-N", "--keepalive-time", "60", "-X", "GET", "-sS", "-H", "Content-Type: application/json" }

  for index, value in ipairs(builder.args) do
    if index == #builder.args then
      value = value .. "&watch=true&resourceVersion=" .. builder.data.metadata.resourceVersion
      table.insert(args, value)
    end
  end

  M.handle = commands.shell_command_async(builder.cmd, args, on_exit, on_stdout, on_err)
  M.builder = builder

  return M.handle
end

function M.stop()
  if M.handle and not M.handle:is_closing() then
    M.handle:kill(2)
  end
  M.event_queue = ""
end

return M
