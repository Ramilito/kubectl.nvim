local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

local function save_history(input)
  local history = commands.load_config("kubectl_filter_history.json")
  local history_size = 5

  if history == nil then
    history = {}
  end

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

  commands.save_config("kubectl_filter_history.json", result)
end

function M.filter()
  local buf = buffers.filter_buffer("k8s_filter", save_history, { title = "Filter", header = { data = {} } })
  local header, marks = tables.generateHeader({
    { key = "<enter>", desc = "apply" },
    { key = "<q>", desc = "close" },
  }, false, false)

  local history = commands.load_config("kubectl_filter_history.json")
  if history then
    table.insert(header, "History:")
    local headers_len = #header
    for _, value in ipairs(history) do
      table.insert(header, headers_len + 1, value)
    end
    table.insert(header, "")
  end

  vim.api.nvim_buf_set_lines(buf, 0, #header, false, header)
  vim.api.nvim_buf_set_lines(buf, #header, -1, false, { "Filter: " .. state.getFilter(), "" })

  buffers.apply_marks(buf, marks, header)

  vim.api.nvim_buf_set_keymap(buf, "n", "<cr>", "", {
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
      vim.api.nvim_win_set_cursor(0, { #header + 2, #prompt })
      vim.cmd("startinsert")
    end,
  })
end

return M
