local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local informer = require("kubectl.actions.informer")
local layout = require("kubectl.actions.layout")
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

  self.buf_nr = buffers.buffer(filetype, title)
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
  end, function(data)
    if on_stderr then
      on_stderr(data)
    end
  end, opts)
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
    tables.pretty_print(self.processedData, headersFunc(self.data), state.sortby[self.resource])
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
  self.header.data, self.header.marks = tables.generateHeader(
    hints_copy,
    include_defaults,
    include_context,
    { resource = string_util.capitalize(self.display_name or self.resource), count = count, filter = filter }
  )
  return self
end

--- Sets the data in a buffer
function ResourceBuilder:setContentRaw(cancellationToken)
  if cancellationToken and cancellationToken() then
    return nil
  end

  buffers.set_content(self.buf_nr, { content = self.data, marks = self.extmarks, header = self.header })

  return self
end

--- Sets the data in a buffer
function ResourceBuilder:setContent(cancellationToken)
  if cancellationToken and cancellationToken() then
    return nil
  end

  buffers.set_content(self.buf_nr, { content = self.prettyData, marks = self.extmarks, header = self.header })

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

function ResourceBuilder:view(definition, cancellationToken, opts)
  opts = opts or {}
  opts.cmd = opts.cmd or "curl"
  self.definition = definition

  self = state.instance
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

  state.instance = self
  state.selections = {}
  return self
end

function ResourceBuilder:draw(definition, cancellationToken)
  self.display_name = definition.display_name
  self
    :process(definition.processRow)
    :sort()
    :prettyPrint(definition.getHeaders)
    :addHints(definition.hints, true, true, true)
  vim.schedule(function()
    self:setContent(cancellationToken)
  end)

  state.instance = self
  return self
end

function ResourceBuilder:action_view(definition, data, callback)
  local args = definition.cmd
  local win_config

  if not self.data then
    self.data = {}
  end

  if not self.extmarks then
    self.extmarks = {}
  end

  self.buf_nr, win_config = buffers.confirmation_buffer(definition.display, definition.ft, function(confirm)
    if confirm then
      callback(args)
    end
  end)

  vim.api.nvim_buf_attach(self.buf_nr, false, {
    on_lines = function(_, buf_nr, _, first, last_orig, last_new, byte_count)
      vim.defer_fn(function()
        if first == last_orig and last_orig == last_new and byte_count == 0 then
          return
        end
        local marks = vim.api.nvim_buf_get_extmarks(
          0,
          state.marks.ns_id,
          0,
          -1,
          { details = true, overlap = true, type = "virt_text" }
        )
        local args_tmp = {}
        for _, value in ipairs(definition.cmd) do
          table.insert(args_tmp, value)
        end

        for _, mark in ipairs(marks) do
          if mark then
            local text = mark[4].virt_text[1][1]
            if string.find(text, "Args", 1, true) then
              vim.api.nvim_buf_set_extmark(buf_nr, state.marks.ns_id, mark[2], 0, {
                id = mark[1],
                virt_text = { { "Args | kubectl " .. table.concat(args_tmp, " "), "KubectlWhite" } },
                virt_text_pos = "inline",
                right_gravity = false,
              })
            else
              for _, item in ipairs(data) do
                if string.find(text, item.text, 1, true) then
                  local line_number = mark[2]
                  local line = vim.api.nvim_buf_get_lines(0, line_number, line_number + 1, false)[1] or ""
                  local value = vim.trim(line)

                  if item.type == "flag" then
                    if value == "true" then
                      table.insert(args_tmp, item.cmd)
                    end
                  elseif item.type == "option" then
                    if value ~= "" and value ~= "false" and value ~= nil then
                      table.insert(args_tmp, item.cmd .. "=" .. value)
                    end
                  elseif item.type == "positional" then
                    if value ~= "" and value ~= nil then
                      if item.cmd then
                        table.insert(args_tmp, item.cmd .. " " .. value)
                      else
                        table.insert(args_tmp, value)
                      end
                    end
                  elseif item.type == "merge_above" then
                    if value ~= "" and value ~= nil then
                      args_tmp[#args_tmp] = args_tmp[#args_tmp] .. item.cmd .. value
                    end
                  end
                  break
                end
              end
            end
          end
        end
        args = args_tmp
      end, 200)
      vim.defer_fn(function()
        if vim.api.nvim_get_current_buf() == buf_nr then
          layout.win_size_fit_content(buf_nr, 2, #table.concat(args) + 40)
        end
      end, 1000)
    end,
  })

  for _, item in ipairs(data) do
    table.insert(self.data, item.value)
    table.insert(self.extmarks, {
      row = #self.data - 1,
      start_col = 0,
      virt_text = { { item.text .. " ", "KubectlHeader" } },
      virt_text_pos = "inline",
      right_gravity = false,
    })
  end

  table.insert(self.data, "")
  table.insert(self.data, "")

  table.insert(self.extmarks, {
    row = #self.data - 1,
    start_col = 0,
    virt_text = { { "Args | " .. " ", "KubectlWhite" } },
    virt_text_pos = "inline",
    right_gravity = false,
  })

  table.insert(self.data, "")
  table.insert(self.data, "")

  local confirmation = "[y]es [n]o"
  local padding = string.rep(" ", (win_config.width - #confirmation) / 2)
  table.insert(self.extmarks, {
    row = #self.data - 1,
    start_col = 0,
    virt_text = { { padding .. "[y]es ", "KubectlError" }, { "[n]o", "KubectlInfo" } },
    virt_text_pos = "inline",
  })

  self:setContentRaw()
  vim.cmd([[syntax match KubectlPending /.*/]])

  local current_enums = {}
  vim.api.nvim_buf_set_keymap(self.buf_nr, "n", "<Plug>(kubectl.tab)", "", {
    noremap = true,
    silent = true,
    desc = "toggle options",
    callback = function()
      local current_line = vim.api.nvim_win_get_cursor(0)[1]
      local marks_ok, marks = pcall(
        vim.api.nvim_buf_get_extmarks,
        0,
        state.marks.ns_id,
        current_line,
        current_line,
        { details = true, overlap = true, type = "virt_text" }
      )
      if not marks_ok then
        return
      end
      local key = marks[1][4].virt_text[1][1]
      for _, item in ipairs(data) do
        if string.match(key, item.text) and item.options then
          if current_enums[item.text] == nil then
            current_enums[item.text] = 2
          else
            current_enums[item.text] = current_enums[item.text] + 1
            if current_enums[item.text] > #item.options then
              current_enums[item.text] = 1
            end
          end
          self.data[current_line] = item.options[current_enums[item.text]]
          self:setContentRaw()
        end
      end
    end,
  })

  vim.schedule(function()
    local mappings = require("kubectl.mappings")
    mappings.map_if_plug_not_set("n", "<Tab>", "<Plug>(kubectl.tab)")
  end)
  return self
end

return ResourceBuilder
