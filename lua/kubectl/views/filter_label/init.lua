local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local find = require("kubectl.utils.find")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local utils = require("kubectl.views.filter_label.utils")
local views = require("kubectl.views")

local M = {
  win_config = nil,
  definition = {
    resource = "kubectl_filter_label",
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
}

function M.View()
  local buf_name = vim.api.nvim_buf_get_var(0, "buf_name")

  local instance = manager.get(buf_name)
  if not instance then
    return
  end
  local view, resource_definition = views.view_and_definition(instance.resource)
  local name, ns = view.getCurrentSelection()
  if not name then
    return
  end
  M.definition.ns = ns

  local builder = manager.get_or_create(M.definition.resource)
  commands.run_async("get_single_async", {
    kind = resource_definition.gvk.k,
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
      builder.buf_nr, M.win_config = buffers.confirmation_buffer(
        M.definition.display,
        M.definition.ft,
        -- on confirm (clicked y)
        function(confirm)
          if confirm then
            local confirmed_labels = {}
            local ns_id = state.marks.ns_id
            --
            local ok, exts =
              pcall(vim.api.nvim_buf_get_extmarks, builder.buf_nr, ns_id, 0, -1, { details = true, type = "virt_text" })
            if not (ok and exts) then
              return
            end
            --
            for _, ext in ipairs(exts) do
              local vt = ext[4].virt_text
              if vt and vt[1] and vt[1][1] == "[x] " then
                local row = ext[2]
                local buf_line = vim.api.nvim_buf_get_lines(builder.buf_nr, row, row + 1, false)[1]
                table.insert(confirmed_labels, buf_line)
              end
            end
            state.filter_label = confirmed_labels
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
      builder.header_len = #builder.header.data + 1

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
      utils.add_res_labels(builder, resource_definition)
      utils.add_confirmation(builder, M.win_config)

      -- clear augroup
      vim.api.nvim_clear_autocmds({ group = M.augroup })
      vim.api.nvim_create_autocmd("InsertLeave", {
        group = M.augroup,
        buffer = builder.buf_nr,
        -- save the label on insert leave
        callback = function(ev)
          local lbl_type, lbl_idx = utils.get_row_data(builder)
          if not (lbl_type and lbl_idx) then
            return
          end
          if lbl_type == "res_labels" then
            M.Draw()
            return
          end
          local row = vim.api.nvim_win_get_cursor(0)[1]
          local line = vim.api.nvim_buf_get_lines(ev.buf, row - 1, row, false)[1]
          local sess_filter_id = builder.fl_content[lbl_type][lbl_idx].sess_filter_id

          state.session_filter_label[sess_filter_id] = line
          utils.add_existing_labels(builder)
          M.Draw()
        end,
      })

      M.Draw()
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
