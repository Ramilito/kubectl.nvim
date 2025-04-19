local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local state = require("kubectl.state")
local string_util = require("kubectl.utils.string")
local tables = require("kubectl.utils.tables")

local M = {}

function M.new(resource)
  local builder = {}

  builder.resource = resource
  builder.definition = nil
  builder.cmd = nil
  builder.args = nil
  builder.data = nil
  builder.processedData = nil
  builder.prettyData = nil
  builder.extmarks = nil
  builder.extmarks_extra = nil
  builder.header = { data = nil, marks = nil }

  function builder.setCmd(args, cmd, contentType)
    local url = require("kubectl.utils.url")
    builder.cmd = cmd or "kubectl"
    builder.args = url.build(args)
    if builder.cmd == "curl" then
      builder.args = url.addHeaders(builder.args, contentType)
    end
    return builder
  end

  function builder.fetch()
    builder.data = commands.shell_command(builder.cmd, builder.args)
    return builder
  end

  function builder.fetchAsync(on_exit, on_stdout, on_stderr, opts)
    commands.shell_command_async(builder.cmd, builder.args, function(result)
      builder.data = result
      if on_exit then
        on_exit(builder)
      end
    end, on_stdout, on_stderr, opts)
    return builder
  end

  function builder.decodeJson()
    if type(builder.data) == "string" then
      local ok, decoded = pcall(vim.json.decode, builder.data, { luanil = { object = true, array = true } })
      if ok then
        builder.data = decoded
      end
    elseif type(builder.data) == "table" then
      for i, chunk in ipairs(builder.data) do
        local ok, dec = pcall(vim.json.decode, chunk, { luanil = { object = true, array = true } })
        if ok then
          builder.data[i] = dec
        end
      end
    end
    return builder
  end

  function builder.process(processFunc, no_filter)
    local find = require("kubectl.utils.find")
    builder.processedData = processFunc(builder.data)
    if not no_filter then
      builder.processedData = find.filter_line(builder.processedData, state.getFilter(), 1)
    end
    return builder
  end

  function builder.splitData()
    if type(builder.data) == "string" then
      builder.data = vim.split(builder.data, "\n")
    end
    return builder
  end

  function builder.prettyPrint(win_nr)
    local sort_info = state.sortby[builder.resource]
    local headers = (builder.definition and builder.definition.headers) or {}
    builder.prettyData, builder.extmarks = tables.pretty_print(builder.processedData, headers, sort_info, win_nr)
    return builder
  end

  function builder.addDivider(include_filter)
    local count = ""
    local filter_str = ""

    if builder.prettyData then
      count = tostring(#builder.prettyData - 1)
    elseif builder.data then
      count = tostring(#builder.data - 1)
    end
    if include_filter and state.filter ~= "" then
      filter_str = state.filter
    end

    builder.header.divider_winbar = tables.generateDividerWinbar({
      resource = string_util.capitalize(builder.display_name or builder.resource),
      count = count,
      filter = filter_str,
    }, builder.win_nr)

    return builder
  end

  function builder.displayContentRaw(cancellationToken)
    if cancellationToken and cancellationToken() then
      return nil
    end
    if builder.header.data then
      tables.generateDividerRow(builder.header.data, builder.header.marks)
    end
    buffers.set_content(builder.buf_nr, {
      content = builder.data,
      marks = builder.extmarks,
      header = builder.header,
    })
    return builder
  end

  function builder.displayContent(win_nr, cancellationToken)
    if cancellationToken and cancellationToken() then
      return nil
    end
    local ok, win_config = pcall(vim.api.nvim_win_get_config, win_nr)
    if builder.extmarks_extra then
      vim.list_extend(builder.extmarks, builder.extmarks_extra)
    end

    if ok and win_config.relative == "" then
      -- normal window
      buffers.set_content(builder.buf_nr, {
        content = builder.prettyData,
        marks = builder.extmarks,
        header = {},
      })
      vim.defer_fn(function()
        pcall(vim.api.nvim_set_option_value, "winbar", builder.header.divider_winbar, { scope = "local", win = win_nr })
      end, 10)
    elseif ok then
      -- floating window
      if builder.header.data then
        tables.generateDividerRow(builder.header.data, builder.header.marks)
      end
      buffers.set_content(builder.buf_nr, {
        content = builder.prettyData,
        marks = builder.extmarks,
        header = builder.header,
      })
    else
      return nil
    end
    return builder
  end

  function builder.view(definition, cancellationToken)
    builder.definition = definition
    builder.buf_nr, builder.win_nr = buffers.buffer(definition.ft, definition.resource)
    state.addToHistory(definition.resource)

    commands.run_async(
      "start_reflector_async",
      { definition.gvk.k, definition.gvk.g, definition.gvk.v, nil },
      function(_, err)
        if err then
          return
        end
        vim.schedule(function()
          builder.draw(definition, cancellationToken)
        end)
      end
    )

    return builder
  end

  function builder.draw(definition, cancellationToken)
    builder.definition = definition
    local namespace = (state.ns and state.ns ~= "All") and state.ns or nil
    local filter = state.getFilter()
    local sort_by = state.sortby[definition.resource].current_word
    local sort_order = state.sortby[definition.resource].order
    commands.run_async(
      "get_table_async",
      { definition.gvk.k, namespace, sort_by, sort_order, filter },
      function(data, err)
        if err then
          return
        end
        if data then
          builder.data = data
          builder.decodeJson()
          builder.processedData = builder.data
          vim.schedule(function()
            if definition.processRow then
              builder.process(definition.processRow, true).sort()
            end
            local windows = buffers.get_windows_by_name(definition.resource)
            for _, win_nr in ipairs(windows) do
              builder.prettyPrint(win_nr).addDivider(true)
              builder.displayContent(win_nr, cancellationToken)
            end
          end)
        end
      end
    )

    return builder
  end

  --- view_float: create or reuse a floating buffer for the resource
  function builder.view_float(definition, opts)
    opts = opts or {}
    builder.definition = definition

    builder.buf_nr, builder.win_nr =
      buffers.floating_buffer(definition.ft, definition.resource, definition.syntax, builder.win_nr)

    commands.run_async(definition.cmd, opts.args, function(result)
      builder.data = result
      builder.decodeJson()
      vim.schedule(function()
        if definition.processRow then
          builder.process(definition.processRow, true).sort().prettyPrint().addDivider(false).displayContent()
        else
          builder.splitData()
          if definition.hints then
            builder.addDivider(false)
          end
          builder.displayContentRaw()
        end
      end)
    end)

    return builder
  end

  function builder.draw_float(definition, opts)
    opts = opts or {}
    builder.definition = definition

    commands.run_async(definition.cmd, opts.args, function(result)
      builder.data = result
      builder.decodeJson()
      vim.schedule(function()
        if definition.processRow then
          builder.process(definition.processRow, true).sort().prettyPrint().addDivider(false).displayContent()
        else
          builder.splitData()
          if definition.hints then
            builder.addDivider(false)
          end
          builder.displayContentRaw()
        end
      end)
    end)

    return builder
  end

  function builder.action_view(definition, data, callback)
    if not builder.data then
      builder.data = {}
    end
    if not builder.extmarks then
      builder.extmarks = {}
    end
    definition.ft = "k8s_action"
    require("kubectl.views.action").View(builder, definition, data, callback)
    return builder
  end

  return builder
end

return M
