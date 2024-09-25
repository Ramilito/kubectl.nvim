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
  local cursorline_enabled = true
  if selected_index == 0 then
    cursorline_enabled = false
    selected_index = 1
  end
  -- check if items are more than 30% of the screen
  local shown_items = {}
  local total_items = #items
  if total_items > 50 then
    return
  end
  --   -- Calculate the start and end indices for the subset
  --   local start_index = selected_index
  --   local end_index = math.min(selected_index + limit - 1, total_items)
  --
  --   -- If the range exceeds the total number of items, adjust the start index
  --   if end_index - start_index + 1 < limit then
  --     start_index = math.max(total_items - limit, 1)
  --   end
  --
  --   vim.notify(
  --     "total_items: "
  --       .. total_items
  --       .. " limit: "
  --       .. limit
  --       .. "\n"
  --       .. "start_index: "
  --       .. start_index
  --       .. " end_index: "
  --       .. end_index
  --   )
  --   -- Extract the subset of items
  --   for i = start_index, end_index do
  --     table.insert(shown_items, items[i])
  --   end
  -- else
  shown_items = items
  -- end
  -- if true then
  --   return
  -- end
  -- Create a new buffer if it doesn't exist
  if not verify_completion_pum("buf") then
    pum_buf = vim.api.nvim_create_buf(false, true)
  end

  -- Create a new window if it doesn't exist
  if not verify_completion_pum("win") then
    pum_win = vim.api.nvim_open_win(pum_buf, false, {
      relative = "cursor",
      width = 30,
      height = #shown_items,
      col = 0,
      row = 1,
      style = "minimal",
      border = "rounded",
      zindex = 251,
    })
  end

  -- Enable cursorline
  vim.api.nvim_set_option_value("cursorline", cursorline_enabled, { win = pum_win })

  -- Define custom highlight for cursorline
  vim.cmd("highlight PUMCursorLine guibg=#3e4451 guifg=#ffffff")

  -- Apply custom highlight to cursorline
  vim.api.nvim_set_option_value("winhl", "CursorLine:PUMCursorLine", { win = pum_win })

  -- Clear the buffer
  vim.api.nvim_buf_set_lines(pum_buf, 0, -1, false, {})

  -- Add items to the buffer
  for i, item in ipairs(shown_items) do
    vim.api.nvim_buf_set_lines(pum_buf, i - 1, i, false, { item })
  end

  -- Highlight search_term in each item
  for i, item in ipairs(shown_items) do
    local s = fzy.positions(search_term:lower(), item:lower())
    if not s then
      break
    end
    for _, e in pairs(s) do
      vim.api.nvim_buf_add_highlight(pum_buf, -1, "Orange", i - 1, e - 1, e)
    end
  end

  -- Place cursor on the selected_index
  local lnum = selected_index > #shown_items and 1 or selected_index
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
      if #input == 0 then
        original_input = ""
        current_suggestion_index = 0
        close_completion_pum()
      end
    end,
  })

  -- Set up the key handler
  vim.on_key(function(key)
    local bs = vim.keycode("<BS>")
    local esc = vim.keycode("<Esc>")
    if key == bs or key == esc then
      local line = vim.api.nvim_get_current_line()
      local input = line:sub(3) -- Remove the `% ` prefix to get the user input
      original_input = input
      current_suggestion_index = 0
      close_completion_pum()
      return
    end
  end, vim.api.nvim_create_namespace("pum_key_handler"))

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
    local desired_prompt = filtered_suggestions[current_suggestion_index] or original_input
    if #filtered_suggestions > 0 then
      if asc then
        current_suggestion_index = current_suggestion_index + 1
        if current_suggestion_index >= #filtered_suggestions + 1 then
          current_suggestion_index = 0 -- Reset the index if no suggestions are available
          desired_prompt = original_input
        end
      else
        current_suggestion_index = current_suggestion_index - 1
        if current_suggestion_index < 0 then
          current_suggestion_index = #filtered_suggestions
        end
      end
    else
      current_suggestion_index = 0 -- Reset the index if no suggestions are available
      desired_prompt = original_input
    end

    set_prompt(buf, desired_prompt)
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
