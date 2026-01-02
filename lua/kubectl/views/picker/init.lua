local buffers = require("kubectl.actions.buffers")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local mappings = require("kubectl.mappings")
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

  vim.api.nvim_buf_set_keymap(builder.buf_nr, "n", "<Plug>(kubectl.delete)", "", {
    noremap = true,
    callback = function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local data_idx = row - 1 -- Account for header row
      local item = data[data_idx]
      if item and item._entry then
        state.picker_remove(item._entry.key)
        table.remove(data, data_idx)
        pcall(vim.api.nvim_buf_set_lines, 0, row - 1, row, false, {})
      end
    end,
  })

  vim.api.nvim_buf_set_keymap(builder.buf_nr, "n", "<Plug>(kubectl.select)", "", {
    noremap = true,
    callback = function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local data_idx = row - 1 -- Account for header row
      local item = data[data_idx]
      if not item or not item._entry then
        return
      end

      local entry = item._entry
      vim.cmd("fclose!")
      vim.schedule(function()
        if not vim.api.nvim_tabpage_is_valid(entry.tab_id) then
          vim.cmd("tabnew")
          entry.tab_id = vim.api.nvim_get_current_tabpage()
        end
        vim.schedule(function()
          vim.api.nvim_set_current_tabpage(entry.tab_id)
          entry.open(unpack(entry.args))
        end)
      end)
    end,
  })

  vim.schedule(function()
    mappings.map_if_plug_not_set("n", "gD", "<Plug>(kubectl.delete)")
  end)
end

return M
