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

M.definition = {
  resource = "aliases",
  ft = "k8s_aliases",
  title = "Aliases",
  hints = {
    { key = "<Plug>(kubectl.select)", desc = "apply" },
    { key = "<Plug>(kubectl.refresh)", desc = "refresh" },
    { key = "<Plug>(kubectl.tab)", desc = "next" },
    { key = "<Plug>(kubectl.shift_tab)", desc = "previous" },
    { key = "<Plug>(kubectl.quit)", desc = "close" },
  },
  panes = {
    { title = "Aliases", prompt = true },
  },
}

M.View = function()
  local builder = manager.get_or_create(M.definition.resource)
  local viewsTable = require("kubectl.utils.viewsTable")
  builder.data = cache.cached_api_resources.values
  builder.splitData().decodeJson()
  builder.data = definition.merge_views(builder.data, viewsTable)

  builder.view_framed(M.definition)

  local buf = builder.buf_nr
  local win = builder.win_nr

  -- Set up prompt callback
  vim.fn.prompt_setcallback(buf, function(input)
    definition.on_prompt_input(input)
    vim.cmd("stopinsert")
    vim.api.nvim_set_option_value("modified", false, { buf = buf })
    vim.cmd.fclose()
  end)

  vim.cmd("startinsert")

  -- Set up autocmd for cache reload
  local group = vim.api.nvim_create_augroup("kubectl_cacheloaded", { clear = true })
  vim.api.nvim_create_autocmd({ "User" }, {
    pattern = "K8sCacheLoaded",
    group = group,
    callback = function()
      local _, is_valid_win = pcall(vim.api.nvim_win_is_valid, win)
      local _, is_valid_buf = pcall(vim.api.nvim_buf_is_valid, buf)
      if is_valid_win and is_valid_buf then
        local new_cached = require("kubectl.cache").cached_api_resources.values
        builder.data = new_cached
        builder.splitData().decodeJson()
        builder.data = definition.merge_views(builder.data, viewsTable)
      end
    end,
  })

  -- Set up completion
  completion.with_completion(buf, builder.data, function()
    builder.data = cache.cached_api_resources.values
    builder.splitData().decodeJson()
    builder.data = definition.merge_views(builder.data, viewsTable)
  end)

  vim.schedule(function()
    -- Render hints
    builder.renderHints()

    -- Build content
    local content = {}
    local marks = {}

    tables.generateDividerRow(content, marks)

    table.insert(content, "History:")
    local history_start = #content
    local padding = #state.alias_history < 10 and 2 or 3

    for i, value in ipairs(state.alias_history) do
      table.insert(content, string.rep(" ", padding) .. value)
      table.insert(marks, {
        row = #content - 1,
        start_col = 0,
        virt_text = { { ("%d"):format(i), hl.symbols.white } },
        virt_text_pos = "overlay",
      })
    end
    table.insert(content, "")

    -- Set content and prompt
    buffers.set_content(buf, { content = content, marks = {}, header = { data = {} } })
    vim.api.nvim_buf_set_lines(buf, #content, -1, false, { "Aliases: " })
    buffers.apply_marks(buf, marks, content)
    buffers.fit_to_content(buf, win, 1)

    -- History number keymaps
    for i = 1, #state.alias_history, 1 do
      vim.keymap.set("n", tostring(i), function()
        local lnum = history_start + i
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

    -- Refresh keymap
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

    -- Select from list keymap
    vim.api.nvim_buf_set_keymap(buf, "n", "<Plug>(kubectl.select)", "", {
      noremap = true,
      callback = function()
        local current_line = vim.api.nvim_win_get_cursor(0)[1]
        if current_line >= #content then
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
