local actions = require("kubectl.actions.actions")
local commands = require("kubectl.actions.commands")
local find = require("kubectl.utils.find")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local url = require("kubectl.utils.url")

local ResourceBuilder = {}
ResourceBuilder.__index = ResourceBuilder

function ResourceBuilder:new(resource, args, opts)
  local self = setmetatable({}, ResourceBuilder)
  opts = opts or {}
  self.resource = resource
  self.args = args
  self.hints = {}
  self.contentType = opts.contentType or "json"
  self.filter = ""
  self.data = {}
  return self
end

function ResourceBuilder:setData(data)
  self.data = data
  return self
end
function ResourceBuilder:fetch(opts)
  opts = opts or {}
  self.args = url.build(self.args)
  if not opts.cmd then
    opts.cmd = "kubectl"
  else
    opts.cmd = opts.cmd
    self.args = url.addHeaders(self.args, self.contentType)
  end

  self.data = commands.execute_shell_command(opts.cmd, self.args)
  return self
end

function ResourceBuilder:fetchAsync(callback, opts)
  opts = opts or {}
  self.args = url.build(self.args)
  if not opts.cmd or opts.cmd == "kubectl" then
    opts.cmd = "kubectl"
  else
    opts.cmd = "curl"
    self.args = url.addHeaders(self.args, self.contentType)
  end

  commands.shell_command_async(opts.cmd, self.args, function(data)
    self.data = data
    callback(self)
  end)
  return self
end

function ResourceBuilder:decodeJson()
  local success, decodedData = pcall(vim.json.decode, self.data)
  if success then
    self.data = decodedData
  end
  return self
end

function ResourceBuilder:process(processFunc)
  self.processedData = processFunc(self.data)
  return self
end

function ResourceBuilder:sort()
  local sortby = state.getSortBy()
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
          else
            return valueA < valueB
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
  self.prettyData = tables.pretty_print(self.processedData, headersFunc())
  return self
end

function ResourceBuilder:addHints(hints, include_defaults, include_context)
  self.hints = tables.generateHints(hints, include_defaults, include_context)
  return self
end

function ResourceBuilder:setFilter()
  self.filter = state.getFilter()
  return self
end

function ResourceBuilder:display(filetype, title, cancellationToken)
  if cancellationToken and cancellationToken() then
    return
  end
  actions.buffer(find.filter_line(self.prettyData, self.filter, 2), filetype, { title = title, hints = self.hints })
end

function ResourceBuilder:displayFloat(filetype, title, syntax, usePrettyData)
  local displayData = usePrettyData and self.prettyData or self.data
  actions.floating_buffer(displayData, filetype, { title = title, syntax = syntax, hints = self.hints })
  return self
end

return ResourceBuilder
