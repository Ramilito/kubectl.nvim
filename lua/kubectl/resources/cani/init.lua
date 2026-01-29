local buffers = require("kubectl.actions.buffers")
local cache = require("kubectl.cache")
local commands = require("kubectl.actions.commands")
local hl = require("kubectl.actions.highlight")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")

local resource = "cani"

local M = {
  definition = {
    resource = resource,
    display_name = "CAN-I",
    ft = "k8s_" .. resource,
    headers = {
      "NAME",
      "APIGROUP",
      "GET",
      "LIST",
      "WATCH",
      "CREATE",
      "PATCH",
      "UPDATE",
      "DELETE",
      "DEL-LIST",
    },
  },
}

--- Build resource list from API resources cache
---@return table[] List of resources with name, group, and namespaced fields
local function build_resource_list()
  local api_resources = cache.cached_api_resources.values
  local list = {}
  for _, res in pairs(api_resources) do
    if res.gvk then
      table.insert(list, {
        name = res.plural or "",
        group = res.gvk.g or "",
        namespaced = res.namespaced or false,
      })
    end
  end
  return list
end

--- Format auth rule results into display rows
---@param results table[] Direct boolean results from Rust backend
---@return table[] Formatted rows with check symbols
local function format_results(results)
  local data = {}
  local check = function(v)
    return v and { value = "✓", symbol = hl.symbols.success } or { value = "✗", symbol = hl.symbols.error }
  end
  for _, rule in ipairs(results) do
    table.insert(data, {
      name = rule.name,
      apigroup = rule.apigroup,
      get = check(rule.get),
      list = check(rule.list),
      watch = check(rule.watch),
      create = check(rule.create),
      patch = check(rule.patch),
      update = check(rule.update),
      delete = check(rule.delete),
      ["del-list"] = check(rule.deletecollection),
    })
  end
  table.sort(data, function(a, b)
    if a.name == b.name then
      return a.apigroup < b.apigroup
    end
    return a.name < b.name
  end)
  return data
end

local function fetch_and_render(builder)
  local resource_list = build_resource_list()
  commands.run_async("get_auth_rules", {
    namespace = state.ns or "default",
    resources = resource_list,
  }, function(data)
    if not data then
      return
    end
    builder.data = data
    builder.decodeJson()

    if type(builder.data) == "table" and builder.data.error then
      vim.schedule(function()
        vim.notify("CAN-I: " .. builder.data.error, vim.log.levels.ERROR)
      end)
      return
    end

    vim.schedule(function()
      builder.processedData = format_results(builder.data)
      local windows = buffers.get_windows_by_name(M.definition.resource)
      for _, win_id in ipairs(windows) do
        builder.prettyPrint(win_id).addDivider(true)
        builder.displayContent(win_id)
      end
    end)
  end)
end

function M.View()
  local builder = manager.get_or_create(M.definition.resource)
  builder.definition = M.definition
  builder.view(M.definition)
  fetch_and_render(builder)
end

function M.Draw()
  local builder = manager.get(M.definition.resource)
  if not builder then
    return
  end
  fetch_and_render(builder)
end

function M.processRow(rows)
  return format_results(rows)
end

return M
