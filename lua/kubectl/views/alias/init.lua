local buffers = require("kubectl.actions.buffers")
local cache = require("kubectl.cache")
local completion = require("kubectl.utils.completion")
local config = require("kubectl.config")
local definition = require("kubectl.views.definition")
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

  -- autocmd for KubectlCacheLoaded
  vim.api.nvim_create_autocmd({ "User" }, {
    pattern = "KubectlCacheLoaded",
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
    for _, value in ipairs(state.alias_history) do
      table.insert(header, headers_len + 1, value)
    end
    table.insert(header, "")

    buffers.set_content(buf, { content = {}, marks = {}, header = { data = header } })
    vim.api.nvim_buf_set_lines(buf, #header, -1, false, { "Aliases: " })

    buffers.apply_marks(buf, marks, header)
    buffers.fit_to_content(buf, win, 1)

    vim.api.nvim_buf_set_keymap(buf, "n", "<Plug>(kubectl.refresh)", "", {
      noremap = true,
      callback = function()
        vim.notify("Refreshing aliases...")
        require("kubectl.cache").LoadFallbackData(true)

        vim.api.nvim_create_autocmd("User", {
          pattern = "KubectlCacheLoaded",
          callback = function()
            vim.notify("Refreshing aliases completed")
          end,
        })
      end,
    })

    vim.api.nvim_buf_set_keymap(buf, "n", "<Plug>(kubectl.select)", "", {
      noremap = true,
      callback = function()
        local line = vim.api.nvim_get_current_line()
				print(line)

        -- Don't act on prompt line
        local current_line = vim.api.nvim_win_get_cursor(0)[1]
        if current_line >= #header then
          return
        end

        local prompt = "% "

        vim.api.nvim_buf_set_lines(buf, #header + 1, -1, false, { prompt .. line })
        vim.api.nvim_win_set_cursor(0, { #header + 2, #prompt })
        vim.cmd("startinsert!")

        if config.options.alias.apply_on_select_from_history then
          vim.schedule(function()
            -- vim.api.nvim_input("<cr>")
          end)
        end
      end,
    })
  end)
end

return M
