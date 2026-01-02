local buffers = require("kubectl.actions.buffers")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local M = {}

local function get_values(definition, data)
  local bufnr = vim.api.nvim_get_current_buf()
  local buf_state = state.get_buffer_state(bufnr)
  local ns = buf_state.ns_id

  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {
    details = true,
    overlap = true,
    type = "virt_text",
  })

  local results = {}

  if definition.cmd then
    for _, cmd in ipairs(definition.cmd) do
      results[#results + 1] = cmd
    end

    for _, mark in ipairs(extmarks) do
      local details = mark[4]
      if not details.virt_text then
        goto continue
      end
      local label = details.virt_text[1][1]
      local line_num = mark[2]
      local raw_line = vim.api.nvim_buf_get_lines(bufnr, line_num, line_num + 1, false)[1] or ""
      local value = vim.trim(raw_line)

      for _, item in ipairs(data) do
        if label:find(item.text, 1, true) then
          if item.type == "flag" and value == "true" then
            results[#results + 1] = item.cmd
          elseif item.type == "option" and value ~= "" and value ~= "false" then
            results[#results + 1] = item.cmd .. "=" .. value
          elseif item.type == "positional" and value ~= "" then
            if item.cmd ~= "" then
              results[#results + 1] = item.cmd .. " " .. value
            else
              results[#results + 1] = value
            end
          elseif item.type == "merge_above" and value ~= "" then
            results[#results] = results[#results] .. item.cmd .. value
          end

          break
        end
      end
      ::continue::
    end
  else
    for _, mark in ipairs(extmarks) do
      local details = mark[4]
      if not details.virt_text then
        goto continue
      end
      local label = details.virt_text[1][1]
      local raw_line = vim.api.nvim_buf_get_lines(bufnr, mark[2], mark[2] + 1, false)[1] or ""
      local value = vim.trim(raw_line)

      for _, item in ipairs(data) do
        if label:find(item.text, 1, true) then
          local entry = vim.deepcopy(item)
          entry.value = value
          table.insert(results, entry)
          break
        end
      end
      ::continue::
    end
  end

  return results
end

function M.View(definition, data, callback)
  local builder = manager.get_or_create("action_view")

  -- Build the framed view definition
  local view_def = {
    resource = "action_view",
    ft = definition.ft,
    title = definition.display,
    hints = definition.hints,
    panes = { { title = definition.display } },
  }

  builder.view_framed(view_def)
  builder.origin_data = data

  local buf = builder.buf_nr

  -- Build content
  local content = {}
  local marks = {}

  -- Add notes if present
  if definition.notes then
    table.insert(content, definition.notes)
    table.insert(marks, {
      row = #content - 1,
      start_col = 0,
      end_col = #definition.notes,
      hl_group = hl.symbols.gray,
    })
    tables.generateDividerRow(content, marks)
  end

  -- Add data items with inline virtual text labels
  for _, item in ipairs(data) do
    table.insert(content, item.value)
    table.insert(marks, {
      row = #content - 1,
      start_col = 0,
      virt_text = { { item.text .. " ", "KubectlHeader" } },
      virt_text_pos = "inline",
      right_gravity = false,
    })
  end

  -- Add confirmation line (will add centered text after fitting)
  table.insert(content, "")
  table.insert(content, "")

  -- Set content
  buffers.set_content(buf, { content = content })
  buffers.apply_marks(buf, marks, nil)

  -- Set up y/n keymaps
  vim.keymap.set("n", "y", function()
    local args = get_values(definition, builder.origin_data)
    callback(args)
    builder.frame.close()
  end, { buffer = buf, noremap = true, silent = true })

  vim.keymap.set("n", "n", function()
    builder.frame.close()
  end, { buffer = buf, noremap = true, silent = true })

  -- Fit to content
  builder.fitToContent(1)

  -- Add centered confirmation text after fitting so we know the width
  local win_width = vim.api.nvim_win_get_config(builder.win_nr).width or 100
  local confirm_text = "[y]es [n]o"
  local padding = string.rep(" ", math.floor((win_width - #confirm_text) / 2))
  buffers.apply_marks(buf, {
    {
      row = #content - 1,
      start_col = 0,
      virt_text = { { padding .. "[y]es ", "KubectlError" }, { "[n]o", "KubectlInfo" } },
      virt_text_pos = "inline",
    },
  }, nil)

  vim.cmd([[syntax match KubectlPending /.*/]])
end

return M
