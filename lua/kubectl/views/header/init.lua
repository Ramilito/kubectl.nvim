local buffers = require("kubectl.actions.buffers")
local config = require("kubectl.config")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local tables = require("kubectl.utils.tables")

local M = { is_drawing = false }

local function wrap_hints(data, marks, max_per_row)
  local DIVIDER = " | "
  local PREFIX = "       "
  local PADDING = (" "):rep(#PREFIX)

  local new_data = {}
  local new_marks = {}

  for row_idx, line in ipairs(data) do
    local content = line:gsub("%s*\n$", "")
    local items = vim.split(content:sub(#PREFIX + 1), DIVIDER, { plain = true })

    if #items <= max_per_row then
      table.insert(new_data, content .. " ")
      for _, mark in ipairs(marks) do
        if mark.row == row_idx - 1 then
          local m = vim.deepcopy(mark)
          m.row = #new_data - 1
          table.insert(new_marks, m)
        end
      end
    else
      local row, col = #new_data, 0

      local function start_line(prefix)
        tables.add_mark(new_marks, row, 0, #prefix, hl.symbols.success)
        col = #prefix
        return prefix
      end

      local current = start_line(PREFIX)
      for i, item in ipairs(items) do
        local is_first = (i - 1) % max_per_row == 0

        if is_first and i > 1 then
          table.insert(new_data, current .. " ")
          row = #new_data
          current = start_line(PADDING)
        end

        if not is_first then
          tables.add_mark(new_marks, row, col, col + #DIVIDER, hl.symbols.success)
          current = current .. DIVIDER
          col = col + #DIVIDER
        end

        local key_end = item:find(" ")
        if key_end then
          tables.add_mark(new_marks, row, col, col + key_end - 1, hl.symbols.pending)
        end
        current = current .. item
        col = col + #item
      end
      table.insert(new_data, current .. " ")
    end
  end

  return new_data, new_marks
end

local function is_overlapping()
  local ui = vim.api.nvim_list_uis()[1] -- current UI size
  local height = 10

  local curwin = vim.api.nvim_get_current_win()
  local curpos = vim.api.nvim_win_get_cursor(curwin)
  local screenpos = vim.fn.screenpos(curwin, curpos[1], curpos[2] + 1)
  local cursor_row = screenpos.row

  local float_top = ui.height - height
  local overlapping = (cursor_row >= float_top)

  return overlapping
end

function M.View()
  if not config.options.headers.enabled then
    return
  end
  local group = vim.api.nvim_create_augroup("kubectl_header", { clear = true })

  manager.get_or_create("header")
  M.Draw()

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "K8sDataLoaded",
    callback = function()
      vim.schedule(function()
        M.Draw()
      end)
    end,
  })

  vim.api.nvim_create_autocmd({ "VimResized" }, {
    group = group,
    callback = function()
      local builder = manager.get("header")
      if not builder then
        return
      end
      M.Close()
      vim.schedule(function()
        M.View()
      end)
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorHold" }, {
    group = group,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      local conf = vim.api.nvim_win_get_config(win)

      if conf.relative == "" then
        if is_overlapping() then
          M.Hide()
        else
          vim.schedule(function()
            M.Draw()
          end)
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    group = group,
    callback = function()
      local ft = vim.bo.filetype
      if ft and ft:match("^k8s_") then
        vim.schedule(function()
          M.Draw()
        end)
      end
    end,
  })
end

function M.Draw()
  if not config.options.headers.enabled and M.is_drawing then
    return
  end
  if is_overlapping() then
    return
  end

  local builder = manager.get("header")
  if not builder then
    return
  end
  M.is_drawing = true

  -- Always invalidate cache at draw time to ensure hints reflect current buffer
  tables.invalidate_plug_mapping_cache()
  builder.buf_nr, builder.win_nr = buffers.header_buffer(builder.win_nr)

  local current_win = vim.api.nvim_get_current_win()
  local ok, win_config = pcall(vim.api.nvim_win_get_config, current_win)

  if ok and (win_config.relative == "") then
    local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
    local current_builder = manager.get(buf_name)

    if current_builder then
      local hints = current_builder.definition and current_builder.definition.hints or {}
      builder.addHints(hints, true, true)

      local max_per_row = 4
      local data, marks = wrap_hints(builder.header.data, builder.header.marks, max_per_row)
      buffers.set_content(builder.buf_nr, { content = data, marks = marks })
    end
  end

  buffers.fit_to_content(builder.buf_nr, builder.win_nr, 0)
  M.is_drawing = false
end

function M.Hide()
  local builder = manager.get("header")

  if builder then
    vim.schedule(function()
      pcall(vim.api.nvim_buf_delete, builder.buf_nr, { force = true })
    end)
  end
end

function M.Close()
  local builder = manager.get("header")

  if builder then
    pcall(vim.api.nvim_buf_delete, builder.buf_nr, { force = true })
    manager.remove("header")
  end
end

return M
