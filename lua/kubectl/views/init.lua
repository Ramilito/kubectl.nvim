local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.definition")
local hl = require("kubectl.actions.highlight")
local tables = require("kubectl.utils.tables")

local M = {}

M.cached_api_resources = { values = {}, timestamp = nil }

local one_day_in_seconds = 24 * 60 * 60
local current_time = os.time()

if M.timestamp == nil or current_time - M.timestamp >= one_day_in_seconds then
  commands.shell_command_async("kubectl", { "api-resources", "-o", "name", "--cached" }, function(data)
    M.cached_api_resources.values = data
    M.timestamp = os.time()
  end)
end

--- Generate hints and display them in a floating buffer
---@alias Hint { key: string, desc: string, long_desc: string }
---@param headers Hint[]
function M.Hints(headers)
  local marks = {}
  local hints = {}
  local globals = {
    { key = "<C-a>", desc = "Aliases" },
    { key = "<C-f>", desc = "Filter on a phrase" },
    { key = "<C-n>", desc = "Change namespace" },
    { key = "<bs> ", desc = "Go up a level" },
    { key = "<gD> ", desc = "Delete resource" },
    { key = "<gP> ", desc = "Port forwards" },
    { key = "<gs> ", desc = "Sort column" },
    { key = "<ge> ", desc = "Edit resource" },
    { key = "<gr> ", desc = "Refresh view" },
    { key = "<0>  ", desc = "Root" },
    { key = "<1>  ", desc = "Deployments" },
    { key = "<2>  ", desc = "Pods " },
    { key = "<3>  ", desc = "Configmaps " },
    { key = "<4>  ", desc = "Secrets " },
    { key = "<5>  ", desc = "Services" },
  }

  local title = "Buffer mappings: "
  tables.add_mark(marks, #hints, 0, #title, hl.symbols.success)
  table.insert(hints, title .. "\n")
  table.insert(hints, "\n")

  local start_row = #hints
  for index, header in ipairs(headers) do
    local line = header.key .. " " .. header.long_desc
    table.insert(hints, line .. "\n")
    tables.add_mark(marks, start_row + index - 1, 0, #header.key, hl.symbols.pending)
  end

  table.insert(hints, "\n")
  title = "Global mappings: "
  tables.add_mark(marks, #hints, 0, #title, hl.symbols.success)
  table.insert(hints, title .. "\n")
  table.insert(hints, "\n")

  start_row = #hints
  for index, header in ipairs(globals) do
    local line = header.key .. " " .. header.desc
    table.insert(hints, line .. "\n")
    tables.add_mark(marks, start_row + index - 1, 0, #header.key, hl.symbols.pending)
  end

  local buf = buffers.floating_dynamic_buffer("k8s_hints", "Hints", false)

  local content = vim.split(table.concat(hints, ""), "\n")
  buffers.set_content(buf, { content = content, marks = marks })
end

function M.Aliases()
  local self = ResourceBuilder:new("aliases")

  self.data = M.cached_api_resources.values
  self:splitData():decodeJson()

  local current_suggestion_index = 0
  local original_input = ""
  local header, marks = tables.generateHeader({
    { key = "<enter>", desc = "go to" },
    { key = "<tab>", desc = "suggestion" },
    { key = "<q>", desc = "close" },
  }, false, false)

  local function update_prompt_with_suggestion(bufnr, suggestion)
    local prompt = "% "
    vim.api.nvim_buf_set_lines(
      bufnr,
      #header + 1,
      -1,
      false,
      { prompt .. original_input .. suggestion:sub(#original_input + 1) }
    )
    vim.api.nvim_win_set_cursor(0, { #header, #prompt + #suggestion })
  end

  local buf = buffers.aliases_buffer(
    "k8s_aliases",
    definition.on_prompt_input,
    { title = "Aliases", header = { data = {} }, suggestions = self.data }
  )

  vim.api.nvim_buf_set_keymap(buf, "i", "<Tab>", "", {
    noremap = true,
    callback = function()
      local line = vim.api.nvim_get_current_line()
      local input = line:sub(3) -- Remove the `% ` prefix to get the user input

      if current_suggestion_index == 0 then
        original_input = input
      end

      -- Filter suggestions based on input
      local filtered_suggestions = {}

      -- We reassign the cache since it can be slow to load
      self.data = M.cached_api_resources.values
      self:splitData():decodeJson()

      for _, suggestion in ipairs(self.data) do
        if suggestion:sub(1, #original_input) == original_input then
          table.insert(filtered_suggestions, suggestion)
        end
      end

      -- Cycle through the suggestions
      if #filtered_suggestions > 0 then
        current_suggestion_index = current_suggestion_index + 1
        if current_suggestion_index >= #filtered_suggestions + 1 then
          update_prompt_with_suggestion(buf, original_input)
          current_suggestion_index = 0 -- Reset the index if no suggestions are available
        else
          update_prompt_with_suggestion(buf, filtered_suggestions[current_suggestion_index])
        end
      else
        update_prompt_with_suggestion(buf, original_input)
        current_suggestion_index = 0 -- Reset the index if no suggestions are available
      end
      return ""
    end,
  })

  vim.api.nvim_buf_set_lines(buf, 0, #header, false, header)
  vim.api.nvim_buf_set_lines(buf, #header, -1, false, { "Aliases: " })

  buffers.apply_marks(buf, marks, header)
end

--- PortForwards function retrieves port forwards and displays them in a float window.
-- @function PortForwards
-- @return nil
function M.PortForwards()
  local pfs = {}
  pfs = definition.getPFData(pfs, false, "all")

  local self = ResourceBuilder:new("Port forward"):displayFloatFit("k8s_port_forwards", "Port forwards")
  self.data = definition.getPFRows(pfs)
  self.extmarks = {}

  self.prettyData, self.extmarks = tables.pretty_print(self.data, { "PID", "TYPE", "RESOURCE", "PORT" })
  self:addHints({ { key = "<gk>", desc = "Kill PF" } }, false, false, false):setContent()
end

--- Execute a user command and handle the response
---@param args table
function M.UserCmd(args)
  ResourceBuilder:new("k8s_usercmd"):setCmd(args):fetchAsync(function(self)
    if self.data == "" then
      return
    end
    self:splitData()
    self.prettyData = self.data

    vim.schedule(function()
      self:display("k8s_usercmd", "UserCmd")
    end)
  end)
end

return M
