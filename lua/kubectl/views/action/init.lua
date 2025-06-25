local buffers = require("kubectl.actions.buffers")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local M = {}

local function get_values(definition, data)
  local bufnr = 0
  local ns = state.marks.ns_id

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
      local label = mark[4].virt_text[1][1]
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
    end
  else
    for _, mark in ipairs(extmarks) do
      local label = mark[4].virt_text[1][1]
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
    end
  end

  return results
end

function M.View(definition, data, callback)
  local win_config
  local builder = manager.get_or_create("action_view")

  builder.extmarks = {}
  builder.data = {}
  builder.header = {}
  builder.origin_data = data

  builder.buf_nr, win_config = buffers.confirmation_buffer(definition.display, definition.ft, function(confirm)
    local args = get_values(definition, builder.origin_data)
    if confirm then
      callback(args)
    end
  end)

  local add_divider = false

  if definition.hints then
    add_divider = true
    builder.addHints(definition.hints, false, false)
  end

  if definition.notes then
    add_divider = true
    table.insert(builder.header.data, definition.notes)
    table.insert(builder.header.marks, {
      row = #builder.header.data - 1,
      start_col = 0,
      end_col = #builder.header.data[#builder.header.data],
      hl_group = hl.symbols.gray,
    })
  end

  if add_divider then
    tables.generateDividerRow(builder.header.data, builder.header.marks)
  end

  for _, item in ipairs(data) do
    table.insert(builder.data, item.text)
    table.insert(builder.extmarks, {
      row = #builder.data - 1,
      start_col = 0,
      virt_text = { { item.value .. " ", "KubectlHeader" } },
      virt_text_pos = "inline",
      right_gravity = false,
    })
  end

  table.insert(builder.data, "")
  table.insert(builder.data, "")
  table.insert(builder.data, "")

  local confirmation = "[y]es [n]o"
  local padding = string.rep(" ", (win_config.width - #confirmation) / 2)
  table.insert(builder.extmarks, {
    row = #builder.data - 1,
    start_col = 0,
    virt_text = { { padding .. "[y]es ", "KubectlError" }, { "[n]o", "KubectlInfo" } },
    virt_text_pos = "inline",
  })
  M.Draw()
end

function M.Draw()
  local builder = manager.get("action_view")
  if not builder then
    return
  end

  builder.displayContentRaw()
  vim.cmd([[syntax match KubectlPending /.*/]])
end

return M
