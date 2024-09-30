local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local completion = require("kubectl.utils.completion")
local config = require("kubectl.config")
local tables = require("kubectl.utils.tables")
local url = require("kubectl.utils.url")
local views = require("kubectl.views")

local M = {}

function M.save_history(input)
  local state = require("kubectl.state")
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
  local state = require("kubectl.state")
  local instance = state.instance
  local view, definition = views.view_and_definition(instance.resource)
  local name, ns = view.getCurrentSelection()
  if not name then
    return
  end

  local resource = tables.find_resource(instance.data, name, ns)
  if not resource then
    return
  end
  local labels = resource.metadata and resource.metadata.labels or {}
  table.sort(labels)
  local original_url = vim.deepcopy(definition.url)

  -- Create ResourceBuilder and buffer
  local builder = ResourceBuilder:new("kubectl_filter_label")
  local win_config
  builder.buf_nr, win_config = buffers.confirmation_buffer("Filter for labels", "label_filter", function(confirm)
    if not confirm then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(builder.buf_nr, 0, -1, false)
    local new_labels = {}
    for _, line in ipairs(lines) do
      local match = line:match("([^=]+=.+)")
      table.insert(new_labels, match)
    end
    if #new_labels == 0 then
      return
    end
    local new_args
    if definition.cmd == "kubectl" then
      new_args = { "get", definition.resource, "-o=json", "-l", table.concat(new_labels, ",") }
      if ns then
        table.insert(new_args, "-n")
        table.insert(new_args, ns)
      end
    else
      local url_str = original_url[#original_url]
      local url_no_query_params, original_query_params = url.breakUrl(url_str, true, false)
      local label_selector = "?labelSelector=" .. vim.uri_encode(table.concat(new_labels, ","), "rfc2396")
      new_args = vim.deepcopy(original_url)
      new_args[#new_args] = url_no_query_params .. label_selector .. "&" .. original_query_params
    end

    -- display view
    state.setFilter("")
    definition.url = new_args
    view.configure_definition = false
    view.View()
    definition.url = original_url
    view.configure_definition = true
  end)

  local confirmation = "[y]es [n]o:"
  local padding = string.rep(" ", (win_config.width - #confirmation) / 2)

  -- Add current label to buffer
  builder.data = { "Current labels:" }
  for k, v in pairs(labels) do
    table.insert(builder.data, k .. "=" .. v)
  end
  table.insert(builder.data, padding .. confirmation)
  builder:splitData()
  builder:setContentRaw()
  vim.cmd([[syntax match KubectlSuccess /.*=\@=/]])
  vim.cmd([[syntax match KubectlDebug /=\@<=.*/]])
end

function M.filter()
  local state = require("kubectl.state")
  local buf = buffers.filter_buffer("k8s_filter", M.save_history, { title = "Filter", header = { data = {} } })

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

  -- Add textual hints
  local header_len = #header
  table.insert(header, header_len - 1, "Use commas to separate multiple patterns.")
  table.insert(header, header_len - 1, "Prefix a pattern with ! for negative filtering.")
  table.insert(header, header_len - 1, "All patterns must match for a line to be included.")
  marks[#marks].row = #header - 1

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
