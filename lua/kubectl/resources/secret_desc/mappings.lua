local M = {}

M.overrides = {
  ["<Plug>(kubectl.select)"] = {
    noremap = true,
    silent = true,
    desc = "Base64Decode",
    callback = function()
      local line = vim.api.nvim_get_current_line()
      local code = line:match(":%s*(.+)")

      if code then
        local dec_ok, decoded = pcall(vim.base64.decode, code)
        if not dec_ok then
          vim.notify("Failed to decode base64: " .. decoded)
          return
        end
        line = line:gsub(vim.pesc(code), vim.pesc(decoded))

        local decoded_lines = vim.split(line, "\n", { plain = true, trimempty = true })
        local current_line_number = vim.api.nvim_win_get_cursor(0)[1]
        vim.api.nvim_buf_set_lines(0, current_line_number - 1, current_line_number, false, decoded_lines)
      else
        vim.notify("No base64encoded text found")
      end
    end,
  },
}

return M
