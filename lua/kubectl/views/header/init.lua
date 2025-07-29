local buffers = require("kubectl.actions.buffers")
local config = require("kubectl.config")
local manager = require("kubectl.resource_manager")

local M = {
  debounce_ms = 150,
  pendin_id = nil,
}

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
  vim.api.nvim_create_augroup("kubectl_header", { clear = true })

  manager.get_or_create("header")
  M.Draw()

  vim.api.nvim_create_autocmd("User", {
    group = "kubectl_header",
    pattern = "K8sDataLoaded",
    callback = function()
      M.Draw()
    end,
  })

  vim.api.nvim_create_autocmd({ "VimResized" }, {
    group = "kubectl_header",
    callback = function()
      local builder = manager.get("header")
      if not builder then
        return
      end
      M.Close()
      M.View()
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = "kubectl_header",
    callback = function()
      if M.pending_id then
        vim.fn.timer_stop(M.pending_id)
      end

      M.pending_id = vim.fn.timer_start(M.debounce_ms, function()
        M.pending_id = nil

        local win = vim.api.nvim_get_current_win()
        local conf = vim.api.nvim_win_get_config(win)

        if conf.relative == "" then
          if is_overlapping() then
            M.Hide()
          else
            M.Draw()
          end
        end
      end)
    end,
  })
end

function M.Draw()
  if not config.options.headers.enabled then
    return
  end
  if is_overlapping() then
    return
  end

  local builder = manager.get("header")
  if not builder then
    return
  end
  builder.buf_nr, builder.win_nr = buffers.header_buffer(builder.win_nr)

  local current_win = vim.api.nvim_get_current_win()
  local ok, win_config = pcall(vim.api.nvim_win_get_config, current_win)

  if ok and (win_config.relative == "") then
    local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
    local current_builder = manager.get(buf_name)

    if current_builder then
      local hints = current_builder.definition and current_builder.definition.hints or {}
      builder.addHints(hints, true, true)
      buffers.set_content(builder.buf_nr, { content = builder.header.data, marks = builder.header.marks })
    end
  end

  buffers.fit_to_content(builder.buf_nr, builder.win_nr, 0)
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
    vim.schedule(function()
      pcall(vim.api.nvim_buf_delete, builder.buf_nr, { force = true })
      manager.remove("header")
    end)
  end
end

return M
