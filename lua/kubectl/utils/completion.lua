local fzy = require("kubectl.utils.fzy")
local M = {}

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
      table.insert(filtered_suggestions, tbl_for_fzy[match[1]])
    end

    -- Cycle through the suggestions
    if #filtered_suggestions > 0 then
      if shortest or shortest == nil then
        table.sort(filtered_suggestions, function(a, b)
          return #a < #b
        end)
      end
      if asc then
        current_suggestion_index = current_suggestion_index + 1
        if current_suggestion_index >= #filtered_suggestions + 1 then
          set_prompt(buf, original_input)
          current_suggestion_index = 0 -- Reset the index if no suggestions are available
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
      set_prompt(buf, original_input)
      current_suggestion_index = 0 -- Reset the index if no suggestions are available
    end

    if callback then
      callback()
    end
    return ""
  end

  vim.api.nvim_buf_set_keymap(buf, "i", "<Tab>", "", {
    noremap = true,
    callback = function()
      tab_toggle(true)
    end,
  })

  vim.api.nvim_buf_set_keymap(buf, "i", "<S-Tab>", "", {
    noremap = true,
    callback = function()
      tab_toggle(false)
    end,
  })
end
return M
