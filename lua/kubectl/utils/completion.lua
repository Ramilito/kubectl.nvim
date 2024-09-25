local fzy = require("kubectl.utils.fzy")
local mappings = require("kubectl.mappings")
local M = {}

local pum_buf = nil
local pum_win = nil

local function verify_completion_pum(type)
  if type == "buf" then
    return pum_buf and vim.api.nvim_buf_is_valid(pum_buf)
  elseif type == "win" then
    return pum_win and vim.api.nvim_win_is_valid(pum_win)
  end
end

local function close_completion_pum()
  if verify_completion_pum("win") then
    vim.schedule(function()
      vim.api.nvim_win_close(pum_win, true)
    end)
  end
end

local function open_completion_pum(items, selected_index, search_term)
  -- Create a new buffer if it doesn't exist
  if not verify_completion_pum("buf") then
    pum_buf = vim.api.nvim_create_buf(false, true)
  end

  -- Create a new window if it doesn't exist
  if not verify_completion_pum("win") then
    pum_win = vim.api.nvim_open_win(pum_buf, false, {
      relative = "cursor",
      width = 30,
      height = #items,
      col = 0,
      row = 1,
      style = "minimal",
      border = "rounded",
      zindex = 251,
    })
  end

  -- Enable cursorline
  local cursorline_enabled = true
  if selected_index == 0 then
    cursorline_enabled = false
    selected_index = 1
  end
  vim.api.nvim_set_option_value("cursorline", cursorline_enabled, { win = pum_win })

  -- Define custom highlight for cursorline
  vim.cmd("highlight PUMCursorLine guibg=#3e4451 guifg=#ffffff")

  -- Apply custom highlight to cursorline
  vim.api.nvim_set_option_value("winhl", "CursorLine:PUMCursorLine", { win = pum_win })

  -- Clear the buffer
  vim.api.nvim_buf_set_lines(pum_buf, 0, -1, false, {})

  -- Add items to the buffer
  for i, item in ipairs(items) do
    vim.api.nvim_buf_set_lines(pum_buf, i - 1, i, false, { item })
  end

  -- Highlight search_term in each item
  for i, item in ipairs(items) do
    local start = 1
    while true do
      local s, e = string.find(item:lower(), search_term:lower(), start, true)
      if not s then
        break
      end
      vim.api.nvim_buf_add_highlight(pum_buf, -1, "Orange", i - 1, s - 1, e)
      start = e + 1
    end
  end

  -- Place cursor on the selected_index
  local lnum = selected_index > #items and 1 or selected_index
  vim.api.nvim_win_set_cursor(pum_win, { lnum, 0 })
end

local function toggle_completion_pum(items, selected_index, search_term)
  local win_exists = verify_completion_pum("win")
  if not items or #items == 0 then
    if win_exists then
      close_completion_pum()
      return
    end
  else
    open_completion_pum(items, selected_index, search_term)
  end
end

local function set_prompt(bufnr, suggestion)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local prompt = "% "
  suggestion = suggestion or ""
  vim.api.nvim_buf_set_lines(bufnr, row - 1, -1, false, { prompt .. suggestion })
  vim.api.nvim_win_set_cursor(0, { row, #prompt + #suggestion })
end

function M.with_completion(buf, data, callback, shortest)
  local original_input = ""
  local current_suggestion_index = 0

  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      local line = vim.api.nvim_get_current_line()
      local input = line:sub(3) -- Remove the `% ` prefix to get the user input
      if input ~= original_input then
        original_input = input
        current_suggestion_index = 0
        close_completion_pum()
      end
      if #input == 0 then
        original_input = ""
        current_suggestion_index = 0
        close_completion_pum()
      end
    end,
  })

  local function tab_toggle(asc)
    local line = vim.api.nvim_get_current_line()
    local input = line:sub(3) -- Remove the `% ` prefix to get the user input

    if current_suggestion_index == 0 then
      original_input = input
    end

    local tbl_for_fzy = {}
    for _, suggestion in pairs(data) do
      table.insert(tbl_for_fzy, suggestion.name)
    end

    -- Filter suggestions based on input
    local filtered_suggestions = {}
    local matches = fzy.filter(original_input, tbl_for_fzy)
    for _, match in pairs(matches) do
      -- check if already in the list
      if not vim.tbl_contains(filtered_suggestions, tbl_for_fzy[match[1]]) then
        table.insert(filtered_suggestions, tbl_for_fzy[match[1]])
      end
    end

    -- shortest
    if shortest or shortest == nil then
      table.sort(filtered_suggestions, function(a, b)
        return #a < #b
      end)
    end

    -- Cycle through the suggestions
    if #filtered_suggestions > 0 then
      if asc then
        current_suggestion_index = current_suggestion_index + 1
        if current_suggestion_index >= #filtered_suggestions + 1 then
          current_suggestion_index = 0 -- Reset the index if no suggestions are available
          set_prompt(buf, original_input)
        else
          set_prompt(buf, filtered_suggestions[current_suggestion_index])
        end
      else
        current_suggestion_index = current_suggestion_index - 1
        if current_suggestion_index < 0 then
          current_suggestion_index = #filtered_suggestions
        end
        set_prompt(buf, filtered_suggestions[current_suggestion_index] or original_input)
      end
    else
      current_suggestion_index = 0 -- Reset the index if no suggestions are available
      set_prompt(buf, original_input)
    end

    toggle_completion_pum(filtered_suggestions, current_suggestion_index, original_input)

    if callback then
      callback()
    end
    return ""
  end

  mappings.map_if_plug_not_set("i", "<Tab>", "<Plug>(kubectl.tab)")
  mappings.map_if_plug_not_set("i", "<S-Tab>", "<Plug>(kubectl.shift_tab)")
  vim.api.nvim_buf_set_keymap(buf, "i", "<Plug>(kubectl.tab)", "", {
    noremap = true,
    callback = function()
      tab_toggle(true)
    end,
  })

  vim.api.nvim_buf_set_keymap(buf, "i", "<Plug>(kubectl.shift_tab)", "", {
    noremap = true,
    callback = function()
      tab_toggle(false)
    end,
  })
end
return M
