local hl = require("kubectl.actions.highlight")
local state = require("kubectl.state")

local M = {}
function M.add_and_shift(tbl, row, start_row)
  -- Check if the type already exists in the table
  local type_exists = false
  local last_idx = 0
  for i, entry in ipairs(tbl) do
    if entry.type == row.type then
      type_exists = true
      last_idx = i
    end
    if type_exists then
      -- Shift rows downward from the current position
      table.insert(
        tbl,
        last_idx + 1,
        vim.tbl_deep_extend("force", {}, entry, row, {
          row = entry.row + 1,
          ext_number = entry.ext_number + 1,
        })
      )
      print("added row: " .. vim.inspect(row) .. " after " .. vim.inspect(entry) .. " at index: " .. last_idx + 1)
      -- Update subsequent rows
      for j = i + 2, #tbl do
        tbl[j].row = tbl[j].row + 1
        tbl[j].ext_number = tbl[j].ext_number + 1
      end
      break
    end
  end

  -- Append to the end if the type doesn't exist
  if not type_exists then
    if #tbl > 0 and not start_row then
      local last_entry = tbl[#tbl]
      table.insert(
        tbl,
        vim.tbl_deep_extend("force", {}, row, {
          row = last_entry.row + 1,
          ext_number = last_entry.ext_number + 1,
        })
      )
    else
      table.insert(
        tbl,
        1,
        vim.tbl_deep_extend("force", {}, row, {
          row = start_row,
          ext_number = 0,
        })
      )
      -- Adjust subsequent rows when prepending
      for i, entry in ipairs(tbl) do
        if i > 1 then
          entry.row = entry.row + 1
          entry.ext_number = entry.ext_number + 1
        end
      end
    end
  end
end

function M.remove_type(tbl, type)
  local i = 1
  while i <= #tbl do
    if tbl[i].type == type then
      table.remove(tbl, i)
      for j = i, #tbl do
        tbl[j].row = tbl[j].row - 1
        tbl[j].ext_number = tbl[j].ext_number - 1
      end
    else
      i = i + 1
    end
  end
end

function M.add_existing_labels(builder)
  local l_type = "existing_label"
  -- remove existing labels from the builder
  M.remove_type(builder.fl_content, l_type)

  -- add header line
  ---@type FilterLabelViewLine[]
  local header_line = {
    is_label = false,
    text = "Existing labels:",
    type = l_type,
    extmarks = {},
  }
  M.add_and_shift(builder.fl_content, header_line, builder.header_len)

  local function add_existing_label(label)
    local label_line = {
      is_label = true,
      is_selected = false,
      text = label,
      type = l_type,
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
    M.add_and_shift(builder.fl_content, label_line)
  end
  -- add existing labels from state
  for _, label in ipairs(state.filter_label) do
    add_existing_label(label)
  end

  -- add existing labels from session
  local sess_fl = state.getSessionFilterLabel()
  for _, label in ipairs(sess_fl) do
    add_existing_label(label)
  end

  local blank_line = {
    is_label = false,
    text = "",
    type = l_type,
    extmarks = {},
  }
  M.add_and_shift(builder.fl_content, blank_line)
end

return M
