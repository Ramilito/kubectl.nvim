local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local utils = require("kubectl.views.filter_label.utils")
local views = require("kubectl.views")

local M = {
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

    local labels = builder.data.metadata.labels

    local win_config
    vim.schedule(function()
      builder.buf_nr, win_config = buffers.confirmation_buffer(M.definition.display, M.definition.ft, function(confirm)
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
      end)

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

      -- INIT CONTENT --
      ---@type table<number, FilterLabelViewLine>
      builder.fl_content = {}

      -- add existing labels
      local added_existing_labels = utils.add_existing_labels(builder)
      print("added_existing_labels: " .. tostring(added_existing_labels))

      -- add resource labels
      local res_label_line = {
        is_label = false,
        text = resource_definition.gvk.k .. " labels:",
        type = "res_label",
        extmarks = {},
      }
      if added_existing_labels then
        utils.add_and_shift(builder.fl_content, res_label_line)
      else
        utils.add_and_shift(builder.fl_content, res_label_line, #builder.header.data + 1)
      end

      -- kind = resource_definition.gvk.k,
      for key, value in pairs(labels) do
        local label_line = {
          is_label = true,
          is_selected = false,
          text = key .. "=" .. value,
          type = "res_label",
          ---@type ExtMark[]
          extmarks = {
            {
              start_col = 0,
              virt_text = { { "", hl.symbols.header } },
              virt_text_pos = "inline",
              right_gravity = false,
            },
          },
        }
        utils.add_and_shift(builder.fl_content, label_line)
      end

      -- add confirmation boxes
      for _ = 1, 2 do
        local empty_line = {
          is_label = false,
          text = "",
          type = "confirmation",
          extmarks = {},
        }
        utils.add_and_shift(builder.fl_content, empty_line)
      end

      local confirmation = "[y]es [n]o"
      local padding = string.rep(" ", (win_config.width - #confirmation) / 2)
      utils.add_and_shift(builder.fl_content, {
        is_label = false,
        text = "",
        type = "confirmation",
        extmarks = {
          {
            start_col = 0,
            virt_text = { { padding .. "[y]es ", "KubectlError" }, { "[n]o", "KubectlInfo" } },
            virt_text_pos = "inline",
          },
        },
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
  for _, line in pairs(builder.fl_content) do
    table.insert(builder.data, line.text)
    for _, ext in ipairs(line.extmarks or {}) do
      ext.row = line.row - #builder.header.data - 1
      if line.is_label then
        ext.virt_text[1][1] = line.is_selected and "[x] " or "[ ] "
      end
      table.insert(builder.extmarks, ext)
    end
  end

  -- print("fl_content: " .. vim.inspect(builder.fl_content))
  -- print("extmarks: " .. vim.inspect(builder.extmarks))
  builder.displayContentRaw()
end

return M
