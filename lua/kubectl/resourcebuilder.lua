local actions = require("kubectl.actions.actions")
local commands = require("kubectl.actions.commands")
local find = require("kubectl.utils.find")
local hl = require("kubectl.actions.highlight")
local marks = require("kubectl.utils.marks")
local notifications = require("kubectl.notification")
local state = require("kubectl.state")
local string_utils = require("kubectl.utils.string")
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
  notifications.Open({
    hl.symbols.gray .. "fetching " .. "[" .. self.resource .. "]",
    hl.symbols.gray .. "args: " .. " " .. vim.inspect(self.args),
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
      hl.symbols.gray .. "json decode successful " .. "[" .. self.resource .. "]",
    })
    self.data = decodedData
  end
  return self
end

function ResourceBuilder:process(processFunc)
  notifications.Add({
    hl.symbols.gray .. "processing table " .. "[" .. self.resource .. "]",
  })
  self.processedData = processFunc(self.data)
  return self
end

function ResourceBuilder:sort()
  notifications.Add({
    hl.symbols.gray .. "sorting " .. "[" .. self.resource .. "]",
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
    hl.symbols.gray .. "prettify table " .. "[" .. self.resource .. "]",
  })
  self.prettyData, self.extmarks = tables.pretty_print(self.processedData, headersFunc())
  return self
end

function ResourceBuilder:addHints(hints, include_defaults, include_context)
  notifications.Add({
    hl.symbols.gray .. "adding hints " .. "[" .. self.resource .. "]",
  })
  self.header.data, self.header.marks = tables.generateHeader(hints, include_defaults, include_context)
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
  notifications.Add({
    hl.symbols.gray .. "display data " .. "[" .. self.resource .. "]",
  })
  notifications.Close()
  actions.buffer(find.filter_line(self.prettyData, self.filter, 2), self.extmarks, filetype, { title = title, header = self.header })
  self:postRender()
  return self
end

function ResourceBuilder:displayFloat(filetype, title, syntax, usePrettyData)
  local displayData = usePrettyData and self.prettyData or self.data

  notifications.Add({
    hl.symbols.gray .. "display data " .. "[" .. self.resource .. "]",
  })
  notifications.Close()
  actions.floating_buffer(displayData, self.extmarks, filetype, { title = title, syntax = syntax, header = self.header })

  return self
end

function ResourceBuilder:postRender()
  vim.schedule(function()
    local sortby = state.sortby
    if #sortby.mark == 0 then
      local extmark = vim.api.nvim_buf_get_extmark_by_id(0, state.marks.ns_id, state.marks.header[1], { details = true })
      local lines = vim.api.nvim_buf_get_text(0, extmark[1], extmark[2], extmark[3].end_row, extmark[3].end_col, {})
      local word = string_utils.trim(table.concat(lines, "\n"))
      sortby.current_word = word

      sortby.mark[1] = state.marks.header[1]
      sortby.mark[2] = extmark[1]
      sortby.mark[3] = extmark[2]
    end

    if #sortby.mark > 0 then
      marks.set_virtual_text_on_mark(
        0,
        state.marks.ns_id,
        { sortby.mark[1], sortby.mark[2], sortby.mark[3] },
        sortby.current_word .. " ▼"
      )
    end
  end)
  return self
end

return ResourceBuilder
