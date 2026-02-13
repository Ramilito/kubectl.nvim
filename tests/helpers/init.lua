-- Bootstrap mini.test for kubectl.nvim
-- Run: nvim --headless --noplugin -u tests/helpers/init.lua -c "lua MiniTest.run()"

-- Add project root to runtimepath
vim.cmd("set rtp+=.")

-- Clone mini.nvim if not present
local mini_path = "deps/mini.nvim"
if not vim.loop.fs_stat(mini_path) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/echasnovski/mini.nvim", mini_path })
end
vim.cmd("set rtp+=" .. mini_path)

require("mini.test").setup()

-- Test helpers module
local M = {}

--- Create a mock resource row (matches pipeline output shape)
---@param overrides? table Fields to override in default row
---@return table
function M.mock_row(overrides)
  local defaults = {
    "test-resource",
    "Running",
    "default",
    "1/1",
  }
  if overrides then
    return vim.tbl_extend("force", defaults, overrides)
  end
  return defaults
end

--- Assert that a table contains expected values
---@param tbl table The table to check
---@param expected table Expected values
function M.assert_contains(tbl, expected)
  for _, exp_val in ipairs(expected) do
    local found = false
    for _, val in ipairs(tbl) do
      if vim.deep_equal(val, exp_val) then
        found = true
        break
      end
    end
    if not found then
      error(string.format("Expected table to contain %s", vim.inspect(exp_val)))
    end
  end
end

--- Assert that a table does not contain values
---@param tbl table The table to check
---@param excluded table Values that should not be present
function M.assert_excludes(tbl, excluded)
  for _, exc_val in ipairs(excluded) do
    for _, val in ipairs(tbl) do
      if vim.deep_equal(val, exc_val) then
        error(string.format("Expected table to not contain %s", vim.inspect(exc_val)))
      end
    end
  end
end

return M
