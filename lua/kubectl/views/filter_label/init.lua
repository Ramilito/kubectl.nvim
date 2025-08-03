local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local utils = require("kubectl.views.filter_label.utils")
local views = require("kubectl.views")

local M = {
  win_config = nil,
  definition = {
    resource = "filter_label",
    display = "Filter on labels",
    ft = "k8s_filter_label",
    hints = {
      { key = "<Plug>(kubectl.tab)", desc = "toggle label" },
      { key = "<Plug>(kubectl.add_label)", desc = "new label" },
      { key = "<Plug>(kubectl.delete_label)", desc = "delete label" },
    },
    notes = "Select none to clear existing filters.",
  },
  augroup = vim.api.nvim_create_augroup("KubectlFilterLabel", { clear = true }),
  resource_definition = {},
}

local function display_float(builder)
  builder.buf_nr, M.win_config = buffers.confirmation_buffer(
    M.definition.display,
    M.definition.ft,
    -- on confirm (clicked y)
    function(confirm)
      if confirm then
        local confirmed_labels = {}
        local sess_labels = {}
        for _, label in ipairs(builder.fl_content.existing_labels) do
          if label.is_label then
            table.insert(sess_labels, label.text)
            if label.is_selected then
              table.insert(confirmed_labels, label.text)
            end
          end
        end
        for _, label in ipairs(builder.fl_content.res_labels) do
          if label.is_label and label.is_selected then
            table.insert(sess_labels, label.text)
            table.insert(confirmed_labels, label.text)
          end
        end
        state.filter_label = confirmed_labels
        state.filter_label_history = sess_labels
      end
    end
  )

  ------------
  -- HEADER --
  ------------
  -- add hints
  builder.addHints(M.definition.hints, false, false)

  -- add notes with extmark
  table.insert(builder.header.data, M.definition.notes)
  table.insert(builder.header.marks, {
    row = #builder.header.data - 1,
    start_col = 0,
    end_col = #builder.header.data[#builder.header.data],
    hl_group = hl.symbols.gray,
  })

  -- add divider
  tables.generateDividerRow(builder.header.data, builder.header.marks)

  -------------
  -- CONTENT --
  -------------
  builder.fl_content = {
    existing_labels = {},
    res_labels = {},
    confirmation = {},
    lines = {},
  }

  utils.add_existing_labels(builder)
  utils.add_res_labels(builder, M.resource_definition.gvk.k)
  utils.add_confirmation(builder, M.win_config)

  -- clear augroup
  vim.api.nvim_clear_autocmds({ group = M.augroup })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = M.augroup,
    buffer = builder.buf_nr,
    -- save the label on insert leave
    callback = function(ev)
      if utils.toggle_event then
        utils.toggle_event = false
        return
      end
      local lbl_type, lbl_idx = utils.get_row_data(builder)
      if not (lbl_type and lbl_idx) then
        return
      end
      if lbl_type == "res_labels" then
        vim.schedule(function()
          M.Draw()
        end)
        return
      end
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local line = vim.api.nvim_buf_get_lines(ev.buf, row - 1, row, false)[1]
      local sess_filter_id = builder.fl_content[lbl_type][lbl_idx].sess_filter_id

      if not line or not state.filter_label_history[sess_filter_id] then
        return
      end
      state.filter_label_history[sess_filter_id] = line
      utils.save_history()
      utils.add_existing_labels(builder)
      M.Draw()
    end,
  })

  M.Draw()
end

function M.View()
  local builder = manager.get_or_create(M.definition.resource)
  local buf_name = vim.api.nvim_buf_get_var(0, "buf_name")

  local instance = manager.get(buf_name)
  if not instance then
    return
  end
  local view
  view, M.resource_definition = views.resource_and_definition(instance.resource)
  local name, ns = view.getCurrentSelection()
  if not name then
    vim.schedule(function()
      display_float(builder)
    end)
    return
  end
  M.definition.ns = ns

  commands.run_async("get_single_async", {
    gvk = M.resource_definition.gvk,
    namespace = ns,
    name = name,
    output = "Json",
  }, function(data)
    if not data then
      return
    end

    -- init builder
    builder.header = { data = {}, marks = {} }

    builder.extmarks = {}
    builder.data = data
    builder.decodeJson()

    vim.schedule(function()
      display_float(builder)
    end)
  end)
end

function M.Draw()
  local builder = manager.get(M.definition.resource)
  if not builder then
    return
  end

  builder.data = {}
  builder.extmarks = {}
  builder.fl_content.lines = {}

  for _, type in ipairs({ "existing_labels", "res_labels", "confirmation" }) do
    for _, line in ipairs(builder.fl_content[type]) do
      line.row = #builder.fl_content.lines + #builder.header.data + 1
      for _, ext in ipairs(line.extmarks or {}) do
        ext.row = #builder.fl_content.lines
        if line.is_label then
          ext.virt_text[1][1] = line.is_selected and "[x] " or "[ ] "
        end
      end
      table.insert(builder.fl_content.lines, vim.tbl_deep_extend("force", line, { type = type }))
    end
  end

  for _, line in ipairs(builder.fl_content.lines) do
    table.insert(builder.data, line.text)
    vim.list_extend(builder.extmarks, line.extmarks or {})
  end

  builder.displayContentRaw()
end

return M
