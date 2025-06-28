local hl = require("kubectl.actions.highlight")
local state = require("kubectl.state")

local M = {}

function M.add_existing_labels(builder)
  builder.fl_content.existing_labels = {}

  table.insert(builder.fl_content.existing_labels, {
    is_label = false,
    text = "Existing labels:",
    extmarks = {},
  })

  local function add_existing_label(label, sess_filter_id)
    local label_line = {
      is_label = true,
      is_selected = false,
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
    }
    if sess_filter_id then
      label_line.sess_filter_id = sess_filter_id
    end
    table.insert(builder.fl_content.existing_labels, label_line)
  end

  -- add existing labels from state
  for _, label in ipairs(state.filter_label) do
    add_existing_label(label)
  end

  -- add existing labels from session
  local sess_fl = state.getSessionFilterLabel()
  for i, label in ipairs(sess_fl) do
    add_existing_label(label, i)
  end

  table.insert(builder.fl_content.existing_labels, {
    is_label = false,
    text = "",
    extmarks = {},
  })
end

function M.add_res_labels(builder, resource_definition)
  builder.fl_content.res_labels = {}

  table.insert(builder.fl_content.res_labels, {
    is_label = false,
    text = resource_definition.gvk.k .. " labels:",
    extmarks = {},
  })

  local labels = builder.data.metadata.labels
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
end

function M.add_confirmation(builder, win_config)
  for _ = 1, 2 do
    local empty_line = {
      is_label = false,
      text = "",
      type = "confirmation",
      extmarks = {},
    }
    table.insert(builder.fl_content.confirmation, empty_line)
  end

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

function M.save_existing_labels(builder)
  local labels = {}
  for _, line in ipairs(builder.fl_content.existing_labels) do
    if line.is_label and line.is_selected then
      table.insert(labels, line.text)
    end
  end

  -- save to state
  state.setFilterLabel(labels)

  -- save to session
  state.setSessionFilterLabel(labels)
end

return M
