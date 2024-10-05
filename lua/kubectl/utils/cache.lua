local ResourceBuilder = require("kubectl.resourcebuilder")
local url = require("kubectl.utils.url")
local M = {}

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

      -- ResourceBuilder:new(resource_name):setCmd({ resource_url }, "curl"):fetchAsync(function(self)
      --   self:decodeJson()
      --   local data = {}
      --   if self.data.items then
      --     for _, row in ipairs(self.data.items) do
      --       if row.metadata.ownerReferences then
      --         table.insert(data, { owners = row.metadata.ownerReferences })
      --       end
      --     end
      --     cached_api_resources.values[resource_name].data = data
      --   end
      -- end)
    end
  end
end

local function processRow(rows, cached_api_resources)
  if rows and rows.items then
    for _, item in ipairs(rows.items) do
      item.metadata.managedFields = {}
      if not item.kind then
        break
      end

      local cache_key = nil
      for key, value in pairs(cached_api_resources.values) do
        if value.version == string.lower(rows.apiVersion) and value.kind == item.kind then
          cache_key = key
        end
      end

      if item.metadata.name and item.metadata.name ~= "" then
        local row = {
          name = item.metadata.name,
          ns = item.metadata.namespace,
          owners = item.metadata.ownerReferences,
        }

        if not cached_api_resources.values[cache_key].data then
          cached_api_resources.values[cache_key].data = {}
        end
        table.insert(cached_api_resources.values[cache_key].data, row)
      end
    end
  end
end

function M.load_cache(cached_api_resources)
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
      local all_urls = { "--parallel", "--parallel-immediate" }

      for _, resource in pairs(cached_api_resources.values) do
        if resource.url then
          table.insert(all_urls, url.replacePlaceholders(resource.url))
        end
      end

      ResourceBuilder:new("all"):setCmd(all_urls, "curl"):fetchAsync(function(builder)
        builder:splitData()
        builder:decodeJson()
        self.processedData = {}
        for _, values in ipairs(builder.data) do
          processRow(values, cached_api_resources)
        end
        -- Memory usage after creating the table
        collectgarbage("collect")
      end)
    end)
  end)
end
return M
