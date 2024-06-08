local actions = require("kubectl.actions.actions")
local commands = require("kubectl.actions.commands")
local find = require("kubectl.utils.find")
local tables = require("kubectl.utils.tables")

local ResourceBuilder = {}
ResourceBuilder.__index = ResourceBuilder

function ResourceBuilder:new(resource, args)
  local self = setmetatable({}, ResourceBuilder)
  self.resource = resource
  self.args = args
  self.hints = {}
  self.filter = ""
  self.data = {}
  return self
end

function ResourceBuilder:NamespaceOrAll()
  if NAMESPACE ~= "All" then
    for i, v in ipairs(self.args) do
      if v == "-A" then
        self.args[i] = "-n=" .. NAMESPACE
      end
    end
  end
end

function ResourceBuilder:fetch()
  self:NamespaceOrAll()
  self.data = commands.execute_shell_command("kubectl", self.args)
  return self
end

function ResourceBuilder:fetchAsync(callback)
  self:NamespaceOrAll()
  commands.shell_command_async("kubectl", self.args, function(data)
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

function ResourceBuilder:sort(sortby)
  if sortby ~= "" then
    sortby = string.lower(sortby)
    table.sort(self.processedData, function(a, b)
      if sortby and a[sortby] and b[sortby] then
        return tostring(a[sortby]) < tostring(b[sortby])
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

function ResourceBuilder:setFilter(filter)
  self.filter = filter
  return self
end

function ResourceBuilder:display(filetype, title, cancellationToken)
  if cancellationToken ~= nil and cancellationToken() then
    return
  end
  actions.buffer(find.filter_line(self.prettyData, self.filter), filetype, { title = title, hints = self.hints })
end

function ResourceBuilder:displayFloat(filetype, title, syntax, usePrettyData)
  local displayData = usePrettyData and self.prettyData or self.data
  actions.floating_buffer(displayData, filetype, { title = title, syntax = syntax, hints = self.hints })
  return self
end

return ResourceBuilder
