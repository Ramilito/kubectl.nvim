local tables = require("kubectl.utils.tables")
local find = require("kubectl.utils.find")
local actions = require("kubectl.actions.actions")
local commands = require("kubectl.actions.commands")

local ResourceBuilder = {}
ResourceBuilder.__index = ResourceBuilder

function ResourceBuilder:new(resource, args)
  local self = setmetatable({}, ResourceBuilder)
  self.resource = resource
  self.args = args
  self.hints = {}
  self.filter = ""
  return self
end

function ResourceBuilder:fetch()
  self.data = commands.execute_shell_command("kubectl", self.args)
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

function ResourceBuilder:display(filetype, title)
  actions.buffer(find.filter_line(self.prettyData, self.filter), filetype, { title = title, hints = self.hints })
end

function ResourceBuilder:displayFloat(filetype, title, syntax, usePrettyData)
  local displayData = usePrettyData and self.prettyData or self.data
  actions.floating_buffer(displayData, filetype, { title = title, syntax = syntax, hints = self.hints })
  return self
end

return ResourceBuilder
