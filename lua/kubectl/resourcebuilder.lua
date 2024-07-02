local actions = require("kubectl.actions.actions")
local commands = require("kubectl.actions.commands")
local find = require("kubectl.utils.find")
local marks = require("kubectl.utils.marks")
local notifications = require("kubectl.notification")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local url = require("kubectl.utils.url")

local ResourceBuilder = {}
ResourceBuilder.__index = ResourceBuilder

function ResourceBuilder:new(resource, args)
  local self = setmetatable({}, ResourceBuilder)
  self.resource = resource
  self.args = args
  self.header = { data = nil, marks = nil }
  return self
end

function ResourceBuilder:setCmd(args, cmd, contentType)
  self.cmd = cmd or "kubectl"
  self.args = url.build(args)

  if self.cmd ~= "kubectl" then
    self.args = url.addHeaders(self.args, contentType)
  end

  return self
end

function ResourceBuilder:setData(data)
  self.data = data
  return self
end

function ResourceBuilder:fetch()
  self.data = commands.execute_shell_command(self.cmd, self.args)
  return self
end

function ResourceBuilder:fetchAsync(callback)
  notifications.Add({
    "fetching " .. "[" .. self.resource .. "]",
    "args: " .. " " .. vim.inspect(self.args),
  })
  commands.shell_command_async(self.cmd, self.args, function(data)
    self.data = data
    callback(self)
  end)
  return self
end

function ResourceBuilder:decodeJson()
  local success, decodedData = pcall(vim.json.decode, self.data)

  if success then
    notifications.Add({
      "json decode successful " .. "[" .. self.resource .. "]",
    })
    self.data = decodedData
  end
  return self
end

function ResourceBuilder:process(processFunc)
  notifications.Add({
    "processing table " .. "[" .. self.resource .. "]",
  })
  self.processedData = processFunc(self.data)
  self.processedData = find.filter_line(self.processedData, state.getFilter(), 1)
  return self
end

function ResourceBuilder:sort()
  notifications.Add({
    "sorting " .. "[" .. self.resource .. "]",
  })
  local sortby = state.sortby.current_word
  if sortby ~= "" then
    sortby = string.lower(sortby)
    table.sort(self.processedData, function(a, b)
      if sortby then
        local valueA = a[sortby]
        local valueB = b[sortby]

        if valueA and valueB then
          if type(valueA) == "table" and type(valueB) == "table" then
            if valueA.timestamp and valueB.timestamp then
              return tostring(valueA.timestamp) > tostring(valueB.timestamp)
            else
              return tostring(valueA.value) < tostring(valueB.value)
            end
          elseif tonumber(valueA) and tonumber(valueB) then
            return valueA < valueB
          else
            return tostring(valueA) < tostring(valueB)
          end
        end
        ---@diagnostic disable-next-line: missing-return
      end
    end)
  end
  return self
end

function ResourceBuilder:splitData()
  if type(self.data) == "string" then
    self.data = vim.split(self.data, "\n")
  end
  return self
end

function ResourceBuilder:prettyPrint(headersFunc)
  notifications.Add({
    "prettify table " .. "[" .. self.resource .. "]",
  })
  self.prettyData, self.extmarks = tables.pretty_print(self.processedData, headersFunc())
  return self
end

function ResourceBuilder:addHints(hints, include_defaults, include_context)
  notifications.Add({
    "adding hints " .. "[" .. self.resource .. "]",
  })
  self.header.data, self.header.marks = tables.generateHeader(hints, include_defaults, include_context)
  return self
end

function ResourceBuilder:display(filetype, title, cancellationToken)
  if cancellationToken and cancellationToken() then
    return
  end
  notifications.Add({
    "display data " .. "[" .. self.resource .. "]",
  })
  notifications.Close()
  actions.buffer(self.prettyData, self.extmarks, filetype, { title = title, header = self.header })
  self:postRender()
  return self
end

function ResourceBuilder:displayFloat(filetype, title, syntax, usePrettyData)
  local displayData = usePrettyData and self.prettyData or self.data

  notifications.Add({
    "display data " .. "[" .. self.resource .. "]",
  })
  notifications.Close()
  actions.floating_buffer(displayData, self.extmarks, filetype, { title = title, syntax = syntax, header = self.header })

  return self
end

function ResourceBuilder:postRender()
  vim.schedule(function()
    marks.set_sortby_header()
  end)
  return self
end

return ResourceBuilder
