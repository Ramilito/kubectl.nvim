local client = require("kubectl.client")
local commands = require("kubectl.actions.commands")
local state = require("kubectl.state")

local M = {}

--- Process rows from kubectl get output into the cached_api_resources structure.
--- @param rows table|string|nil Raw resource rows
--- @param cached_api_resources table The API resources cache
function M.processRow(rows, cached_api_resources)
  if not rows or type(rows) ~= "table" then
    return
  end
  for _, item in ipairs(rows) do
    if item.kind and item.metadata and item.metadata.name then
      item.metadata.managedFields = nil

      local cache_key = nil
      for _, value in pairs(cached_api_resources.values) do
        if value.api_version and item.apiVersion then
          if string.lower(value.api_version) == string.lower(item.apiVersion) and value.gvk.k == item.kind then
            cache_key = value.crd_name
          end
        end
      end

      if cache_key then
        if not cached_api_resources.values[cache_key].data then
          cached_api_resources.values[cache_key].data = {}
        end
        table.insert(cached_api_resources.values[cache_key].data, item)
      end
    end
  end
end

--- Collect all resources from cached data into a flat list.
--- @param data_sample table The cached_api_resources.values table
--- @return table resources Flat list of resources
function M.collect_all_resources(data_sample)
  local resources = {}
  for kind_key, resource_group in pairs(data_sample) do
    if resource_group.data then
      for _, resource in ipairs(resource_group.data) do
        -- Guard against mlua nil/vim.NIL — only include resources with a real
        -- metadata.name string so downstream JSON encoding never drops the field.
        local meta = resource.metadata
        if meta and type(meta.name) == "string" then
          resource.kind = (resource.kind and resource.kind) or (resource_group.gvk.k or kind_key)
          resource.namespaced = resource_group.namespaced
          table.insert(resources, resource)
        end
      end
    end
  end
  return resources
end

--- Build lineage graph asynchronously via commands.run_async.
--- @param data table The collected resources
--- @param callback function Called with (graph) when done
function M.build_graph_async(data, callback)
  local context = state.getContext()
  local root_name = context.clusters[1].name

  local args = { resources = data, root_name = root_name }
  commands.run_async("build_lineage_graph_worker", args, function(result_json, err)
    if err then
      vim.schedule(function()
        vim.notify("Error building lineage graph: " .. tostring(err), vim.log.levels.ERROR)
        callback(nil)
      end)
      return
    end

    local ok, result = pcall(vim.json.decode, result_json)
    if not ok then
      vim.schedule(function()
        vim.notify("Error decoding lineage graph: " .. tostring(result), vim.log.levels.ERROR)
        callback(nil)
      end)
      return
    end

    local graph = {
      nodes = result.nodes,
      root_key = result.root_key,
      tree_id = result.tree_id,
      get_related_nodes = function(node_key)
        local related_json = client.get_lineage_related_nodes(result.tree_id, node_key)
        return vim.json.decode(related_json)
      end,
    }

    vim.schedule(function()
      callback(graph)
    end)
  end)
end

return M
