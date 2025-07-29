local buffers = require("kubectl.actions.buffers")
local config = require("kubectl.config")
local manager = require("kubectl.resource_manager")

local M = {}
function M.View()
  if not config.options.headers.enabled then
    return
  end
  vim.api.nvim_create_augroup("kubectl_header", { clear = true })

  local ui = vim.api.nvim_list_uis()[1] -- current UI size
  local height = 20
  local row = ui.height - height
  local show_header = true

  local function refresh_header()
    if not config.options.headers.enabled then
      return
    end

    if not show_header then
      return
    end
    local builder = manager.get_or_create("header")
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
        height = #builder.header.data + 1
        row = ui.height - height
      end
    end

    buffers.fit_to_content(builder.buf_nr, builder.win_nr, 0)
  end

  refresh_header()

  vim.api.nvim_create_autocmd("User", {
    group = "kubectl_header",
    pattern = "K8sDataLoaded",
    callback = function()
      refresh_header()
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = "kubectl_header",
    pattern = "*",
    callback = function(_)
      local ft = vim.bo.filetype
      if ft:match("^k8s_") then
        vim.schedule(function()
          refresh_header()
        end)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = "kubectl_header",
    callback = function()
      local curwin = vim.api.nvim_get_current_win()
      local curpos = vim.api.nvim_win_get_cursor(curwin)
      local screenpos = vim.fn.screenpos(curwin, curpos[1], curpos[2] + 1)
      local cursor_row = screenpos.row

      local float_top = row - 2
      local overlapping = (cursor_row >= float_top)

      local builder = manager.get("header")
      if not builder then
        return
      end
      if overlapping and show_header then
        vim.schedule(function()
          pcall(vim.api.nvim_buf_delete, builder.buf_nr, { force = true })
        end)
        show_header = false
      elseif (not overlapping) and not show_header then
        show_header = true
        refresh_header()
      end
    end,
  })
end
return M
