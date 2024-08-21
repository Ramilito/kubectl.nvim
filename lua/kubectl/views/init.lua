local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local definition = require("kubectl.views.definition")
local hl = require("kubectl.actions.highlight")
local notifications = require("kubectl.notification")
local tables = require("kubectl.utils.tables")

local M = {}

M.cached_api_resources = { values = {}, shortNames = {}, timestamp = nil }

--- Decode a JSON string
--- @param string string The JSON string to decode
--- @return table|nil result The decoded table or nil if decoding fails
local decode = function(string)
  local success, result = pcall(vim.json.decode, string)
  if success then
    return result
  else
    vim.notify("Error: api-resources unavailable", vim.log.levels.ERROR)
  end
end

local one_day_in_seconds = 24 * 60 * 60
local current_time = os.time()

if M.timestamp == nil or current_time - M.timestamp >= one_day_in_seconds then
  commands.shell_command_async("kubectl", { "get", "--raw", "/apis" }, function(data)
    local apis = decode(data)
    -- apis.groups
    for _, group in ipairs(apis.groups) do
      local group_name = group.name
      local group_version = group.preferredVersion.groupVersion
      -- check if name contains 'metrics.k8s.io' and skip
      if string.find(group_name, "metrics.k8s.io") then
        goto next_group
      end
      commands.shell_command_async("kubectl", { "get", "--raw", "/apis/" .. group_version }, function(group_data)
        local group_resources = decode(group_data)
        for _, resource in ipairs(group_resources.resources) do
          if string.find(resource.name, "/status") then
            goto next_resource
          end
          local resource_name = resource.name .. "." .. group_name
          local resource_url = "{{BASE}}/apis/" .. group_version .. "/" .. resource.name
          M.cached_api_resources.values[resource_name] = {
            name = resource.name,
            url = resource_url,
          }
          M.cached_api_resources.shortNames[resource.name] = resource_name
          if resource.singularName then
            M.cached_api_resources.shortNames[resource.singularName] = resource_name
          end
          if resource.shortNames then
            for _, shortName in ipairs(resource.shortNames) do
              M.cached_api_resources.shortNames[shortName] = resource_name
            end
          end
          ::next_resource::
        end
      end)
    end
    ::next_group::
  end)
  M.timestamp = os.time()
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

      for _, suggestion in pairs(self.data) do
        if suggestion.name:sub(1, #original_input) == original_input then
          table.insert(filtered_suggestions, suggestion.name)
        end
      end
      vim.schedule(function()
        notifications.Add({
          "in here",
        })
      end)

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

  vim.keymap.set("n", "q", function()
    vim.api.nvim_set_option_value("modified", false, { buf = self.buf_nr })
    vim.cmd.close()
    vim.api.nvim_input("gr")
  end, { buffer = self.buf_nr, silent = true })
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
