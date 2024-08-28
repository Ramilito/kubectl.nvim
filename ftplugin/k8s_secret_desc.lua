local api = vim.api

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(select)", "", {
    noremap = true,
    silent = true,
    desc = "Base64Decode",
    callback = function()
      local line = vim.api.nvim_get_current_line()

      local code = line:match(":%s*(.+)")
      if code then
        local decoded = vim.base64.decode(code)
        line = line:gsub(code, decoded)

        local decoded_lines = vim.split(line, "\n", true)
        local current_line_number = vim.api.nvim_win_get_cursor(0)[1]
        vim.api.nvim_buf_set_lines(0, current_line_number - 1, current_line_number, false, decoded_lines)
      else
        vim.notify("No base64encoded text found")
      end
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
end

init()
