local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

--- Create a new factory for the given `resource`.
---@param resource string  -- e.g., "pods", "deployments"
---@return table builder   -- the new builder object
function M.new(resource)
  local builder = {}

  -- Basic fields
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
  builder.win_nr = nil
  builder.buf_nr = nil

  ---------------------------------------------------------------------------
  -- LOW-LEVEL UTILITY METHODS
  ---------------------------------------------------------------------------

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
    elseif type(builder.data) == "table" and builder.data then
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

  function builder.sort()
    local sortby = state.sortby[builder.resource]
    if sortby == nil then
      return builder
    end
    local word = string.lower(sortby.current_word)
    if word == "" then
      return builder
    end

    table.sort(builder.processedData, function(a, b)
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

    return builder
  end

  ---------------------------------------------------------------------------
  -- PRETTY PRINT & DIVIDER
  ---------------------------------------------------------------------------

  function builder.prettyPrint(win_nr)
    local sort_info = state.sortby[builder.resource]
    local original_headers = {}
    if builder.definition and builder.definition.headers then
      original_headers = builder.definition.headers
    end

    -- Use centralized function for column ordering and visibility
    local visible_headers = tables.getVisibleHeaders(builder.resource, original_headers)

    builder.prettyData, builder.extmarks =
      tables.pretty_print(builder.processedData, visible_headers, sort_info, win_nr)
    return builder
  end

  function builder.addHints(hints, include_defaults, include_context)
    local hints_copy = {}
    if hints then
      for index, value in ipairs(hints) do
        hints_copy[index] = value
      end
      builder.header.data, builder.header.marks = tables.generateHeader(hints_copy, include_defaults, include_context)
    end

    return builder
  end

  function builder.addDivider(include_filter)
    local count = ""
    if builder.prettyData then
      count = tostring(#builder.prettyData - 1)
    elseif builder.data then
      count = tostring(#builder.data - 1)
    end

    local filter_str = ""
    if include_filter and state.filter ~= "" then
      filter_str = state.filter
    end
    if include_filter and #state.filter_label > 0 then
      if filter_str ~= "" then
        filter_str = filter_str .. ", "
      end
      filter_str = filter_str .. table.concat(state.filter_label, ", ")
    end

    if include_filter and #state.filter_key > 0 then
      if filter_str ~= "" then
        filter_str = filter_str .. ", "
      end
      filter_str = filter_str .. state.filter_key
    end

    builder.header.divider_winbar = tables.generateDividerWinbar({
      resource = builder.resource,
      count = count,
      filter = filter_str,
    }, builder.win_nr)

    return builder
  end

  ---------------------------------------------------------------------------
  -- BUFFER DISPLAY
  ---------------------------------------------------------------------------

  function builder.displayContentRaw(cancellationToken)
    if cancellationToken and cancellationToken() then
      return nil
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
      -- Normal window
      buffers.set_content(builder.buf_nr, {
        content = builder.prettyData,
        marks = builder.extmarks,
        header = {},
      })
      vim.defer_fn(function()
        pcall(vim.api.nvim_set_option_value, "winbar", builder.header.divider_winbar, { scope = "local", win = win_nr })
      end, 10)
    elseif ok then
      -- Floating window
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

  ---------------------------------------------------------------------------
  -- “VIEW” AND “DRAW” METHODS
  ---------------------------------------------------------------------------

  function builder.view(definition, cancellationToken)
    builder.definition = definition or {}
    if definition.resource and definition.resource ~= builder.resource then
      builder.resource = definition.resource
    end

    builder.buf_nr, builder.win_nr = buffers.buffer(definition.ft, builder.resource)
    state.addToHistory(builder.resource)

    commands.run_async("start_reflector_async", { gvk = definition.gvk, namespace = nil }, function(_, err)
      if err then
        return
      end
      vim.schedule(function()
        builder.draw(cancellationToken)
        vim.cmd("doautocmd User K8sDataLoaded")
      end)
    end)

    return builder
  end

  --- Update winbar for all windows showing this buffer
  local function update_winbars(windows, winbar_content)
    for _, win_id in ipairs(windows) do
      local ok, win_config = pcall(vim.api.nvim_win_get_config, win_id)
      if ok and win_config.relative == "" then
        vim.defer_fn(function()
          pcall(vim.api.nvim_set_option_value, "winbar", winbar_content, { scope = "local", win = win_id })
        end, 10)
      end
    end
  end

  function builder.draw(cancellationToken)
    local definition = builder.definition or {}
    local sort_data = state.sortby[resource]

    local namespace = (state.ns and state.ns ~= "All") and state.ns or nil
    local sort_by = sort_data and sort_data.current_word or nil
    local sort_order = sort_data and sort_data.order or nil
    local filter = state.getFilter() or nil
    local filter_label = state.getFilterLabel() or nil
    local filter_key = state.getFilterKey() or nil

    -- Get window dimensions for Rust-side formatting
    local windows = buffers.get_windows_by_name(resource)
    local primary_win = windows[1]
    local window_width, text_offset
    if primary_win and vim.api.nvim_win_is_valid(primary_win) then
      window_width = vim.api.nvim_win_get_width(primary_win)
      text_offset = vim.fn.getwininfo(primary_win)[1].textoff
    end

    -- Get visible headers for formatting
    local original_headers = definition.headers or {}
    local visible_headers = tables.getVisibleHeaders(resource, original_headers)

    local args = {
      gvk = definition.gvk,
      namespace = namespace,
      sort_by = sort_by,
      sort_order = sort_order,
      filter = filter,
      filter_label = filter_label,
      filter_key = filter_key,
      -- Formatting parameters (Rust will format if all are present)
      headers = visible_headers,
      window_width = window_width,
      text_offset = text_offset,
    }

    commands.run_async("get_table_async", args, function(data, err)
      if err then
        return
      end
      if not data then
        return
      end

      builder.data = data
      builder.decodeJson()

      vim.schedule(function()
        -- Check if Rust returned formatted output
        local rust_formatted = builder.data and builder.data.lines and builder.data.extmarks
        if rust_formatted then
          -- Use Rust-formatted output directly (includes semantic highlights)
          builder.prettyData = builder.data.lines
          builder.extmarks = builder.data.extmarks
          builder.processedData = {}
        else
          -- Fallback to Lua formatting (backward compatibility)
          builder.processedData = builder.data

          if definition.processRow then
            builder.process(definition.processRow, true)
            if sort_data then
              builder.sort()
            end
          end

          local win_list = buffers.get_windows_by_name(resource)
          if #win_list == 0 then
            return
          end
          builder.prettyPrint(win_list[1])

          -- Add semantic line highlights (only for Lua path - Rust does this internally)
          local semantic = require("kubectl.lsp.semantic")
          semantic.add_line_highlights(builder.processedData, builder.extmarks, 1)
        end

        local win_list = buffers.get_windows_by_name(resource)
        if #win_list == 0 then
          return
        end

        builder.addDivider(true)

        -- Set buffer content once (all windows see the same buffer)
        builder.displayContent(win_list[1], cancellationToken)

        -- Update diagnostics immediately after content (same render frame)
        local diagnostics = require("kubectl.lsp.diagnostics")
        diagnostics.set_diagnostics(builder.buf_nr, resource)

        -- Winbar is window-local, so update it for all windows
        update_winbars(win_list, builder.header.divider_winbar)

        local loop = require("kubectl.utils.loop")
        loop.set_running(builder.buf_nr, false)
      end)
    end)

    return builder
  end

  function builder.view_float(definition, opts)
    opts = opts or {}
    builder.definition = definition or {}

    local title = definition.display_name or builder.resource
    builder.buf_nr, builder.win_nr = buffers.floating_buffer(definition.ft, title, definition.syntax, builder.win_nr)

    commands.run_async(definition.cmd, opts.args, function(result)
      builder.data = result
      builder.decodeJson()
      vim.schedule(function()
        if definition.processRow then
          builder
            .process(definition.processRow, true)
            .sort()
            .prettyPrint()
            .addDivider(false)
            .addHints(definition.hints, false, false)
            .displayContent(builder.win_nr)
        else
          builder.splitData().addHints(definition.hints, false, false).addDivider(false).displayContentRaw()
        end
      end)
    end)

    return builder
  end

  function builder.draw_float(definition, opts)
    opts = opts or {}
    builder.definition = definition or {}

    commands.run_async(definition.cmd, opts.args, function(result)
      builder.data = result
      builder.decodeJson()
      vim.schedule(function()
        if definition.processRow then
          builder.process(definition.processRow, true).sort().prettyPrint().addDivider(false)
          builder.displayContent(builder.win_nr)
        else
          builder.splitData()
          builder.addDivider(false)
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
    require("kubectl.views.action").View(definition, data, callback)
    return builder
  end

  --- Create a framed floating view with hints bar and multiple panes.
  --- Automatically renders hints and sets syntax if provided.
  --- If cmd and args are provided in opts, runs async command and displays content.
  --- @param definition table Definition with ft, hints, panes, title, width, height, syntax, cmd
  --- @param opts? { args: table, recreate_func: function, recreate_args: table } Options
  --- @return table builder
  function builder.view_framed(definition, opts)
    opts = opts or {}
    builder.definition = definition or {}

    local frame = buffers.framed_buffer({
      title = definition.title,
      filetype = definition.ft,
      panes = definition.panes,
      width = definition.width,
      height = definition.height,
      -- For picker restoration - view provides function to recreate itself
      recreate_func = opts.recreate_func,
      recreate_args = opts.recreate_args,
    })

    builder.frame = frame
    builder.buf_nr = frame.panes[1].buf
    builder.win_nr = frame.panes[1].win

    -- Auto-render hints
    builder.renderHints()

    -- Set syntax if provided
    if definition.syntax then
      vim.api.nvim_set_option_value("syntax", definition.syntax, { buf = builder.buf_nr })
    end

    -- If cmd and args provided, run async and set content
    if definition.cmd and opts.args then
      commands.run_async(definition.cmd, opts.args, function(result)
        if not result then
          return
        end
        vim.schedule(function()
          local lines = vim.split(result, "\n", { plain = true })
          buffers.set_content(builder.buf_nr, {
            content = lines,
            header = { data = {}, marks = {} },
          })
        end)
      end)
    end

    return builder
  end

  --- Fit the view to its content size.
  --- Handles both framed layouts and regular windows.
  --- @param offset? number Height offset (default 1)
  --- @return table builder
  function builder.fitToContent(offset)
    if builder.frame then
      buffers.fit_framed_to_content(builder.frame, offset or 1)
    elseif builder.buf_nr and builder.win_nr then
      buffers.fit_to_content(builder.buf_nr, builder.win_nr, offset or 1)
    end
    return builder
  end

  --- Render hints to the framed layout's hints buffer.
  --- @return table builder
  function builder.renderHints()
    if not builder.frame then
      return builder
    end

    local hints_buf = builder.frame.hints_buf
    local definition = builder.definition or {}
    local hints = definition.hints or {}

    vim.api.nvim_set_option_value("modifiable", true, { buf = hints_buf })

    local header_lines, header_marks = tables.generateHeader(hints, false, false)
    vim.api.nvim_buf_set_lines(hints_buf, 0, -1, false, header_lines)
    buffers.apply_marks(hints_buf, header_marks, {})

    vim.api.nvim_set_option_value("modifiable", false, { buf = hints_buf })

    return builder
  end

  return builder
end

return M
