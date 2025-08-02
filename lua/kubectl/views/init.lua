local buffers = require("kubectl.actions.buffers")
local find = require("kubectl.utils.find")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local mappings = require("kubectl.mappings")
local state = require("kubectl.state")
local tables = require("kubectl.utils.tables")
local url = require("kubectl.utils.url")

local M = {}

-- Generate hints and display them in a floating buffer
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
    { key = "<Plug>(kubectl.view_clusterrolebindings)", desc = "ClusterRoleBindings" },
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

  local global_keymaps = tables.get_plug_mappings(globals)

  local title = "Buffer mappings: "
  tables.add_mark(marks, #hints, 0, #title, hl.symbols.success)
  table.insert(hints, title .. "\n")
  table.insert(hints, "\n")

  local buffer_keymaps = tables.get_plug_mappings(headers)
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

  local buf = buffers.floating_dynamic_buffer("k8s_hints", "Hints | global keys", nil)

  local content = vim.split(table.concat(hints, ""), "\n")
  buffers.set_content(buf, { content = content, marks = marks })
end

function M.Picker()
  vim.cmd("fclose!")

  local self = manager.get_or_create("Picker")
  local data = {}

  for id, value in pairs(state.buffers) do
    local parts = vim.split(value.args[2], "|")
    local kind = vim.trim(parts[1])
    local resource = vim.trim(parts[2] or "")
    local namespace = vim.trim(parts[3] or "")
    local type = value.args[1]:gsub("k8s_", "")
    local symbol = hl.symbols.success

    if type == "exec" then
      symbol = hl.symbols.experimental
    elseif type == "desc" then
      symbol = hl.symbols.debug
    elseif type == "yaml" then
      symbol = hl.symbols.header
    end

    table.insert(data, {
      id = { value = id, symbol = hl.symbols.gray },
      kind = { value = kind, symbol = symbol },
      type = { value = type, symbol = symbol },
      resource = { value = resource, symbol = symbol },
      namespace = { value = namespace, symbol = hl.symbols.gray },
    })
  end

  local function sort_by_id_value(tbl)
    table.sort(tbl, function(a, b)
      return a.id.value > b.id.value
    end)
  end
  sort_by_id_value(data)
  self.data = data
  self.processedData = self.data

  self.addHints({
    { key = "<Plug>(kubectl.delete)", desc = "delete" },
    { key = "<Plug>(kubectl.select)", desc = "select" },
  }, false, false, false)

  self.buf_nr, self.win_nr = buffers.floating_dynamic_buffer("k8s_picker", "Picker", nil, nil)
  self.prettyData, self.extmarks = tables.pretty_print(
    self.processedData,
    { "ID", "KIND", "TYPE", "RESOURCE", "NAMESPACE" },
    { current_word = "ID", order = "desc" }
  )
  vim.api.nvim_buf_set_keymap(self.buf_nr, "n", "<Plug>(kubectl.delete)", "", {
    noremap = true,
    callback = function()
      local selection = tables.getCurrentSelection(1)
      local bufnr = tonumber(selection)

      if bufnr then
        state.buffers[bufnr] = nil
        vim.api.nvim_buf_delete(bufnr, { force = true })
        local row = vim.api.nvim_win_get_cursor(0)[1] - 1
        vim.api.nvim_buf_set_lines(0, row, row + 1, false, {})
      end
    end,
  })

  vim.api.nvim_buf_set_keymap(self.buf_nr, "n", "<Plug>(kubectl.select)", "", {
    noremap = true,
    callback = function()
      local bufnr = tables.getCurrentSelection(1)
      local buffer = state.buffers[tonumber(bufnr)]

      if buffer then
        vim.cmd("fclose!")
        vim.schedule(function()
          if not vim.api.nvim_tabpage_is_valid(buffer.tab_id) then
            vim.cmd("tabnew")
            buffer.tab_id = vim.api.nvim_get_current_tabpage()
          end
          vim.schedule(function()
            vim.api.nvim_set_current_tabpage(buffer.tab_id)
            buffer.open(unpack(buffer.args))
          end)
        end)
      end
    end,
  })
  self.displayContent(self.win_nr)
  vim.schedule(function()
    mappings.map_if_plug_not_set("n", "gD", "<Plug>(kubectl.delete)")
  end)
end

--- PortForwards function retrieves port forwards and displays them in a float window.
-- @function PortForwards
-- @return nil
function M.PortForwards()
  local resource = "port_forwards"
  local pf_definition = require("kubectl.resources.port_forwards.definition")
  local self = manager.get_or_create(resource)
  self.buf_nr, self.win_nr = buffers.floating_dynamic_buffer("k8s_" .. resource, "Port forwards", nil, nil)
  self.data = pf_definition.getPFRows()
  self.extmarks = {}
  self.prettyData, self.extmarks = tables.pretty_print(self.data, { "ID", "TYPE", "NAME", "NS", "PORT" })
  self
    .addHints({ { key = "<Plug>(kubectl.delete)", desc = "Delete PF" } }, false, false, false)
    .displayContent(self.win_nr)

  vim.keymap.set("n", "q", function()
    vim.api.nvim_set_option_value("modified", false, { buf = self.buf_nr })
    vim.cmd.fclose()
    vim.api.nvim_input("<Plug>(kubectl.refresh)")
  end, { buffer = self.buf_nr, silent = true })
end

--- Execute a user command and handle the response
---@param args table
function M.UserCmd(args)
  local builder = manager.get_or_create("k8s_usercmd")
  builder.setCmd(args, "kubectl").fetchAsync(function(self)
    if self.data == "" then
      return
    end
    self.splitData()

    vim.schedule(function()
      self.buf_nr = 0
      self.displayContentRaw()
    end)
  end)
end

function M.Redraw()
  local win_id = vim.api.nvim_get_current_win()
  local win_config = vim.api.nvim_win_get_config(win_id)

  if win_config.relative == "" then
    local _, buf_name = pcall(vim.api.nvim_buf_get_var, 0, "buf_name")
    local current_view, _ = M.resource_and_definition(string.lower(vim.trim(buf_name)))
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
  local res_view, res_definition = M.resource_and_definition(dest)
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
  local buf_name = vim.api.nvim_buf_get_var(0, "buf_name")
  local resource = tables.find_resource(state.instance[buf_name].data, name, ns)
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

function M.resource_and_definition(view_name)
  local view_ok, view = pcall(require, "kubectl.resources." .. view_name)
  if not view_ok then
    view = require("kubectl.resources.fallback")
  end
  return view, view.definition
end

function M.resource_or_fallback(view_name)
  local supported_view = nil
  local viewsTable = require("kubectl.utils.viewsTable")
  for k, v in pairs(viewsTable) do
    local found_in_table = find.is_in_table(v, view_name, true)
    if found_in_table or k == view_name then
      supported_view = k
    end
  end
  local view_to_find = supported_view or view_name
  local ok, view = pcall(require, "kubectl.resources." .. view_to_find)
  if ok then
    vim.schedule(function()
      pcall(view.View)
    end)
  else
    vim.schedule(function()
      local fallback = require("kubectl.resources.fallback")
      fallback.View(nil, view_name)
    end)
  end
end

return M
