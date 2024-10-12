local ResourceBuilder = require("kubectl.resourcebuilder")
local config = require("kubectl.config")
local timeme = require("kubectl.utils.timeme")
local url = require("kubectl.utils.url")

local M = { handles = nil, loading = false, cached_api_resources = { values = {}, shortNames = {}, timestamp = nil } }

local one_day_in_seconds = 24 * 60 * 60
local current_time = os.time()

M.LoadFallbackData = function(force)
  if force and not M.loading or M.timestamp == nil or current_time - M.timestamp >= one_day_in_seconds then
    M.cached_api_resources.values = {}
    M.cached_api_resources.shortNames = {}

    M.load_cache(M.cached_api_resources)
    M.timestamp = os.time()
  end
end

local function process_apis(api_url, group_name, group_version, group_resources, cached_api_resources)
  if not group_resources.resources then
    return
  end
  for _, resource in ipairs(group_resources.resources) do
    -- Skip if resource name contains '/status'
    if not string.find(resource.name, "/status") then
      local resource_name = group_name ~= "" and (resource.name .. "." .. group_name) or resource.name
      local namespaced = resource.namespaced and "{{NAMESPACE}}" or ""
      local resource_url =
        string.format("{{BASE}}/%s/%s/%s%s?pretty=false", api_url, group_version, namespaced, resource.name)

      cached_api_resources.values[resource_name] = {
        name = resource.name,
        url = resource_url,
        namespaced = resource.namespaced,
        kind = resource.kind,
        version = group_version,
      }

      require("kubectl.state").sortby[resource_name] = { mark = {}, current_word = "", order = "asc" }
      cached_api_resources.shortNames[resource.name] = resource_name

      if resource.singularName then
        cached_api_resources.shortNames[resource.singularName] = resource_name
      end

      if resource.shortNames then
        for _, shortName in ipairs(resource.shortNames) do
          cached_api_resources.shortNames[shortName] = resource_name
        end
      end
    end
  end
end

local function processRow(rows, cached_api_resources)
  local relationships = require("kubectl.utils.relationships")
  if rows.code == "404" or not rows.items or #rows.items == 0 then
    return
  end

  local kind = rows.kind and rows.kind:gsub("List", "") or ""

  if rows and rows.items then
    for _, item in ipairs(rows.items) do
      item.metadata.managedFields = {}
      item.metadata.annotations = {}

      local cache_key = nil
      for key, value in pairs(cached_api_resources.values) do
        if value.version == string.lower(rows.apiVersion) and value.kind == kind then
          cache_key = key
        end
      end

      local row = {}

      -- Process relationships based on the relationships map
      local rel_def = relationships[kind]
      if rel_def and item[rel_def.owner_field] then
        local owners = {}
        local owner_info = item[rel_def.owner_field]

        table.insert(owners, {
          kind = owner_info[rel_def.fields.kind] or "",
          apiVersion = rows.apiVersion,
          name = owner_info[rel_def.fields.name] or "",
          uid = owner_info[rel_def.fields.uid] or "",
          ns = owner_info[rel_def.fields.namespace] or item.metadata.namespace,
        })
        row = {
          name = item.metadata.name,
          ns = item.metadata.namespace,
          owners = owners,
        }
      elseif item.metadata.name then
        row = {
          name = item.metadata.name,
          ns = item.metadata.namespace,
          owners = item.metadata.ownerReferences,
          labels = item.metadata.labels,
        }

        if row.owners then
          for _, owner in ipairs(row.owners) do
            owner.ns = item.metadata.namespace
          end
        end

        if item.spec and item.spec.selector then
          local label_selector = item.spec.selector.matchLabels or item.spec.selector
          if label_selector then
            row.selectors = label_selector
          end
        end
      end

      if cache_key then
        if not cached_api_resources.values[cache_key].data then
          cached_api_resources.values[cache_key].data = {}
        end
        table.insert(cached_api_resources.values[cache_key].data, row)
      end
    end
  end
end

function M.load_cache(cached_api_resources)
  M.loading = true
  timeme.start()
  local cmds = {
    { cmd = "kubectl", args = { "get", "--raw", "/api/v1" } },
    { cmd = "kubectl", args = { "get", "--raw", "/apis" } },
  }
  ResourceBuilder:new("api_resources"):fetchAllAsync(cmds, function(self)
    self:decodeJson()
    process_apis("api", "", "v1", self.data[1], cached_api_resources)

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
        process_apis("apis", "", self.data.groupVersion, self.data, cached_api_resources)
      end

      local all_urls = {}
      for _, resource in pairs(cached_api_resources.values) do
        if resource.url then
          table.insert(all_urls, { cmd = "curl", args = { resource.url } })
        end
      end
      for _, cmd in ipairs(all_urls) do
        if cmd.cmd == "curl" then
          cmd.args = url.build(cmd.args)
          cmd.args = url.addHeaders(cmd.args, cmd.contentType)
        else
        end
      end

      if M.handles or not config.options.lineage.enabled then
        return
      end

      collectgarbage("collect")

      -- Memory usage before creating the table
      local mem_before = collectgarbage("count")

      M.handles = ResourceBuilder:new("all"):fetchAllAsync(all_urls, function(builder)
        builder:splitData()
        builder:decodeJson()
        builder.processedData = {}

        for _, values in ipairs(builder.data) do
          processRow(values, cached_api_resources)
        end

        -- Memory usage after creating the table
        collectgarbage("collect")
        local mem_after = collectgarbage("count")
        local mem_diff_mb = (mem_after - mem_before) / 1024
        print("Memory used by the table (in MB):", mem_diff_mb)
        timeme.stop()
        M.handles = nil
        M.loading = false
      end)
    end)
  end)
end
return M
