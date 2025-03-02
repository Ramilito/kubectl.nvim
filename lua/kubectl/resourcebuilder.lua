local buffers = require("kubectl.actions.buffers")
local client = require("kubectl.client")
local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local informer = require("kubectl.actions.informer")
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
---@return ResourceBuilder
function ResourceBuilder:new(resource)
  local instance = setmetatable({}, { __index = ResourceBuilder })
  instance.resource = resource
  instance.display_name = nil
  instance.processedData = nil
  instance.data = nil
  instance.buf_nr = nil
  instance.win_nr = nil
  instance.prettyData = nil
  instance.header = { data = nil, marks = nil }
  return instance
end

--- Display the data in a buffer
---@param filetype string The filetype to use for the buffer
---@param title string The title for the buffer
---@param cancellationToken function|nil The function to check for cancellation
---@return ResourceBuilder|nil
function ResourceBuilder:display(filetype, title, cancellationToken)
  if cancellationToken and cancellationToken() then
    return nil
  end

  self.buf_nr, self.win_nr = buffers.buffer(filetype, title)
  state.addToHistory(title)
  return self
end

--- Display the data in a floating window
---@param filetype string The filetype to use for the floating window
---@param title string The title for the floating window
---@param syntax string? The syntax to use for the floating window
---@return ResourceBuilder
function ResourceBuilder:displayFloat(filetype, title, syntax)
  self.buf_nr, self.win_nr = buffers.floating_buffer(filetype, title, syntax, self.win_nr)

  return self
end

--- Display the data in a floating fit to size window
---@param filetype string The filetype to use for the floating window
---@param title string The title for the floating window
---@param syntax? string The syntax to use for the floating window
---@return ResourceBuilder
function ResourceBuilder:displayFloatFit(filetype, title, syntax)
  self.buf_nr = buffers.floating_dynamic_buffer(filetype, title, nil, { syntax })

  return self
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

  if self.cmd == "curl" then
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
  self.data = commands.shell_command(self.cmd, self.args)
  return self
end

--- Fetch all data asynchronously
---@return ResourceBuilder
function ResourceBuilder:fetchAllAsync(cmds, callback)
  self.handles = commands.await_shell_command_async(cmds, function(data)
    self.data = data
    callback(self)
  end)

  return self
end

--- Fetch the data asynchronously
---@param on_exit function The callback function to execute after fetching data
---@param on_stdout function|nil The callback function to execute on stdout
---@param on_stderr function|nil The callback function to execute on stdout
---@param opts? table|nil The callback function to execute on stdout
---@return ResourceBuilder
function ResourceBuilder:fetchAsync(on_exit, on_stdout, on_stderr, opts)
  commands.shell_command_async(self.cmd, self.args, function(data)
    self.data = data
    on_exit(self)
  end, function(data)
    if on_stdout then
      on_stdout(data)
    end
  end, on_stderr and function(data)
    on_stderr(data)
  end or nil, opts)
  return self
end

--- Decode JSON data
---@return ResourceBuilder
function ResourceBuilder:decodeJson()
  if type(self.data) == "string" then
    local success, decodedData = pcall(vim.json.decode, self.data, { luanil = { object = true, array = true } })
    if success then
      self.data = decodedData
    end
  elseif type(self.data == "table") then
    for index, data in ipairs(self.data) do
      local success, decodedData = pcall(vim.json.decode, data, { luanil = { object = true, array = true } })

      if success then
        self.data[index] = decodedData
      end
    end
  end
  return self
end

--- Process the data
---@param processFunc function The function to process the data
---@param no_filter boolean|nil Whether to filter the data or not
---@return ResourceBuilder
function ResourceBuilder:process(processFunc, no_filter)
  local find = require("kubectl.utils.find")
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
  local sortby = state.sortby[self.resource]
  if sortby == nil then
    return self
  end
  local word = string.lower(sortby.current_word)
  if word == "" then
    return self
  end

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
          if valueA.sort_by and valueB.sort_by then
            return comp(valueA.sort_by, valueB.sort_by)
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
    return false
  end)

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
  self.prettyData, self.extmarks =
    tables.pretty_print(self.processedData, headersFunc(self.data), state.sortby[self.resource], self.win_nr)
  return self
end

