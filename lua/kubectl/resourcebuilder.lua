local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local notifications = require("kubectl.notification")
local state = require("kubectl.state")
local string_util = require("kubectl.utils.string")
local tables = require("kubectl.utils.tables")

---@class ResourceBuilder
---@field resource string
---@field args table
---@field cmd string
---@field data any
---@field processedData any
---@field prettyData any
---@field extmarks table
---@field header table
local ResourceBuilder = {}
ResourceBuilder.__index = ResourceBuilder

--- Create a new ResourceBuilder
---@param resource string The resource to build
---@param args table? The arguments for the resource
---@return ResourceBuilder
function ResourceBuilder:new(resource, args)
  self.resource = resource
  self.args = args or {}
  self.header = { data = nil, marks = nil }
  return setmetatable({}, ResourceBuilder)
end

--- Sets a command for the ResourceBuilder instance.
---@param args table
---@param cmd? string
---@param contentType? string
---@return ResourceBuilder
function ResourceBuilder:setCmd(args, cmd, contentType)
  local url = require("kubectl.utils.url")
  self.cmd = cmd or "kubectl"
  self.args = url.build(args)

  if self.cmd ~= "kubectl" then
    self.args = url.addHeaders(self.args, contentType)
  end

  return self
end

--- Set the data for the ResourceBuilder
---@param data any The data to set
---@return ResourceBuilder
function ResourceBuilder:setData(data)
  self.data = data
  return self
end

--- Fetch the data synchronously
---@return ResourceBuilder
function ResourceBuilder:fetch()
  self.data = commands.execute_shell_command(self.cmd, self.args)
  return self
end

--- Fetch the data asynchronously
---@param callback function The callback function to execute after fetching data
---@return ResourceBuilder
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

--- Decode JSON data
---@return ResourceBuilder
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

--- Process the data
---@param processFunc function The function to process the data
---@param no_filter boolean Whether to filter the data or not
---@return ResourceBuilder
function ResourceBuilder:process(processFunc, no_filter)
  local find = require("kubectl.utils.find")
  notifications.Add({
    "processing table " .. "[" .. self.resource .. "]",
  })
  self.processedData = processFunc(self.data)

  if no_filter then
    return self
  end

  self.processedData = find.filter_line(self.processedData, state.getFilter(), 1)

  return self
end

--- Sort the data
---@return ResourceBuilder
function ResourceBuilder:sort()
  notifications.Add({
    "sorting " .. "[" .. self.resource .. "]",
  })

  local sortby = state.sortby[self.resource]
  if sortby == nil then
    return self
  end
  local word = string.lower(sortby.current_word)

  if word ~= "" then
    table.sort(self.processedData, function(a, b)
      if sortby then
        local valueA = a[word]
        local valueB = b[word]

        if valueA and valueB then
          local comp
          if sortby.order == "asc" then
            comp = function(x, y)
              return x < y
            end
          else
            comp = function(x, y)
              return x > y
            end
          end
          if type(valueA) == "table" and type(valueB) == "table" then
            if valueA.timestamp and valueB.timestamp then
              return comp(tostring(valueA.timestamp), tostring(valueB.timestamp))
            else
              return comp(tostring(valueA.value), tostring(valueB.value))
            end
          elseif tonumber(valueA) and tonumber(valueB) then
            return comp(valueA, valueB)
          else
            return comp(tostring(valueA), tostring(valueB))
          end
        end
      end
      return true
    end)
  end

  return self
end

--- Split the data into lines
---@return ResourceBuilder
function ResourceBuilder:splitData()
  if type(self.data) == "string" then
    self.data = vim.split(self.data, "\n")
  end
  return self
end

--- Pretty print the data
---@param headersFunc function The function to generate headers
---@return ResourceBuilder
function ResourceBuilder:prettyPrint(headersFunc)
  notifications.Add({
    "prettify table " .. "[" .. self.resource .. "]",
  })
  self.prettyData, self.extmarks = tables.pretty_print(self.processedData, headersFunc())
  return self
end

--- Add hints to the data
---@param hints table The hints to add
---@param include_defaults boolean Whether to include default hints or not
---@param include_context boolean Whether to include context hints or not
---@param include_filter boolean Whether to include filter or not
---@return ResourceBuilder
function ResourceBuilder:addHints(hints, include_defaults, include_context, include_filter)
  notifications.Add({
    "adding hints " .. "[" .. self.resource .. "]",
  })
  local count = ""
  local filter = ""
  if self.prettyData then
    count = "[" .. #self.prettyData - 1 .. "]"
  elseif self.data then
    count = "[" .. #self.data - 1 .. "]"
  end
  if include_filter and state.filter ~= "" then
    filter = " </" .. state.filter .. "> "
  else
    filter = " "
  end
  self.header.data, self.header.marks = tables.generateHeader(
    hints,
    include_defaults,
    include_context,
    { resource = " " .. string_util.capitalize(self.resource), count = count, filter = filter }
  )
  return self
end

--- Display the data in a buffer
---@param filetype string The filetype to use for the buffer
---@param title string The title for the buffer
---@param cancellationToken function The function to check for cancellation
---@return ResourceBuilder|nil
function ResourceBuilder:display(filetype, title, cancellationToken)
  if cancellationToken and cancellationToken() then
    return nil
  end
  notifications.Add({
    "display data " .. "[" .. self.resource .. "]",
  })
  notifications.Close()
  buffers.buffer(self.prettyData, self.extmarks, filetype, { title = title, header = self.header })
  self:postRender()
  return self
end

--- Display the data in a floating window
---@param filetype string The filetype to use for the floating window
---@param title string The title for the floating window
---@param syntax string The syntax to use for the floating window
---@param usePrettyData? boolean Whether to use pretty data or raw data
---@return ResourceBuilder
function ResourceBuilder:displayFloat(filetype, title, syntax, usePrettyData)
  local displayData = usePrettyData and self.prettyData or self.data or {}

  notifications.Add({
    "display data " .. "[" .. self.resource .. "]",
  })
  notifications.Close()
  buffers.floating_buffer(
    displayData,
    self.extmarks,
    filetype,
    { title = title, syntax = syntax, header = self.header }
  )

  return self
end

--- Perform post-render actions
---@return ResourceBuilder
function ResourceBuilder:postRender()
  local marks = require("kubectl.utils.marks")
  vim.schedule(function()
    marks.set_sortby_header(self.resource)
  end)
  return self
end

return ResourceBuilder
