local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local cache = require("kubectl.cache")
local completion = require("kubectl.utils.completion")
local config = require("kubectl.config")
local definition = require("kubectl.views.definition")
local find = require("kubectl.utils.find")
local hl = require("kubectl.actions.highlight")
local mappings = require("kubectl.mappings")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local url = require("kubectl.utils.url")

local M = {}

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
    { key = "<Plug>(kubectl.yaml)", desc = "View YAML" },
    { key = "<Plug>(kubectl.portforwards_view)", desc = "Port forwards" },
    { key = "<Plug>(kubectl.sort)", desc = "Sort column" },
    { key = "<Plug>(kubectl.edit)", desc = "Edit resource" },
    { key = "<Plug>(kubectl.toggle_headers)", desc = "Toggle headers" },
    { key = "<Plug>(kubectl.lineage)", desc = "View Lineage" },
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

  local buf = buffers.floating_dynamic_buffer("k8s_hints", "Hints", nil)

  local content = vim.split(table.concat(hints, ""), "\n")
  buffers.set_content(buf, { content = content, marks = marks })
end

function M.Picker()
  vim.cmd("fclose!")

  local self = ResourceBuilder:new("Picker")

  self:displayFloatFit("k8s_picker", "Picker")
  local data = {}

  for id, value in pairs(state.buffers) do
    table.insert(data, tostring(id) .. " | " .. value.args[1] .. " - " .. value.args[2])
  end
  self.data = data

  self:addHints({
    { key = "<Plug>(kubectl.kill)", desc = "kill" },
    { key = "<Plug>(kubectl.select)", desc = "select" },
  }, false, false, false)

  vim.api.nvim_buf_set_keymap(self.buf_nr, "n", "<Plug>(kubectl.kill)", "", {
    noremap = true,
    callback = function()
      local line = vim.api.nvim_get_current_line()
      local bufnr = line:match("^(%d+)%s*|")

      state.buffers[bufnr] = nil
    end,
  })

  vim.api.nvim_buf_set_keymap(self.buf_nr, "n", "<Plug>(kubectl.select)", "", {
    noremap = true,
    callback = function()
      local line = vim.api.nvim_get_current_line()
      local bufnr = line:match("^(%d+)%s*|")

      local buffer = state.buffers[tonumber(bufnr)]

      if buffer then
        vim.cmd("fclose!")
        vim.schedule(function()
          buffer.open(unpack(buffer.args))
        end)
      end
    end,
  })
  vim.schedule(function()
    self:setContentRaw()
    mappings.map_if_plug_not_set("n", "gk", "<Plug>(kubectl.kill)")
  end)
end

function M.Aliases()
  local self = ResourceBuilder:new("aliases")
  local viewsTable = require("kubectl.utils.viewsTable")
  self.data = cache.cached_api_resources.values
  self:splitData():decodeJson()
  self.data = definition.merge_views(self.data, viewsTable)
  local buf, win = buffers.aliases_buffer(
    "k8s_aliases",
    definition.on_prompt_input,
    { title = "Aliases - " .. vim.tbl_count(self.data), header = { data = {} }, suggestions = self.data }
  )

  -- autocmd for KubectlCacheLoaded
  vim.api.nvim_create_autocmd("User", {
    pattern = "KubectlCacheLoaded",
    callback = function()
      -- check if win and buf are valid
      local _, is_valid_win = pcall(vim.api.nvim_win_is_valid, win)
      local _, is_valid_buf = pcall(vim.api.nvim_buf_is_valid, buf)
      -- if both valid, update the window title
      if is_valid_win and is_valid_buf then
        local new_cached = require("kubectl.cache").cached_api_resources.values
        self.data = new_cached
        self:splitData():decodeJson()
        self.data = definition.merge_views(self.data, viewsTable)
        vim.api.nvim_win_set_config(win, { title = "k8s_aliases - Aliases - " .. vim.tbl_count(self.data) })
      end
    end,
  })

  completion.with_completion(buf, self.data, function()
    -- We reassign the cache since it can be slow to load
    self.data = cache.cached_api_resources.values
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
  pfs = definition.getPFData(pfs, false)

  local self = ResourceBuilder:new("Port forward"):displayFloatFit("k8s_port_forwards", "Port forwards")
  self.data = definition.getPFRows(pfs)
  self.extmarks = {}

  self.prettyData, self.extmarks = tables.pretty_print(self.data, { "PID", "TYPE", "RESOURCE", "PORT" })
  self:addHints({ { key = "<Plug>(kubectl.kill)", desc = "Kill PF" } }, false, false, false):setContent()

  vim.keymap.set("n", "q", function()
    vim.api.nvim_set_option_value("modified", false, { buf = self.buf_nr })
    vim.cmd.fclose()
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

function M.Redraw()
  local win_id = vim.api.nvim_get_current_win()
  local win_config = vim.api.nvim_win_get_config(win_id)

  if win_config.relative == "" then
    local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
    local current_view, _ = M.view_and_definition(string.lower(vim.trim(buf_name)))
    pcall(current_view.Draw)
  end
end

--- Set a new URL and open the view
---@param opts table Options. Possible fields:
---   - <src> - Source view name where we are redirecting from
---   - <dest> - Destination view name where we are redirecting to
---   - <new_query_params> - New query parameters to set to the
---     destination view URL
---   - <name> - Resource name from src
---   - <ns> - Namespace name from src
function M.set_url_and_open_view(opts)
  opts = opts or {}
  local src = opts.src
  local dest = opts.dest
  local new_query_params = opts.new_query_params
  local name = opts.name
  local ns = opts.ns
  local encode = function(str)
    return vim.uri_encode(str, "rfc2396")
  end
  local res_view, res_definition = M.view_and_definition(dest)
  -- save url details
  local original_url = res_definition.url[1]
  local url_no_query_params, original_query_params = url.breakUrl(original_url, true, false)
  local all_query_params = {}
  for key, value in pairs(new_query_params) do
    table.insert(all_query_params, encode(key) .. "=" .. encode(value))
  end
  local str_query_params = "?" .. table.concat(all_query_params, "&")
  if original_query_params ~= "" then
    str_query_params = str_query_params .. "&" .. original_query_params
  end
  local new_url = url_no_query_params .. str_query_params

  local msg = {
    string.format("Loading %s for %s: %s", dest, src, name),
    "Refresh the view to see all " .. dest,
  }
  if ns then
    msg[1] = msg[1] .. " in namespace: " .. ns
  end
  vim.notify(table.concat(msg, "\n"))
  res_definition.url = { new_url }
  res_view.View()
  res_definition.url = { original_url }
end

function M.set_and_open_pod_selector(name, ns)
  -- get the selectors for the pods
  local resource = tables.find_resource(state.instance.data, name, ns)
  if not resource then
    return
  end
  local selector_t = (resource.spec.selector and resource.spec.selector.matchLabels or resource.spec.selector)
    or resource.metadata.labels
  local key_vals = table.concat(
    vim.tbl_map(function(key)
      return key .. "=" .. selector_t[key]
    end, vim.tbl_keys(selector_t)),
    ","
  )
  M.set_url_and_open_view({
    src = state.instance.resource,
    dest = "pods",
    new_query_params = {
      labelSelector = key_vals,
    },
    name = name,
    ns = ns,
  })
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
