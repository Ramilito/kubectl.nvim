local commands = require("kubectl.actions.commands")
local state = require("kubectl.state")

local M = {}

M.event_queue = ""

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
  local rows = M.split_json_objects(M.event_queue:gsub("\n", ""))
  M.event_queue = ""
  local events = {}

  -- Process each JSON object found in the result
  for _, value in ipairs(rows) do
    local success, data = pcall(vim.json.decode, value)
    if success then
      table.insert(events, data)
    else
      print(data)
      if parse_retries < 3 then
        M.process_event_queue(builder)
      end
    end
  end

  parse_retries = 0
  table.sort(events, function(a, b)
    return tonumber(a.object.metadata.resourceVersion) < tonumber(b.object.metadata.resourceVersion)
  end)

  if not builder.data then
    return
  end
  while #events > 0 do
    local event = table.remove(events, 1)

    if event.type == "ADDED" then
      table.insert(builder.data.items, event.object)
    elseif event.type == "DELETED" then
      for index, value in ipairs(builder.data.items) do
        if value.metadata.name == event.object.metadata.name then
          table.remove(builder.data.items, index)
          break
        end
      end
    elseif event.type == "MODIFIED" then
      for index, value in ipairs(builder.data.items) do
        if value.metadata.name == event.object.metadata.name then
          builder.data.items[index] = event.object
          break
        end
      end
    end

    -- Redraw UI after processing an event
    -- vim.schedule(function()
    --   M.Draw()
    -- end)
  end
end

function M.start(builder)
  if not builder.data then
    return
  end
  local args = {
    "-N",
    "-X",
    "GET",
    "-sS",
    "-H",
    "Content-Type: application/json",
    state.getProxyUrl()
      .. "/api/v1/pods/?pretty=false&watch=true&resourceVersion="
      .. builder.data.metadata.resourceVersion,
  }

  local handle = commands.shell_command_async(builder.cmd, args, function() end, function(result)
    M.event_queue = M.event_queue .. result
  end)

  return handle
end

function M.stop(handle)
  if handle and not handle:is_closing() then
    handle:kill(2)
  end
  M.event_queue = ""
end

return M
