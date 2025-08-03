local config = require("kubectl.config")
local hl = require("kubectl.actions.highlight")
local state = require("kubectl.state")

local M = {
  event = nil,
}

--- Saves label filter history
function M.save_history()
  local history_size = config.options.filter_label.max_history
  local history = state.filter_label_history

  if #history > history_size then
    for i = 1, #history - history_size do
      table.remove(history, i)
    end
  end
  state.set_session(state.session.contexts[state.context["current-context"]].view)
end

function M.add_existing_labels(builder)
  builder.fl_content.existing_labels = {}
  local sess_fl = state.getSessionFilterLabel()

  table.insert(builder.fl_content.existing_labels, {
    is_label = false,
    text = string.format("Existing labels (%s):", vim.tbl_count(sess_fl)),
    extmarks = {},
  })

  -- add existing labels from session
  for i, label in ipairs(sess_fl) do
    -- check if label is in state.filter_label
    table.insert(builder.fl_content.existing_labels, {
      is_label = true,
      is_selected = vim.tbl_contains(state.filter_label, label),
      text = label,
      sess_filter_id = i,
      ---@type ExtMark[]
      extmarks = {
        {
          start_col = 0,
          virt_text = { { "", hl.symbols.header } },
          virt_text_pos = "inline",
          right_gravity = false,
        },
      },
    })
  end

  -- add existing labels from state
  for _, label in ipairs(state.filter_label) do
    if not vim.tbl_contains(sess_fl, label) then
      table.insert(builder.fl_content.existing_labels, {
        is_label = true,
        is_selected = true,
        text = label,
        ---@type ExtMark[]
        extmarks = {
          {
            start_col = 0,
            virt_text = { { "", hl.symbols.header } },
            virt_text_pos = "inline",
            right_gravity = false,
          },
        },
      })
    end
  end

  table.insert(builder.fl_content.existing_labels, {
    is_label = false,
    text = "",
    extmarks = {},
  })
end

function M.add_res_labels(builder, kind)
  builder.fl_content.res_labels = {}

  local labels = builder.data and builder.data.metadata and builder.data.metadata.labels or {}
  if not labels or vim.tbl_count(labels) == 0 then
    return
  end
  table.insert(builder.fl_content.res_labels, {
    is_label = false,
    text = kind .. " labels:",
    extmarks = {},
  })
  for key, value in pairs(labels) do
    local label_line = {
      is_label = true,
      is_selected = false,
      text = key .. "=" .. value,
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
    table.insert(builder.fl_content.res_labels, label_line)
  end
  table.insert(builder.fl_content.res_labels, {
    is_label = false,
    text = "",
    extmarks = {},
  })
end

function M.add_confirmation(builder, win_config)
  table.insert(builder.fl_content.confirmation, {
    is_label = false,
    text = "",
    type = "confirmation",
    extmarks = {},
  })

  local confirmation = "[y]es [n]o"
  local padding = string.rep(" ", (win_config.width - #confirmation) / 2)
  table.insert(builder.fl_content.confirmation, {
    is_label = false,
    text = "",
    extmarks = {
      {
        start_col = 0,
        virt_text = { { padding .. "[y]es ", "KubectlError" }, { "[n]o", "KubectlInfo" } },
        virt_text_pos = "inline",
      },
    },
  })
end

function M.get_labels_positions(builder)
  local existing_labels_start_row = #builder.header.data + 1
  local res_labels_start_row = existing_labels_start_row + #builder.fl_content.existing_labels

  return {
    existing_labels = {
      start_row = existing_labels_start_row,
      end_row = res_labels_start_row - 1,
    },
    res_labels = {
      start_row = res_labels_start_row,
      end_row = res_labels_start_row + #builder.fl_content.res_labels - 1,
    },
  }
end

function M.get_row_data(builder)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local row_positions = M.get_labels_positions(builder)
  local existing_labels_start_row = row_positions.existing_labels.start_row
  local existing_labels_end_row = row_positions.existing_labels.end_row
  local res_labels_start_row = row_positions.res_labels.start_row
  local res_labels_end_row = row_positions.res_labels.end_row

  -- row should be in the range of existing labels or resource labels
  local label_type
  local label_idx
  if row < existing_labels_start_row or row > res_labels_end_row then
    return nil, nil
  elseif row >= existing_labels_start_row and row <= existing_labels_end_row then
    label_type = "existing_labels"
    label_idx = row - #builder.header.data
  elseif row >= res_labels_start_row and row <= res_labels_end_row then
    label_type = "res_labels"
    label_idx = row - #builder.fl_content.existing_labels - #builder.header.data
  end
  return label_type, label_idx
end

function M.find_label_index(builder, label)
  for i, existing_label in ipairs(builder.fl_content.existing_labels) do
    if existing_label.text == label then
      return i
    end
  end
  return nil
end

return M
