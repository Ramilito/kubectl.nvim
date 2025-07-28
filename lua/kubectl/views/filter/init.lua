local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local completion = require("kubectl.utils.completion")
local config = require("kubectl.config")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local views = require("kubectl.views")

local resource = "filter_label"
local M = {
  definition = {
    resource = resource,
  },
}

--- Saves filter history
--- @param input string: The input
function M.save_history(input)
  local history = state.filter_history
  local history_size = config.options.filter.max_history

  local result = {}
  local exists = false
  for i = 1, math.min(history_size, #history) do
    if history[i] ~= input then
      table.insert(result, history[i])
    else
      table.insert(result, 1, input)
      exists = true
    end
  end

  if not exists and input ~= "" then
    table.insert(result, 1, input)
    if #result > history_size then
      table.remove(result, #result)
    end
  end

  state.filter_history = result
end

function M.filter_label()
  local buf_name = vim.api.nvim_buf_get_var(0, "buf_name")

  local instance = manager.get(buf_name)
  if not instance then
    return
  end
  local view, definition = views.resource_and_definition(instance.resource)
  local name, ns = view.getCurrentSelection()
  if not name then
    return
  end

  local def = {
    resource = "filter_label",
    display = "Filter on labels",
    ft = "k8s_action",
    ns = ns,
    group = M.definition.group,
    version = M.definition.version,
    hints = {
      { key = "<Plug>(kubectl.select)", desc = "apply" },
      { key = "<Plug>(kubectl.tab)", desc = "next" },
      { key = "<Plug>(kubectl.shift_tab)", desc = "previous" },
      { key = "<Plug>(kubectl.clear)", desc = "close" },
      -- TODO: Definition should be moved to mappings.lua
      { key = "<Plug>(kubectl.quit)", desc = "close" },
    },
    notes = "Select none to clear existing filters.",
  }

  local builder = manager.get_or_create(def.resource)
  commands.run_async("get_single_async", {
    kind = definition.gvk.k,
    namespace = ns,
    name = name,
    output = "Json",
  }, function(data)
    if not data then
      return
    end

    builder.data = data
    builder.decodeJson()
    local labels = builder.data.metadata.labels

    local action_data = {}
    for key, value in pairs(labels) do
      table.insert(action_data, {
        text = key .. "=" .. value,
        value = "[ ]",
        type = "positional",
        options = { "[x]", "[ ]" },
      })
    end

    builder.data = {}
    vim.schedule(function()
      builder.action_view(def, action_data, function(args)
        local selection = {}
        for _, item in ipairs(args) do
          if item.value == "[x]" then
            table.insert(selection, item.text)
          end
        end
        state.filter_label = selection
      end)
    end)
  end)
end

function M.filter()
  local buf, win = buffers.filter_buffer("k8s_filter", M.save_history, { title = "Filter", header = { data = {} } })

  local list = {}
  for _, value in ipairs(state.filter_history) do
    table.insert(list, { name = value })
  end
  completion.with_completion(buf, list, nil, false)

  -- We wrap because with_completion is adding keymappings that generateHeader needs
  vim.schedule(function()
    local header, marks = tables.generateHeader({
      { key = "<Plug>(kubectl.select)", desc = "apply" },
      { key = "<Plug>(kubectl.tab)", desc = "next" },
      { key = "<Plug>(kubectl.shift_tab)", desc = "previous" },
      -- TODO: Definition should be moved to mappings.lua
      { key = "<Plug>(kubectl.quit)", desc = "close" },
    }, false, false)

    table.insert(header, "Use commas to separate multiple patterns.")
    table.insert(marks, {
      row = #header - 1,
      start_col = 0,
      end_col = #header[#header],
      hl_group = hl.symbols.gray,
    })

    table.insert(header, "Prefix a pattern with ! for negative filtering.")
    table.insert(marks, {
      row = #header - 1,
      start_col = 0,
      end_col = #header[#header],
      hl_group = hl.symbols.gray,
    })

    table.insert(header, "All patterns must match for a line to be included.")
    table.insert(marks, {
      row = #header - 1,
      start_col = 0,
      end_col = #header[#header],
      hl_group = hl.symbols.gray,
    })
    tables.generateDividerRow(header, marks)

    table.insert(header, "History:")
    local headers_len = #header
    for _, value in ipairs(state.filter_history) do
      table.insert(header, headers_len + 1, value)
    end
    table.insert(header, "")

    buffers.set_content(buf, { content = {}, marks = {}, header = { data = header } })
    vim.api.nvim_buf_set_lines(buf, #header, -1, false, { "Filter: " .. state.getFilter(), "" })

    -- TODO: Marks should be set in buffers.set_content above
    buffers.apply_marks(buf, marks, header)
    buffers.fit_to_content(buf, win, 0)

    -- TODO: Registering keymap after generateheader makes it not appear in hints
    vim.api.nvim_buf_set_keymap(buf, "n", "<Plug>(kubectl.select)", "", {
      noremap = true,
      callback = function()
        local line = vim.api.nvim_get_current_line()

        -- Don't act on prompt line
        local current_line = vim.api.nvim_win_get_cursor(0)[1]
        if current_line >= #header then
          return
        end

        local prompt = "% "

        vim.api.nvim_buf_set_lines(buf, #header + 1, -1, false, { prompt .. line })
        vim.api.nvim_win_set_cursor(0, { #header + 2, #(prompt .. line) })
        vim.cmd("startinsert!")

        if config.options.filter.apply_on_select_from_history then
          vim.schedule(function()
            vim.api.nvim_input("<cr>")
          end)
        end
      end,
    })
  end)
end

return M
