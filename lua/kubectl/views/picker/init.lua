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

local headers = { "MARK", "KIND", "TYPE", "RESOURCE", "NAMESPACE" }

local function build_marks_lookup()
  local lookup = {}
  for char, entry in pairs(state.marks) do
    lookup[entry.key] = char
  end
  return lookup
end

local function build_picker_data(entries)
  local marks_lookup = build_marks_lookup()
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
      _entry = entry,
      mark = { value = marks_lookup[entry.key] or "", symbol = hl.symbols.pending },
      kind = { value = kind, symbol = symbol },
      type = { value = view_type, symbol = symbol },
      resource = { value = resource, symbol = symbol },
      namespace = { value = namespace, symbol = hl.symbols.gray },
    }
  end
  return data
end

local function apply_data(builder, data)
  builder.data = data
  builder.processedData = data
  builder.prettyData, builder.extmarks = tables.pretty_print(data, headers)
  buffers.set_content(builder.buf_nr, {
    content = builder.prettyData,
    marks = builder.extmarks,
    header = { data = {}, marks = {} },
  })
  builder.fitToContent(1)
end

function M.View()
  local win_config = vim.api.nvim_win_get_config(0)
  if win_config.relative ~= "" then
    vim.cmd("fclose!")
  end

  local builder = manager.get_or_create("Picker")
  builder.view_framed(M.definition)

  local data = build_picker_data(state.picker_list())
  table.sort(data, function(a, b)
    local a_mark = a.mark.value
    local b_mark = b.mark.value
    if a_mark ~= "" and b_mark ~= "" then
      return a_mark < b_mark
    elseif a_mark ~= "" then
      return true
    elseif b_mark ~= "" then
      return false
    end
    return false
  end)
  apply_data(builder, data)
end

return M
