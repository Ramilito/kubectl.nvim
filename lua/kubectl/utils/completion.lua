local M = {}

local original_input = ""
local current_suggestion_index = 0

function M.with_completion(buf, data, callback)
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

      -- We reassign the cache since it can be slow to load
      -- self.data = M.cached_api_resources.values
      -- self:splitData():decodeJson()

      for _, suggestion in pairs(data) do
        if suggestion.name:sub(1, #original_input) == original_input then
          table.insert(filtered_suggestions, suggestion.name)
        end
      end

      -- Cycle through the suggestions
      if #filtered_suggestions > 0 then
        current_suggestion_index = current_suggestion_index + 1
        if current_suggestion_index >= #filtered_suggestions + 1 then
          callback(buf, original_input)
          current_suggestion_index = 0 -- Reset the index if no suggestions are available
        else
          callback(buf, filtered_suggestions[current_suggestion_index])
        end
      else
        callback(buf, original_input)
        current_suggestion_index = 0 -- Reset the index if no suggestions are available
      end
      return ""
    end,
  })
end
return M
