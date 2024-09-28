local fzy = require("kubectl.utils.fzy")
local hl = require("kubectl.actions.highlight")
local mappings = require("kubectl.mappings")
local M = {
  pum_buf = nil,
  pum_win = nil,
  ns = nil,
}

local function close_completion_pum(pum_win)
  pcall(vim.api.nvim_win_close, pum_win, true)
end

local function open_completion_pum(items, selected_index, search_term)
  if not items or #items <= 1 then
    close_completion_pum(M.pum_win)
    return
  end
  local cursorline_enabled = true
  if selected_index == 0 then
    cursorline_enabled = false
    selected_index = 1
  end

  -- Create a new buffer if it doesn't exist
  if not M.pum_buf or not vim.api.nvim_buf_is_valid(M.pum_buf) then
    M.pum_buf = vim.api.nvim_create_buf(false, true)
  end

  -- Create a new window if it doesn't exist
  if not M.pum_win or not vim.api.nvim_win_is_valid(M.pum_win) then
    local win_config = {
      relative = "cursor",
      anchor = "NW",
      width = 30,
      height = math.min(#items, 20),
      row = 1,
      col = 0,
      focusable = false,
      noautocmd = true,
      style = "minimal",
      border = "rounded",
      zindex = 251,
    }
    M.pum_win = vim.api.nvim_open_win(M.pum_buf, false, win_config)
  else
    -- Resize the window if it already exists
    vim.api.nvim_win_set_config(M.pum_win, {
      width = 30,
      height = math.min(#items, 20),
    })
  end

  -- Enable cursorline and define custom highlight for cursorline
  vim.api.nvim_set_option_value("cursorline", cursorline_enabled, { win = M.pum_win })
  vim.api.nvim_set_option_value("winhl", "CursorLine:KubectlPselect,Search:None", { win = M.pum_win })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { scope = "local" })
  -- Clear the buffer
  vim.api.nvim_buf_set_lines(M.pum_buf, 0, -1, false, {})

  -- Add items to the buffer
  for i, item in ipairs(items) do
    vim.api.nvim_buf_set_lines(M.pum_buf, i - 1, i, false, { item })
  end

  -- Highlight search_term in each item
  for i, item in ipairs(items) do
    local s = fzy.positions(search_term:lower(), item:lower())
    if s then
      for _, e in pairs(s) do
        vim.api.nvim_buf_add_highlight(M.pum_buf, -1, hl.symbols.match, i - 1, e - 1, e)
      end
    end
  end

  -- Place cursor on the selected_index
  local lnum = selected_index > #items and 1 or selected_index
  vim.api.nvim_win_set_cursor(M.pum_win, { lnum, 0 })
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
        close_completion_pum(M.pum_win)
      end
    end,
    on_detach = function()
      close_completion_pum(M.pum_win)
      if M.ns then
        vim.on_key(nil, M.ns)
        vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
        M.ns = nil
      end
    end,
  })

  -- Set up the key handler
  M.ns = vim.api.nvim_create_namespace("pum_key_handler")
  vim.on_key(function(key)
    local bs = vim.keycode("<BS>")
    local esc = vim.keycode("<Esc>")
    local cr = vim.keycode("<cr>")
    if key == bs or key == esc or key == cr then
      local line = vim.api.nvim_get_current_line()
      local input = line:sub(3) -- Remove the `% ` prefix to get the user input
      original_input = input
      current_suggestion_index = 0
      close_completion_pum(M.pum_win)
      return
    end
  end, M.ns)

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
    local desired_prompt = ""
    if #filtered_suggestions > 0 then
      if asc then
        current_suggestion_index = current_suggestion_index + 1
        if current_suggestion_index >= #filtered_suggestions + 1 then
          current_suggestion_index = 0 -- Reset the index if no suggestions are available
          desired_prompt = original_input
        else
          desired_prompt = filtered_suggestions[current_suggestion_index]
        end
      else
        current_suggestion_index = current_suggestion_index - 1
        if current_suggestion_index < 0 then
          current_suggestion_index = #filtered_suggestions
        end
        desired_prompt = filtered_suggestions[current_suggestion_index] or original_input
      end
    else
      current_suggestion_index = 0 -- Reset the index if no suggestions are available
      desired_prompt = original_input
    end

    set_prompt(buf, desired_prompt)
    open_completion_pum(filtered_suggestions, current_suggestion_index, original_input)

    if callback then
      callback()
    end
    return ""
  end

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

  vim.schedule(function()
    mappings.map_if_plug_not_set("i", "<Tab>", "<Plug>(kubectl.tab)")
    mappings.map_if_plug_not_set("i", "<S-Tab>", "<Plug>(kubectl.shift_tab)")
  end)
end

return M
