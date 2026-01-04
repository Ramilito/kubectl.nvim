local buffers = require("kubectl.actions.buffers")
local config = require("kubectl.config")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

M.definition = {
  resource = "filter",
  ft = "k8s_filter",
  title = "Filter",
  hints = {
    { key = "<Plug>(kubectl.select)", desc = "apply" },
    { key = "<Plug>(kubectl.tab)", desc = "next" },
    { key = "<Plug>(kubectl.shift_tab)", desc = "previous" },
    { key = "<Plug>(kubectl.quit)", desc = "close" },
  },
  panes = {
    { title = "Filter", prompt = true },
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

function M.View()
  local builder = manager.get_or_create(M.definition.resource)
  builder.view_framed(M.definition)

  local buf = builder.buf_nr
  local win = builder.win_nr

  -- Set up prompt callback
  vim.fn.prompt_setcallback(buf, function(input)
    input = vim.trim(input)
    M.save_history(input)
    if not input then
      state.setFilter("")
    else
      state.setFilter(input)
    end

    vim.api.nvim_set_option_value("modified", false, { buf = buf })
    vim.cmd.fclose()
    vim.api.nvim_input("<Plug>(kubectl.refresh)")
  end)

  vim.cmd("startinsert")

  -- Build content
  local content = {}
  local marks = {}

  local instructions = {
    "Use commas to separate multiple patterns.",
    "Prefix a pattern with ! for negative filtering.",
    "All patterns must match for a line to be included.",
  }

  for _, line in ipairs(instructions) do
    table.insert(content, line)
    table.insert(marks, {
      row = #content - 1,
      start_col = 0,
      end_col = #line,
      hl_group = hl.symbols.gray,
    })
  end

  tables.generateDividerRow(content, marks)

  table.insert(content, "History:")
  local history_start = #content

  local padding = #state.filter_history < 10 and 2 or 3
  for i, value in ipairs(state.filter_history) do
    table.insert(content, string.rep(" ", padding) .. value)
    table.insert(marks, {
      row = #content - 1,
      start_col = 0,
      virt_text = { { ("%d"):format(i), hl.symbols.white } },
      virt_text_pos = "overlay",
    })
  end
  table.insert(content, "")

  -- Set content and prompt
  buffers.set_content(buf, { header = { data = {} }, content = content, marks = {} })
  vim.api.nvim_buf_set_lines(buf, #content, -1, false, { "Filter: " })
  buffers.apply_marks(buf, marks, content)
  buffers.fit_to_content(buf, win, 1)
  vim.api.nvim_win_set_cursor(win, { 1, 0 })

  -- History number keymaps
  for i = 1, #state.filter_history, 1 do
    vim.keymap.set("n", tostring(i), function()
      local lnum = history_start + i
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

  -- Select from list keymap
  vim.keymap.set("n", "<Plug>(kubectl.select)", function()
    local current_line = vim.api.nvim_win_get_cursor(0)[1]
    if current_line >= #content then
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
  end, { buffer = buf, noremap = true })
end

return M
