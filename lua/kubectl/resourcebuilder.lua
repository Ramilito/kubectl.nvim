local actions = require("kubectl.actions.actions")
local commands = require("kubectl.actions.commands")
local find = require("kubectl.utils.find")
local state = require("kubectl.utils.state")
local tables = require("kubectl.utils.tables")

local ResourceBuilder = {}
ResourceBuilder.__index = ResourceBuilder

function ResourceBuilder:new(resource, args, opts)
  opts = opts or {}
  local self = setmetatable({}, ResourceBuilder)
  self.resource = resource
  self.args = args
  self.hints = {}
  self.contentType = opts.contentType or "json"
  self.filter = ""
  self.data = {}
  return self
end

local function buildPath(args, contentType)
  for i, arg in ipairs(args) do
    if string.find(arg, "{{BASE}}") then
      local base = state.getProxyUrl()
      arg = string.gsub(arg, "{{BASE}}", base)
      args[i] = arg
    end

    if string.find(arg, "{{NAMESPACE}}") then
      if state.ns and state.ns ~= "All" then
        args[i] = string.gsub(arg, "{{NAMESPACE}}", string.format("namespaces/%s/", state.ns))
      else
        args[i] = string.gsub(arg, "{{NAMESPACE}}", "")
      end
    end
  end

  if contentType == "yaml" then
    table.insert(args, 1, "Content-Type: application/yaml")
    table.insert(args, 1, "-H")
    table.insert(args, 1, "Accept: application/yaml")
    table.insert(args, 1, "-H")
  elseif contentType == "text/html" then
    table.insert(args, 1, "Content-Type: text/plain")
    table.insert(args, 1, "-H")

    table.insert(args, 1, "Accept: application/yaml")
    table.insert(args, 1, "-H")
  else
    table.insert(args, 1, "Content-Type: application/json")
    table.insert(args, 1, "-H")
  end

  table.insert(args, 1, "-sS")
  table.insert(args, 1, "GET")
  table.insert(args, 1, "-X")
  return args
end

function ResourceBuilder:setData(data)
  self.data = data
  return self
end
function ResourceBuilder:fetch()
  self.args = buildPath(self.args, self.contentType)
  self.data = commands.execute_shell_command("curl", self.args)
  return self
end

function ResourceBuilder:fetchAsync(callback)
  self.args = buildPath(self.args, self.contentType)
  commands.shell_command_async("curl", self.args, function(data)
    self.data = data
    callback(self)
  end, nil)
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
  if cancellationToken ~= nil and cancellationToken() then
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
