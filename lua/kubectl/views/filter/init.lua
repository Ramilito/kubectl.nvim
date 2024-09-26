local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local completion = require("kubectl.utils.completion")
local config = require("kubectl.config")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

local function save_history(input)
  local history = state.filter_history
  local history_size = config.options.filter.max_history

  local result = {}
  local exists = false
  for i = 1, math.min(history_size, #history) do
    if history[i] ~= input then
      table.insert(result, history[i])
    else
      table.insert(result, 1, input)
      exists = true
    end
  end

  if not exists and input ~= "" then
    table.insert(result, 1, input)
    if #result > history_size then
      table.remove(result, #result)
    end
  end

  state.filter_history = result
end

function M.filter_label()
  -- local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  -- local file_name = vim.api.nvim_buf_get_name(0)
  -- local content = table.concat(lines, "\n")

  local builder = ResourceBuilder:new("kubectl_filter_label")

  builder.data = "blabla\nblabla"

  local instance = vim.deepcopy(state.instance)
  instance["header"] = nil
  instance["data"] = nil
  instance["prettyData"] = nil
  instance["processedData"] = nil
  instance["extmarks"] = nil

  vim.print("res: " .. vim.inspect(instance))
  -- local res_view_ok, res_view = pcall(require, "kubectl.views." .. res)
  -- vim.print("res_view" .. vim.inspect(res_view) .. " " .. vim.inspect(res_view_ok))
  -- local sel_ok, selection = pcall("getCurrentSelection")
  -- vim.print("selection" .. selection .. " " .. vim.inspect(sel_ok))
  builder:splitData()
  vim.schedule(function()
    local win_config
    builder.buf_nr, win_config = buffers.confirmation_buffer("Filter for labels", "label_filter", function(confirm)
      if confirm then
        vim.print("confirmed")
      end
    end)

    local confirmation = "[y]es [n]o:"
    local padding = string.rep(" ", (win_config.width - #confirmation) / 2)

    table.insert(builder.data, padding .. confirmation)
    builder:setContentRaw()
  end)
end

function M.filter()
  local buf = buffers.filter_buffer("k8s_filter", save_history, { title = "Filter", header = { data = {} } })

  local list = {}
  for _, value in ipairs(state.filter_history) do
    table.insert(list, { name = value })
  end
  completion.with_completion(buf, list, nil, false)

  local header, marks = tables.generateHeader({
    { key = "<Plug>(kubectl.select)", desc = "apply" },
    { key = "<Plug>(kubectl.tab)", desc = "next" },
    { key = "<Plug>(kubectl.shift_tab)", desc = "previous" },
    -- TODO: Definition should be moved to mappings.lua
    { key = "<Plug>(kubectl.quit)", desc = "close" },
  }, false, false)

  table.insert(header, "History:")
  local headers_len = #header
  for _, value in ipairs(state.filter_history) do
    table.insert(header, headers_len + 1, value)
  end
  table.insert(header, "")

  buffers.set_content(buf, { content = {}, marks = {}, header = { data = header } })
  vim.api.nvim_buf_set_lines(buf, #header, -1, false, { "Filter: " .. state.getFilter(), "" })

  -- TODO: Marks should be set in buffers.set_content above
  buffers.apply_marks(buf, marks, header)
  buffers.fit_to_content(buf, 0)

  -- TODO: Registering keymap after generateheader makes it not appear in hints
  vim.api.nvim_buf_set_keymap(buf, "n", "<Plug>(kubectl.select)", "", {
    noremap = true,
    callback = function()
      local line = vim.api.nvim_get_current_line()

      -- Don't act on prompt line
      local current_line = vim.api.nvim_win_get_cursor(0)[1]
      if current_line >= #header then
        return
      end

      local prompt = "% "

      vim.api.nvim_buf_set_lines(buf, #header + 1, -1, false, { prompt .. line })
      vim.api.nvim_win_set_cursor(0, { #header + 2, #(prompt .. line) })
      vim.cmd("startinsert!")

      if config.options.filter.apply_on_select_from_history then
        vim.schedule(function()
          vim.api.nvim_input("<cr>")
        end)
      end
    end,
  })
end

return M
