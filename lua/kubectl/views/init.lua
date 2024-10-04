local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local completion = require("kubectl.utils.completion")
local config = require("kubectl.config")
local definition = require("kubectl.views.definition")
local find = require("kubectl.utils.find")
local hl = require("kubectl.actions.highlight")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local url = require("kubectl.utils.url")

local M = {}

M.cached_api_resources = { values = {}, shortNames = {}, timestamp = nil }

local one_day_in_seconds = 24 * 60 * 60
local current_time = os.time()

M.LoadFallbackData = function(force)
  if force or M.timestamp == nil or current_time - M.timestamp >= one_day_in_seconds then
    M.cached_api_resources.values = {}
    M.cached_api_resources.shortNames = {}

    local cmds = {
      {
        cmd = "kubectl",
        args = { "get", "--raw", "/api/v1" },
      },
      {
        cmd = "kubectl",
        args = { "get", "--raw", "/apis" },
      },
    }
    ResourceBuilder:new("api_resources"):fetchAllAsync(cmds, function(self)
      self:decodeJson()
      definition.process_apis("api", "", "v1", self.data[1], M.cached_api_resources)

      if self.data[2].groups == nil then
        return
      end
      local group_cmds = {}
      for _, group in ipairs(self.data[2].groups) do
        local group_name = group.name
        local group_version = group.preferredVersion.groupVersion

        -- Skip if name contains 'metrics.k8s.io'
        if not string.find(group.name, "metrics.k8s.io") then
          table.insert(group_cmds, {
            group_name = group_name,
            group_version = group_version,
            cmd = "kubectl",
            args = { "get", "--raw", "/apis/" .. group_version },
          })
        end
      end

      self:fetchAllAsync(group_cmds, function(results)
        for _, value in ipairs(results.data) do
          self.data = value
          self:decodeJson()
          definition.process_apis("apis", "", self.data.groupVersion, self.data, M.cached_api_resources)
        end
      end)
    end)

    M.timestamp = os.time()
  end
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
    { key = "<Plug>(kubectl.filter_label)", desc = "Filter on labels" },
    { key = "<Plug>(kubectl.namespace_view)", desc = "Change namespace" },
    { key = "<Plug>(kubectl.contexts_view)", desc = "Change context" },
    { key = "<Plug>(kubectl.go_up)", desc = "Go up a level" },
    { key = "<Plug>(kubectl.delete)", desc = "Delete resource" },
    { key = "<Plug>(kubectl.describe)", desc = "Describe resource" },
    { key = "<Plug>(kubectl.portforwards_view)", desc = "Port forwards" },
    { key = "<Plug>(kubectl.sort)", desc = "Sort column" },
    { key = "<Plug>(kubectl.edit)", desc = "Edit resource" },
    { key = "<Plug>(kubectl.refresh)", desc = "Refresh view" },
    { key = "<Plug>(kubectl.view_deployments)", desc = "Deployments" },
    { key = "<Plug>(kubectl.view_pods)", desc = "Pods" },
    { key = "<Plug>(kubectl.view_configmaps)", desc = "Configmaps" },
    { key = "<Plug>(kubectl.view_secrets)", desc = "Secrets" },
    { key = "<Plug>(kubectl.view_services)", desc = "Services" },
    { key = "<Plug>(kubectl.view_ingresses)", desc = "Ingresses" },
    { key = "<Plug>(kubectl.view_api_resources)", desc = "API-Resources" },
    { key = "<Plug>(kubectl.view_clusterrolebinding)", desc = "ClusterRoleBindings" },
    { key = "<Plug>(kubectl.view_crds)", desc = "CRDs" },
    { key = "<Plug>(kubectl.view_cronjobs)", desc = "CronJobs" },
    { key = "<Plug>(kubectl.view_daemonsets)", desc = "DaemonSets" },
    { key = "<Plug>(kubectl.view_events)", desc = "Events" },
    { key = "<Plug>(kubectl.view_helm)", desc = "Helm" },
    { key = "<Plug>(kubectl.view_jobs)", desc = "Jobs" },
    { key = "<Plug>(kubectl.view_nodes)", desc = "Nodes" },
    { key = "<Plug>(kubectl.view_overview)", desc = "Overview" },
    { key = "<Plug>(kubectl.view_pv)", desc = "PersistentVolumes" },
    { key = "<Plug>(kubectl.view_pvc)", desc = "PersistentVolumeClaims" },
    { key = "<Plug>(kubectl.view_sa)", desc = "ServiceAccounts" },
    { key = "<Plug>(kubectl.view_top_nodes)", desc = "Top Nodes" },
    { key = "<Plug>(kubectl.view_top_pods)", desc = "Top Pods" },
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

  vim.schedule(function()
    local header, marks = tables.generateHeader({
      { key = "<Plug>(kubectl.select)", desc = "apply" },
      { key = "<Plug>(kubectl.tab)", desc = "next" },
      { key = "<Plug>(kubectl.shift_tab)", desc = "previous" },
      -- TODO: Definition should be moved to mappings.lua
      { key = "<Plug>(kubectl.quit)", desc = "close" },
    }, false, false)

    table.insert(header, "History:")
    local headers_len = #header
    for _, value in ipairs(state.alias_history) do
      table.insert(header, headers_len + 1, value)
    end
    table.insert(header, "")

    buffers.set_content(buf, { content = {}, marks = {}, header = { data = header } })
    vim.api.nvim_buf_set_lines(buf, #header, -1, false, { "Aliases: " })

    buffers.apply_marks(buf, marks, header)
    buffers.fit_to_content(buf, 1)

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
        vim.api.nvim_win_set_cursor(0, { #header + 2, #prompt })
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
  self:addHints({ { key = "<Plug>(kubectl.kill)", desc = "Kill PF" } }, false, false, false):setContent()

  vim.keymap.set("n", "q", function()
    vim.api.nvim_set_option_value("modified", false, { buf = self.buf_nr })
    vim.cmd.close()
    vim.api.nvim_input("<Plug>(kubectl.refresh)")
  end, { buffer = self.buf_nr, silent = true })
end

--- Execute a user command and handle the response
---@param args table
function M.UserCmd(args)
  ResourceBuilder:new("k8s_usercmd"):setCmd(args, "kubectl"):fetchAsync(function(self)
    if self.data == "" then
      return
    end
    self:splitData()
    self.prettyData = self.data

    vim.schedule(function()
      self:display("k8s_usercmd", "UserCmd"):setContent()
    end)
  end)
end

function M.set_and_open_pod_selector(name, ns)
  local kind = state.instance.resource
  local pod_view, pod_definition = M.view_and_definition("pods")
  if not name or not ns then
    return pod_view.View()
  end

  -- save url details
  local original_url = pod_definition.url[1]
  local url_no_query_params, original_query_params = url.breakUrl(original_url, true, false)

  -- get the selectors for the pods
  local encode = vim.uri_encode
  local resource = tables.find_resource(state.instance.data, name, ns)
  if not resource then
    return
  end
  local selector_t = (resource.spec.selector and resource.spec.selector.matchLabels or resource.spec.selector)
    or resource.metadata.labels
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

function M.view_and_definition(view_name)
  local view_ok, view = pcall(require, "kubectl.views." .. view_name)
  if not view_ok then
    view_name = "fallback"
    view = require("kubectl.views.fallback")
  end
  local view_definition = require("kubectl.views." .. view_name .. ".definition")
  return view, view_definition
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
