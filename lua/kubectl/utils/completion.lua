local M = {}

local function set_prompt(bufnr, suggestion)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local prompt = "% "
  vim.api.nvim_buf_set_lines(bufnr, row - 1, -1, false, { prompt .. suggestion })
  vim.api.nvim_win_set_cursor(0, { row, #prompt + #suggestion })
end

function M.with_completion(buf, data, callback, shortest)
  local original_input = ""
  local current_suggestion_index = 0

  vim.api.nvim_buf_set_keymap(buf, "i", "<Tab>", "", {
    noremap = true,
    callback = function()
      local line = vim.api.nvim_get_current_line()
      local input = line:sub(3) -- Remove the `% ` prefix to get the user input

      if current_suggestion_index == 0 then
        original_input = input
      end

      -- Filter suggestions based on input
      local filtered_suggestions = {}

      for _, suggestion in pairs(data) do
        if suggestion.name:lower():sub(1, #original_input) == original_input then
          table.insert(filtered_suggestions, suggestion.name)
        end
      end

      -- Cycle through the suggestions
      if #filtered_suggestions > 0 then
        if shortest or shortest == nil then
          table.sort(filtered_suggestions, function(a, b)
            return #a < #b
          end)
        end
        current_suggestion_index = current_suggestion_index + 1
        if current_suggestion_index >= #filtered_suggestions + 1 then
          set_prompt(buf, original_input)
          current_suggestion_index = 0 -- Reset the index if no suggestions are available
        else
          set_prompt(buf, filtered_suggestions[current_suggestion_index])
        end
      else
        set_prompt(buf, original_input)
        current_suggestion_index = 0 -- Reset the index if no suggestions are available
      end

      if callback then
        callback()
      end
      return ""
    end,
  })
end
return M
