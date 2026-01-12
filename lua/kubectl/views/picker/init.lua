local buffers = require("kubectl.actions.buffers")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

M.definition = {
  resource = "Picker",
  ft = "k8s_picker",
  title = "Picker",
  hints = {
    { key = "<Plug>(kubectl.delete)", desc = "delete" },
    { key = "<Plug>(kubectl.select)", desc = "select" },
  },
  panes = {
    { title = "Picker" },
  },
}

function M.View()
  vim.cmd("fclose!")

  local builder = manager.get_or_create("Picker")
  builder.view_framed(M.definition)

  -- Get sorted entries from state
  local entries = state.picker_list()

  -- Build display data
  local data = {}
  for i, entry in ipairs(entries) do
    local parts = vim.split(entry.title, "|")
    local kind = vim.trim(parts[1])
    local resource = vim.trim(parts[2] or "")
    local namespace = vim.trim(parts[3] or "")
    local view_type = entry.filetype:gsub("k8s_", "")
    local symbol = hl.symbols.success

    if view_type == "exec" then
      symbol = hl.symbols.experimental
    elseif view_type == "desc" then
      symbol = hl.symbols.debug
    elseif view_type:match("yaml") then
      symbol = hl.symbols.header
    elseif view_type == "pod_logs" then
      symbol = hl.symbols.note
    end

    data[i] = {
      _entry = entry, -- Store reference for callbacks
      kind = { value = kind, symbol = symbol },
      type = { value = view_type, symbol = symbol },
      resource = { value = resource, symbol = symbol },
      namespace = { value = namespace, symbol = hl.symbols.gray },
    }
  end

  builder.data = data
  builder.processedData = data

  local headers = { "KIND", "TYPE", "RESOURCE", "NAMESPACE" }
  builder.prettyData, builder.extmarks = tables.pretty_print(data, headers)

  buffers.set_content(builder.buf_nr, {
    content = builder.prettyData,
    marks = builder.extmarks,
    header = { data = {}, marks = {} },
  })
  builder.fitToContent(1)
end

return M
