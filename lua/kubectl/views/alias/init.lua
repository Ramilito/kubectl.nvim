local buffers = require("kubectl.actions.buffers")
local cache = require("kubectl.cache")
local completion = require("kubectl.utils.completion")
local config = require("kubectl.config")
local definition = require("kubectl.views.alias.definition")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

M.View = function()
  local self = manager.get_or_create("aliases")
  local viewsTable = require("kubectl.utils.viewsTable")
  self.data = cache.cached_api_resources.values
  self.splitData().decodeJson()
  self.data = definition.merge_views(self.data, viewsTable)
  local buf, win = buffers.aliases_buffer(
    "k8s_aliases",
    definition.on_prompt_input,
    { title = "Aliases - " .. vim.tbl_count(self.data), header = { data = {} }, suggestions = self.data }
  )

  local group = vim.api.nvim_create_augroup("kubectl_cacheloaded", { clear = true })
  vim.api.nvim_create_autocmd({ "User" }, {
    pattern = "K8sCacheLoaded",
    group = group,
    callback = function()
      -- check if win and buf are valid
      local _, is_valid_win = pcall(vim.api.nvim_win_is_valid, win)
      local _, is_valid_buf = pcall(vim.api.nvim_buf_is_valid, buf)
      -- if both valid, update the window title
      if is_valid_win and is_valid_buf then
        local new_cached = require("kubectl.cache").cached_api_resources.values
        self.data = new_cached
        self.splitData().decodeJson()
        self.data = definition.merge_views(self.data, viewsTable)
        vim.api.nvim_win_set_config(win, { title = "k8s_aliases - Aliases - " .. vim.tbl_count(self.data) })
      end
    end,
  })

  completion.with_completion(buf, self.data, function()
    -- We reassign the cache since it can be slow to load
    self.data = cache.cached_api_resources.values
    self.splitData().decodeJson()
    self.data = definition.merge_views(self.data, viewsTable)
  end)

  vim.schedule(function()
    local header, marks = tables.generateHeader({
      { key = "<Plug>(kubectl.select)", desc = "apply" },
      { key = "<Plug>(kubectl.refresh)", desc = "refresh" },
      { key = "<Plug>(kubectl.tab)", desc = "next" },
      { key = "<Plug>(kubectl.shift_tab)", desc = "previous" },
      -- TODO: Definition should be moved to mappings.lua
      { key = "<Plug>(kubectl.quit)", desc = "close" },
    }, false, false)
    tables.generateDividerRow(header, marks)

    table.insert(header, "History:")
    local headers_len = #header
    local padding = #state.alias_history < 10 and 2 or 3

    for i, value in ipairs(state.alias_history) do
      table.insert(header, headers_len + 1, string.rep(" ", padding) .. value)
      table.insert(marks, {
        row = headers_len - 1 + i,
        start_col = 0,
        virt_text = { { ("%d"):format(i), hl.symbols.white } },
        virt_text_pos = "overlay",
      })
    end
    table.insert(header, "")

    buffers.set_content(buf, { content = {}, marks = {}, header = { data = header } })
    vim.api.nvim_buf_set_lines(buf, #header, -1, false, { "Aliases: " })

    buffers.apply_marks(buf, marks, header)
    buffers.fit_to_content(buf, win, 1)

    for i = 1, #state.alias_history, 1 do
      vim.keymap.set("n", tostring(i), function()
        local lnum = headers_len + i
        local picked = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""

        local prompt = "% " .. vim.trim(picked)

        vim.api.nvim_buf_set_lines(buf, -2, -1, false, { prompt })
        vim.api.nvim_win_set_cursor(win, { 1, #prompt })
        vim.cmd("startinsert!")

        if config.options.alias.apply_on_select_from_history then
          vim.schedule(function()
            vim.api.nvim_input("<cr>")
          end)
        end
      end, {
        buffer = buf,
        nowait = true,
        silent = true,
        noremap = true,
        desc = "kubectl: select history #" .. i,
      })
    end

    vim.api.nvim_buf_set_keymap(buf, "n", "<Plug>(kubectl.refresh)", "", {
      noremap = true,
      callback = function()
        vim.notify("Refreshing aliases...")
        require("kubectl.cache").LoadFallbackData(true)

        vim.api.nvim_create_autocmd("User", {
          pattern = "K8sCacheLoaded",
          callback = function()
            vim.notify("Refreshing aliases completed")
          end,
        })
      end,
    })

    vim.api.nvim_buf_set_keymap(buf, "n", "<Plug>(kubectl.select)", "", {
      noremap = true,
      callback = function()
        -- Don't act on prompt line
        local current_line = vim.api.nvim_win_get_cursor(0)[1]
        if current_line >= #header then
          return
        end

        local picked = vim.api.nvim_get_current_line()
        local prompt = "% " .. vim.trim(picked)

        vim.api.nvim_buf_set_lines(buf, -2, -1, false, { prompt })
        vim.api.nvim_win_set_cursor(win, { 1, #prompt })
        vim.cmd("startinsert!")

        if config.options.alias.apply_on_select_from_history then
          vim.schedule(function()
            vim.api.nvim_input("<cr>")
          end)
        end
      end,
    })
  end)
end

return M
