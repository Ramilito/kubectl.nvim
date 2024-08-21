local commands = require("kubectl.actions.commands")

local M = {
  event_queue = "",
  handle = nil,
  max_retries = 10,
  lock = false,
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

function M.split_json_objects(input)
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

local parse_retries = 0
function M.process_event_queue(builder)
  parse_retries = parse_retries + 1
  if M.event_queue == "" then
    return
  end

  if not builder.data then
    return
  end

  local queue = M.event_queue
  M.event_queue = ""
  local rows = M.split_json_objects(queue:gsub("\n", ""))
  local events = {}

  -- Process each JSON object found in the result
  for _, value in ipairs(rows) do
    local success, data = pcall(vim.json.decode, value)
    if success then
      table.insert(events, data)
    else
      if parse_retries < M.max_retries then
        M.process_event_queue(builder)
      else
        print(data)
      end
    end
  end

  parse_retries = 0
  table.sort(events, function(a, b)
    return tonumber(a.object.metadata.resourceVersion) < tonumber(b.object.metadata.resourceVersion)
  end)
  while #events > 0 do
    local event = table.remove(events, 1)
    if event.type == "ADDED" then
      table.insert(builder.data.items, event.object)
    elseif event.type == "DELETED" then
      for index, value in ipairs(builder.data.items) do
        if value.metadata.name == event.object.metadata.name then
          table.remove(builder.data.items, index)
        end
      end
    elseif event.type == "MODIFIED" then
      for index, value in ipairs(builder.data.items) do
        if value.metadata.name == event.object.metadata.name then
          builder.data.items[index] = event.object
        end
      end
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

  local args = { "-N", "--keepalive-time", "60" }

  for index, value in ipairs(builder.args) do
    if index == #builder.args then
      value = value .. "&watch=true&resourceVersion=" .. builder.data.metadata.resourceVersion
    end

    if value ~= "curl" then
      table.insert(args, value)
    end
  end
  M.handle = commands.shell_command_async(builder.cmd, args, on_exit, on_stdout, on_err)
  M.builder = builder

  M.timer = vim.loop.new_timer()
  M.timer:start(
    100,
    20,
    vim.schedule_wrap(function()
      if M.handle and not M.lock and M.event_queue ~= "" then
        M.process_event_queue(builder)
      end
    end)
  )
  return M.handle
end

function M.stop()
  if M.handle and not M.handle:is_closing() then
    M.handle:kill(2)
  end
  M.event_queue = ""
end

return M
