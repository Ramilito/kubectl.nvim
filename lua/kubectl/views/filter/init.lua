local buffers = require("kubectl.actions.buffers")
local find = require("kubectl.utils.find")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")

local M = {}

local function load_history()
  local file_path = vim.fn.stdpath("data") .. "/kubectl_filter_history.json"
  local file = io.open(file_path, "r")
  if not file then
    return nil
  end

  local json_data = file:read("*a")
  file:close()

  local ok, decoded = pcall(vim.json.decode, json_data)
  if ok then
    return decoded
  end
  return nil
end

local function save_history(input)
  local history = load_history()
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

  local ok, encoded = pcall(vim.json.encode, result)
  if ok then
    local file_path = vim.fn.stdpath("data") .. "/kubectl_filter_history.json"
    local file = io.open(file_path, "w")
    if file then
      file:write(encoded)
      file:close()
    end
  end
end

function M.filter()
  local buf = buffers.filter_buffer("k8s_filter", save_history, { title = "Filter", header = { data = {} } })
  local header, marks = tables.generateHeader({
    { key = "<enter>", desc = "apply" },
    { key = "<q>", desc = "close" },
  }, false, false)

  local history = load_history()
  if history then
    table.insert(header, "History:")
    for _, value in ipairs(history) do
      table.insert(header, value)
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
