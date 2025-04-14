local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")
local config = require("kubectl.config")
local timeme = require("kubectl.utils.timeme")
local url = require("kubectl.utils.url")

local M = { handles = nil, loading = false, timestamp = nil, cached_api_resources = { values = {}, shortNames = {} } }

local one_day_in_seconds = 24 * 60 * 60
local current_time = os.time()

M.LoadFallbackData = function(force, callback)
  if force and not M.loading or (M.timestamp == nil or current_time - M.timestamp >= one_day_in_seconds) then
    M.cached_api_resources.values = {}
    M.cached_api_resources.shortNames = {}

    M.load_cache(M.cached_api_resources, callback)
    M.timestamp = os.time()
  end
end

local function process_apis(resource, cached_api_resources)
  local version = resource.gvk.version:match("([^/]+)$")
  local name = string.lower(resource.gvk.kind)
  cached_api_resources.values[name] = {
    name = name,
    gvk = {
      g = resource.gvk.group,
      v = version,
      k = string.lower(resource.gvk.kind),
    },
    plural = resource.plural,
    crd_name = resource.crd_name,
    namespaced = resource.namespaced,
  }

  require("kubectl.state").sortby[name] = { mark = {}, current_word = "", order = "asc" }
  cached_api_resources.shortNames[name] = resource

  if resource.singularName then
    cached_api_resources.shortNames[resource.singularName] = name
  end

  if resource.shortNames then
    for _, shortName in ipairs(resource.shortNames) do
      cached_api_resources.shortNames[shortName] = name
    end
  end
end

local function processRow(rows, cached_api_resources, relationships)
  if rows.code == "404" or not rows.items or #rows.items == 0 then
    return
  end

  local kind = rows.kind and rows.kind:gsub("List", "") or ""

  if rows and rows.items then
    for _, item in ipairs(rows.items) do
      item.metadata.managedFields = {}

      local cache_key = nil
      for key, value in pairs(cached_api_resources.values) do
        if value.version == string.lower(rows.apiVersion) and value.kind == kind then
          cache_key = key
        end
      end

      local row

      if item.metadata.name then
        local owners = {}
        local relations = {}

        for _, relation in ipairs(relationships.getRelationship(kind, item, rows)) do
          if relation.relationship_type == "owner" then
            table.insert(owners, relation)
          elseif relation.relationship_type == "dependency" then
            table.insert(relations, relation)
          end
        end

        -- Add ownerReferences
        if item.metadata.ownerReferences then
          for _, owner in ipairs(item.metadata.ownerReferences) do
            table.insert(owners, {
              kind = owner.kind,
              apiVersion = owner.apiVersion,
              name = owner.name,
              uid = owner.uid,
              ns = owner.namespace or item.metadata.namespace,
            })
          end
        end

        -- Build the row data
        row = {
          name = item.metadata.name,
          ns = item.metadata.namespace,
          apiVersion = rows.apiVersion,
          labels = item.metadata.labels,
          owners = owners,
          relations = relations,
        }

        -- Add selectors if available
        if item.spec and item.spec.selector then
          local label_selector = item.spec.selector.matchLabels or item.spec.selector
          if label_selector then
            row.selectors = label_selector
          end
        end

        -- Add the row to the cache if cache_key is available
        if cache_key then
          if not cached_api_resources.values[cache_key].data then
            cached_api_resources.values[cache_key].data = {}
          end
          table.insert(cached_api_resources.values[cache_key].data, row)
        end
      end
    end
  end
end

function M.load_cache(cached_api_resources, callback)
  M.loading = true
  local builder = ResourceBuilder:new("api_resources")
  commands.run_async("get_api_resources_async", {}, function(data, err)
    if err then
      vim.print("error: failed loading api_resources", err)
      return
    end
    builder.data = data
    builder:decodeJson()

    for _, resource in ipairs(builder.data) do
      process_apis(resource, cached_api_resources)
    end

    timeme.stop()
    M.loading = false
    vim.schedule(function()
      vim.cmd("doautocmd User KubectlCacheLoaded")
    end)
  end)

  --     local all_urls = {}
  --     for _, resource in pairs(cached_api_resources.values) do
  --       if resource.url then
  --         table.insert(all_urls, { cmd = "get_raw_async", args = { resource.url, nil, false } })
  --       end
  --     end
  --     for _, cmd in ipairs(all_urls) do
  --       cmd.args = url.build(cmd.args)
  --     end
  --
  --     M.loading = false
  --     vim.schedule(function()
  --       vim.cmd("doautocmd User KubectlCacheLoaded")
  --     end)
  --
  --     if M.handles or not config.options.lineage.enabled then
  --       return
  --     end
  --
  --     collectgarbage("collect")
  --
  --     -- Memory usage before creating the table
  --     local mem_before = collectgarbage("count")
  --
  --     local relationships = require("kubectl.utils.relationships")
  --     M.handles = ResourceBuilder:new("all"):fetchAllAsync(all_urls, function(builder)
  --       builder:splitData()
  --       builder:decodeJson()
  --       builder.processedData = {}
  --
  --       for _, values in ipairs(builder.data) do
  --         processRow(values, cached_api_resources, relationships)
  --       end
  --
  --       -- Memory usage after creating the table
  --       collectgarbage("collect")
  --       local mem_after = collectgarbage("count")
  --       local mem_diff_mb = (mem_after - mem_before) / 1024
  --       print("Memory used by the table (in MB):", mem_diff_mb)
  --       timeme.stop()
  --       M.handles = nil
  --       if callback then
  --         callback()
  --       end
  --     end)
  --   end)
  -- end)
end

return M