--- Add hints to the data
---@param hints table The hints to add
---@param include_defaults boolean Whether to include default hints or not
---@param include_context boolean Whether to include context hints or not
---@param include_filter boolean Whether to include filter or not
---@return ResourceBuilder
function ResourceBuilder:addHints(hints, include_defaults, include_context, include_filter)
  local count = ""
  local filter = ""
  local hints_copy = {}
  if hints then
    for index, value in ipairs(hints) do
      hints_copy[index] = value
    end
  end
  if self.prettyData then
    count = tostring(#self.prettyData - 1)
  elseif self.data then
    count = tostring(#self.data - 1)
  end
  if include_filter and state.filter ~= "" then
    filter = state.filter
  end

  self.header.data, self.header.marks = tables.generateHeader(hints_copy, include_defaults, include_context)
  self.header.divider_winbar = tables.generateDividerWinbar({
    resource = string_util.capitalize(self.display_name or self.resource),
    count = count,
    filter = filter,
  }, self.win_nr)

  return self
end

--- Sets the data in a buffer
function ResourceBuilder:setContentRaw(cancellationToken)
  if cancellationToken and cancellationToken() then
    return nil
  end

  if self.header.data then
    tables.generateDividerRow(self.header.data, self.header.marks)
  end
  buffers.set_content(self.buf_nr, { content = self.data, marks = self.extmarks, header = self.header })

  return self
end

--- Sets the data in a buffer
function ResourceBuilder:setContent(cancellationToken)
  if cancellationToken and cancellationToken() then
    return nil
  end

  local ok, win_config = pcall(vim.api.nvim_win_get_config, self.win_nr or 0)

  if ok and win_config.relative == "" then
    buffers.set_content(self.buf_nr, { content = self.prettyData, marks = self.extmarks, header = {} })

    vim.defer_fn(function()
      pcall(vim.api.nvim_set_option_value, "winbar", self.header.divider_winbar, { scope = "local", win = self.win_nr })
    end, 10)
  elseif ok then
    if self.header.data then
      tables.generateDividerRow(self.header.data, self.header.marks)
    end
    buffers.set_content(self.buf_nr, { content = self.prettyData, marks = self.extmarks, header = self.header })
  else
    return nil
  end

  return self
end

-- We ignore the override of self in luacheck
--luacheck: ignore
function ResourceBuilder:view_float(definition, opts)
  opts = opts or {}
  opts.cmd = opts.cmd or "curl"
  self = state.instance_float

  -- Explicitly check for false
  if opts.reload == nil or opts.reload or self == nil then
    self = ResourceBuilder:new(definition.resource)
    self.definition = definition
    self:displayFloat(self.definition.ft, self.definition.resource, self.definition.syntax)
  else
    self.definition = definition
  end

  self:setCmd(self.definition.url, opts.cmd, opts.contentType):fetchAsync(function(builder)
    builder:decodeJson()

    vim.schedule(function()
      if self.definition.processRow then
        builder
          :process(self.definition.processRow, true)
          :sort()
          :prettyPrint(self.definition.getHeaders)
          :addHints(self.definition.hints, false, false, false)
          :setContent()
      else
        builder:splitData()
        if self.definition.hints then
          builder:addHints(self.definition.hints, false, false, false)
        end
        builder:setContentRaw()
      end
    end)
  end)

  state.instance_float = self
  return self
end

function ResourceBuilder:view_new(definition, cancellationToken)
  self.definition = definition
  self = state.instance[definition.resource]

  if not self or not self.resource or self.resource ~= definition.resource then
    self = ResourceBuilder:new(definition.resource)
  end

  local ns = nil
  if state.ns and state.ns ~= "All" then
    ns = state.ns
  end

  commands.run_async(
    "get_resource",
    { definition.resource_name, definition.group, definition.version, nil, ns },
    function(data)
      self.data = data
      self:decodeJson()
      if definition.informer and definition.informer.enabled then
        client.start_watcher(definition.resource_name, definition.group, definition.version, nil)
      end
      vim.schedule(function()
        self:display(definition.ft, definition.resource, cancellationToken)
        self:draw(definition, cancellationToken)
      end)

      state.instance[definition.resource] = self
      state.selections = {}
    end
  )

  return self
end
function ResourceBuilder:view(definition, cancellationToken, opts)
  opts = opts or {}
  opts.cmd = opts.cmd or "curl"
  self.definition = definition

  self = state.instance[definition.resource]
  if not self or not self.resource or self.resource ~= definition.resource then
    self = ResourceBuilder:new(definition.resource)
  end

  self
    :display(definition.ft, definition.resource, cancellationToken)
    :setCmd(definition.url, opts.cmd)
    :fetchAsync(function(builder)
      builder:decodeJson()
      if opts.cmd == "curl" then
        if not vim.tbl_contains(vim.tbl_keys(opts), "informer") or opts.informer then
          informer.start(builder)
        end
      end
      vim.schedule(function()
        builder:draw(definition, cancellationToken)
      end)
    end)

  state.instance[definition.resource] = self
  state.selections = {}
  return self
end

function ResourceBuilder:draw(definition, cancellationToken)
  self.display_name = definition.display_name
  vim.schedule(function()
    self:prettyPrint(definition.getHeaders):addHints(definition.hints, true, true, true)
    self:setContent(cancellationToken)
    self:draw_header(cancellationToken)
  end)

  state.instance[definition.resource] = self
  return self
end

function ResourceBuilder:draw_header(cancellationToken)
  if not config.options.headers then
    return
  end

  if cancellationToken and cancellationToken() then
    return
  end

  self.buf_header_nr, self.win_header_nr = buffers.header_buffer(self.win_header_nr)
  local ok, win_config = pcall(vim.api.nvim_win_get_config, self.win_header_nr)

  local current_buf = vim.api.nvim_get_current_buf()
  if ok and (win_config.relative ~= "" or current_buf ~= self.buf_nr) then
    return
  end
  if self.win_header_nr and vim.api.nvim_win_is_valid(self.win_header_nr) then
    buffers.set_content(self.buf_header_nr, { content = self.header.data, marks = self.header.marks })
    vim.api.nvim_set_option_value("winbar", "", { scope = "local", win = self.win_header_nr })
    vim.api.nvim_set_option_value("statusline", " ", { scope = "local", win = self.win_header_nr })

    local rows = vim.api.nvim_buf_line_count(self.buf_header_nr)
    win_config.height = rows
    pcall(vim.api.nvim_win_set_config, self.win_header_nr, win_config)
  end
end

function ResourceBuilder:action_view(definition, data, callback)
  if not self.data then
    self.data = {}
  end

  if not self.extmarks then
    self.extmarks = {}
  end

  definition.ft = "k8s_action"
  require("kubectl.views.action").View(self, definition, data, callback)

  return self
end

return ResourceBuilder
