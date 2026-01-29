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

--- Check if a rule matches a given resource name and api group
---@param rule table The auth rule from Rust
---@param res_name string The resource plural name
---@param api_group string The API group
---@return boolean
local function rule_matches(rule, res_name, api_group)
  local name_match = rule.name == "*" or rule.name == res_name
  local group_match = rule.apigroup == "*" or rule.apigroup == api_group
  return name_match and group_match
end

local verbs = { "get", "list", "watch", "create", "patch", "update", "delete", "deletecollection" }

--- Resolve permissions for all API resources against auth rules
---@param rules table[] The raw auth rules from SelfSubjectRulesReview
---@return table[] Resolved rows with per-resource permissions
local function resolve_permissions(rules)
  local api_resources = cache.cached_api_resources.values
  local data = {}

  for _, res in pairs(api_resources) do
    if res.gvk then
      local api_group = res.gvk.g or ""
      local res_name = res.plural or ""

      local perms = {}
      for _, v in ipairs(verbs) do
        perms[v] = false
      end

      for _, rule in ipairs(rules) do
        if rule_matches(rule, res_name, api_group) then
          for _, v in ipairs(verbs) do
            if rule[v] then
              perms[v] = true
            end
          end
        end
      end

      local check = function(v)
        return perms[v] and { value = "✓", symbol = hl.symbols.success } or ""
      end

      table.insert(data, {
        name = res_name,
        apigroup = api_group,
        get = check("get"),
        list = check("list"),
        watch = check("watch"),
        create = check("create"),
        patch = check("patch"),
        update = check("update"),
        delete = check("delete"),
        ["del-list"] = check("deletecollection"),
      })
    end
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
  commands.run_async("get_auth_rules", { namespace = state.ns or "default" }, function(data)
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
      builder.processedData = resolve_permissions(builder.data)
      builder.prettyPrint().displayContent(builder.win_nr)
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
  return resolve_permissions(rows)
end

return M
