local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local completion = require("kubectl.utils.completion")
local definition = require("kubectl.views.definition")
local find = require("kubectl.utils.find")
local hl = require("kubectl.actions.highlight")
local tables = require("kubectl.utils.tables")

local M = {}

M.cached_api_resources = { values = {}, shortNames = {}, timestamp = nil }

local one_day_in_seconds = 24 * 60 * 60
local current_time = os.time()

if M.timestamp == nil or current_time - M.timestamp >= one_day_in_seconds then
  ResourceBuilder:new("api_resources"):setCmd({ "get", "--raw", "/apis" }, "kubectl"):fetchAsync(function(self)
    self:decodeJson()

    -- process default api group
    commands.shell_command_async("kubectl", { "get", "--raw", "/api/v1" }, function(group_data)
      self.data = group_data
      self:decodeJson()
      definition.process_apis("api", "", "v1", self.data, M.cached_api_resources)
    end)

    if self.data.groups == nil then
      return
    end
    for _, group in ipairs(self.data.groups) do
      local group_name = group.name
      local group_version = group.preferredVersion.groupVersion

      -- Skip if name contains 'metrics.k8s.io'
      if not string.find(group_name, "metrics.k8s.io") then
        commands.shell_command_async("kubectl", { "get", "--raw", "/apis/" .. group_version }, function(group_data)
          self.data = group_data
          self:decodeJson()
          definition.process_apis("apis", group_name, group_version, self.data, M.cached_api_resources)
        end)
      end
    end
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
    { key = "<Plug>(kubectl.alias_view)", desc = "Aliases" },
    { key = "<Plug>(kubectl.filter_view)", desc = "Filter on a phrase" },
    { key = "<Plug>(kubectl.namespace_view)", desc = "Change namespace" },
    { key = "<Plug>(kubectl.go_up)", desc = "Go up a level" },
    { key = "<Plug>(kubectl.delete)", desc = "Delete resource" },
    { key = "<Plug>(kubectl.describe)", desc = "Describe resource" },
    { key = "<Plug>(kubectl.portforwards_view)", desc = "Port forwards" },
    { key = "<Plug>(kubectl.sort)", desc = "Sort column" },
    { key = "<Plug>(kubectl.edit)", desc = "Edit resource" },
    { key = "<Plug>(kubectl.refresh)", desc = "Refresh view" },
    { key = "<Plug>(kubectl.view_1)", desc = "Deployments" },
    { key = "<Plug>(kubectl.view_2)", desc = "Pods " },
    { key = "<Plug>(kubectl.view_3)", desc = "Configmaps " },
    { key = "<Plug>(kubectl.view_4)", desc = "Secrets " },
    { key = "<Plug>(kubectl.view_4)", desc = "Services" },
  }

  local global_keymaps = tables.get_plug_mappings(globals, "n")

  local title = "Buffer mappings: "
  tables.add_mark(marks, #hints, 0, #title, hl.symbols.success)
  table.insert(hints, title .. "\n")
  table.insert(hints, "\n")

  local buffer_keymaps = tables.get_plug_mappings(headers, "n")
  local start_row = #hints
  for index, header in ipairs(buffer_keymaps) do
    local line = header.key .. " " .. (header.long_desc or header.desc)
    table.insert(hints, line .. "\n")
    tables.add_mark(marks, start_row + index - 1, 0, #header.key, hl.symbols.pending)
  end

  table.insert(hints, "\n")
  title = "Global mappings: "
  tables.add_mark(marks, #hints, 0, #title, hl.symbols.success)
  table.insert(hints, title .. "\n")
  table.insert(hints, "\n")

  start_row = #hints
  for index, header in ipairs(global_keymaps) do
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
  local viewsTable = require("kubectl.utils.viewsTable")
  self.data = M.cached_api_resources.values
  self:splitData():decodeJson()
  self.data = definition.merge_views(self.data, viewsTable)

  local header, marks = tables.generateHeader({
    { key = "<enter>", desc = "go to" },
    { key = "<tab>", desc = "suggestion" },
    { key = "<q>", desc = "close" },
  }, false, false)

  local buf = buffers.aliases_buffer(
    "k8s_aliases",
    definition.on_prompt_input,
    { title = "Aliases", header = { data = {} }, suggestions = self.data }
  )

  completion.with_completion(buf, self.data, function()
    -- We reassign the cache since it can be slow to load
    self.data = M.cached_api_resources.values
    self:splitData():decodeJson()
    self.data = definition.merge_views(self.data, viewsTable)
  end)

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

function M.set_and_open_pod_selector(kind, name, ns)
  local pod_view = require("kubectl.views.pods")
  if not kind or not name or not ns then
    return pod_view.View()
  end

  -- save url details
  local pod_definition = require("kubectl.views.pods.definition")
  local original_url = pod_definition.url[1]
  local url_no_query_params, original_query_params = original_url:match("(.+)%?(.+)")

  -- get the selectors for the pods
  local encode = vim.uri_encode
  local get_selectors = { "get", kind, name, "-n", ns, "-o", "json" }
  local resource = vim.json.decode(
    commands.execute_shell_command("kubectl", get_selectors),
    { luanil = { object = true, array = true } }
  )
  local selector_t = resource.spec.selector.matchLabels or resource.metadata.labels
  local key_value_pairs = vim.tbl_map(function(key)
    return encode(key .. "=" .. selector_t[key])
  end, vim.tbl_keys(selector_t))
  local label_selector = "?labelSelector=" .. table.concat(key_value_pairs, encode(","))
  local new_url = url_no_query_params .. label_selector .. "&" .. original_query_params

  pod_definition.url = { new_url }
  vim.notify(
    "Loading pods for " .. kind .. ": " .. name .. " in namespace: " .. ns .. "\nRefresh the view to see all pods"
  )
  pod_view.View()
  pod_definition.url = { original_url }
end

function M.view_or_fallback(view_name)
  local supported_view = nil
  local viewsTable = require("kubectl.utils.viewsTable")
  for k, v in pairs(viewsTable) do
    local found_in_table = find.is_in_table(v, view_name, true)
    if found_in_table or k == view_name then
      supported_view = k
    end
  end
  local view_to_find = supported_view or view_name
  local ok, view = pcall(require, "kubectl.views." .. view_to_find)
  if ok then
    vim.schedule(function()
      pcall(view.View)
    end)
  else
    vim.schedule(function()
      local fallback = require("kubectl.views.fallback")
      fallback.View(nil, view_name)
    end)
  end
end

return M
