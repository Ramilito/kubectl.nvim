local buffers = require("kubectl.actions.buffers")
local completion = require("kubectl.utils.completion")
local config = require("kubectl.config")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

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

function M.View()
  local self = manager.get_or_create("filter")
  local buf, win = buffers.filter_buffer("k8s_filter", M.save_history, { title = "Filter", header = { data = {} } })
  self.buf_nr = buf
  self.win_nr = win

  local items = vim.tbl_map(function(entry)
    return { name = entry }
  end, state.filter_history)

  completion.with_completion(self.buf_nr, items, nil, false)

  local legend_spec = {
    { key = "<Plug>(kubectl.select)", desc = "apply" },
    { key = "<Plug>(kubectl.tab)", desc = "next" },
    { key = "<Plug>(kubectl.shift_tab)", desc = "previous" },
    { key = "<Plug>(kubectl.quit)", desc = "close" },
  }

  local header, marks = tables.generateHeader(legend_spec, false, false)

  local instructions = {
    "Use commas to separate multiple patterns.",
    "Prefix a pattern with ! for negative filtering.",
    "All patterns must match for a line to be included.",
  }

  local function add_gray_line(txt)
    table.insert(header, txt)
    table.insert(marks, {
      row = #header - 1,
      start_col = 0,
      end_col = #txt,
      hl_group = hl.symbols.gray,
    })
  end

  for _, line in ipairs(instructions) do
    add_gray_line(line)
  end
  tables.generateDividerRow(header, marks)

  table.insert(header, "History:")

  local headers_len = #header
  local padding = #state.filter_history < 10 and 2 or 3

  for i, value in ipairs(state.filter_history) do
    table.insert(header, headers_len + 1, string.rep(" ", padding) .. value)
    table.insert(marks, {
      row = headers_len - 1 + i,
      start_col = 0,
      virt_text = { { ("%d"):format(i), hl.symbols.white } },
      virt_text_pos = "overlay",
    })
  end
  table.insert(header, "")

  buffers.set_content(self.buf_nr, { header = { data = header }, content = {}, marks = {} })
  vim.api.nvim_buf_set_lines(buf, #header, -1, false, { "Filter: " })

  buffers.apply_marks(self.buf_nr, marks, header)
  buffers.fit_to_content(self.buf_nr, self.win_nr, 1)
  vim.api.nvim_win_set_cursor(self.win_nr, { 1, 0 })

  for i = 1, #state.filter_history, 1 do
    vim.keymap.set("n", tostring(i), function()
      local lnum = headers_len + i
      local picked = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""

      local prompt = "% " .. vim.trim(picked)

      vim.api.nvim_buf_set_lines(buf, -2, -1, false, { prompt })
      vim.api.nvim_win_set_cursor(win, { 1, #prompt })
      vim.cmd("startinsert!")

      if config.options.filter.apply_on_select_from_history then
        vim.schedule(function()
          vim.api.nvim_input("<cr>")
        end)
      end
    end, {
      buffer = buf,
      nowait = true,
      silent = true,
      noremap = true,
      desc = "kubectl: select history #" .. i,
    })
  end

  vim.keymap.set("n", "<Plug>(kubectl.select)", function()
    local current_line = vim.api.nvim_win_get_cursor(0)[1]
    if current_line >= #header then
      return
    end

    local picked = vim.api.nvim_get_current_line()
    local prompt = "% " .. picked

    vim.api.nvim_buf_set_lines(buf, -2, -1, false, { prompt })
    vim.api.nvim_win_set_cursor(win, { 1, #prompt })
    vim.cmd("startinsert!")

    if config.options.filter.apply_on_select_from_history then
      vim.schedule(function()
        vim.api.nvim_input("<CR>")
      end)
    end
  end, { buffer = self.buf_nr, noremap = true })
end

return M
