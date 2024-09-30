local commands = require("kubectl.actions.commands")
local log = require("kubectl.log")
local state = require("kubectl.state")
local event_handler = require("kubectl.actions.eventhandler").handler

local M = {
  event_queue = "",
  handle = nil,
  events_handle = nil,
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
  if not event or not event.object or not event.object.metadata then
    return
  end
  local event_name = event.object.metadata.name

  local function handle_events(action)
    -- If the event is an event and we are not in events resource,
    -- we assign the involvedObject as event name so the eventhandler can react to those changes
    if event.object.kind == "Event" and builder.resource ~= "events" then
      if event.object.involvedObject and event.object.involvedObject.name then
        event.object.metadata.name = event.object.involvedObject.name
      end
    else
      action()
    end
  end

  -- TODO: prettify this code
  if builder.data.kind == "Table" then
    local target = builder.data
    if event.type == "ADDED" then
      handle_events(function()
        table.insert(target, event.object)
        table.insert(target.rows, { object = event.object, cells = target.rows[1].cells })
      end)
    elseif event.type == "DELETED" then
      for index, row in ipairs(target.rows) do
        if row.object.metadata.name == event_name then
          table.remove(target.rows, index)
          break
        end
      end
    elseif event.type == "MODIFIED" then
      handle_events(function()
        for index, row in ipairs(target.rows) do
          if row.object.metadata.name == event_name then
            target.rows[index].object = event.object
            break
          end
        end
      end)
    end
  else
    local target = builder.data.items
    if event.type == "ADDED" then
      handle_events(function()
        table.insert(target, event.object)
      end)
    elseif event.type == "DELETED" then
      for index, item in ipairs(target) do
        if item.metadata.name == event_name then
          table.remove(target, index)
          break
        end
      end
    elseif event.type == "MODIFIED" then
      handle_events(function()
        for index, item in ipairs(target) do
          if item.metadata.name == event_name then
            target[index] = event.object
            break
          end
        end
      end)
    end
  end

  event_handler:emit(event.type, event)
end

local function sort_events_by_resource_version(events)
  table.sort(events, function(event_a, event_b)
    if event_a.object and event_b.object then
      local event_a_version = tonumber(event_a.object.metadata.resourceVersion)
      local event_b_version = tonumber(event_b.object.metadata.resourceVersion)

      if event_a_version and event_b_version then
        return event_a_version < event_b_version
      else
        log.fmt_debug(
          "Failed to sort events by resource version: %s, %s",
          event_a.object.metadata.resourceVersion,
          event_b.object.metadata.resourceVersion
        )
      end
    end
    return false
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
      log.fmt_error("Failed to decode json: %s", decode_error)
      log.fmt_debug('Failed json text: "%s"', json_objects)
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

local function on_exit()
  log.fmt_debug("Exited informer")
end

function M.start(builder)
  if not builder.data or not builder.data.metadata then
    log.fmt_error("No metadata found in builder data")
    return
  end
  if M.handle or M.events_handle then
    M.stop()
  end

  local args = { "-N", "--keepalive-time", "60", "-X", "GET", "-sS", "-H", "Content-Type: application/json" }

  local event_cmd = { state.getProxyUrl() .. "/api/v1/events?pretty=false&watch=true" }
  for _, arg in ipairs(args) do
    table.insert(event_cmd, arg)
  end

  for index, value in ipairs(builder.args) do
    if index == #builder.args then
      value = value .. "&watch=true&resourceVersion=" .. (builder.data.metadata.resourceVersion or "0")
      table.insert(args, value)
    end
  end

  log.fmt_debug("Starting informer with command: %s %s", builder.cmd, args)
  M.handle = commands.shell_command_async(builder.cmd, args, on_exit, on_stdout, on_err)
  M.events_handle = commands.shell_command_async("curl", event_cmd, on_exit, on_stdout, on_err)
  M.builder = builder

  return M.handle
end

function M.stop()
  if M.handle and not M.handle:is_closing() then
    M.handle:kill(2)
  end

  if M.events_handle and not M.events_handle:is_closing() then
    M.events_handle:kill(2)
  end
  M.event_queue = ""
end

return M
