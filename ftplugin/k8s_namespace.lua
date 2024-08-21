local api = vim.api
local namespace_view = require("kubectl.views.namespace")
local tables = require("kubectl.utils.tables")

--- Set key mappings for the buffer
local function set_keymaps(bufnr) end

--- Initialize the module
local function init()
  set_keymaps(0)
end

init()
