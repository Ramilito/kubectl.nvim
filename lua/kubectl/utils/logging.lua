local M = {}

function M.notify_table(tbl)
  vim.schedule(function()
    local str = vim.inspect(tbl)
    local max_len = 1000 -- Split the output if it's too long
    for i = 1, #str, max_len do
      vim.notify(str:sub(i, i + max_len - 1))
    end
  end)
end

return M
