local ResourceBuilder = require("kubectl.resourcebuilder")
local commands = require("kubectl.actions.commands")

local M = { handles = nil, loading = false, timestamp = nil, cached_api_resources = { values = {}, shortNames = {} } }

local one_day_in_seconds = 24 * 60 * 60
local current_time = os.time()

M.LoadFallbackData = function(force)
  if force and not M.loading or (M.timestamp == nil or current_time - M.timestamp >= one_day_in_seconds) then
    M.cached_api_resources.values = {}
    M.cached_api_resources.shortNames = {}

    M.load_cache(M.cached_api_resources)
    M.timestamp = os.time()
  end
end

local function process_apis(resource, cached_api_resources)
  local name = string.lower(resource.crd_name)
  cached_api_resources.values[name] = {
    name = name,
    gvk = {
      g = resource.gvk.group,
      v = resource.gvk.version,
      k = resource.gvk.kind,
    },
    plural = resource.plural,
    crd_name = name,
    namespaced = resource.namespaced,
    api_version = resource.api_version,
  }

  require("kubectl.state").sortby[name] = { mark = {}, current_word = "", order = "asc" }
  -- cached_api_resources.shortNames[name] = resource

  -- if resource.singularName then
  --   cached_api_resources.shortNames[resource.singularName] = name
  -- end
  --
  -- if resource.shortNames then
  --   for _, shortName in ipairs(resource.shortNames) do
  --     cached_api_resources.shortNames[shortName] = name
  --   end
  -- end
end

function M.load_cache(cached_api_resources)
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
      if resource.gvk then
        process_apis(resource, cached_api_resources)
      end
    end

    M.loading = false
    vim.schedule(function()
      vim.cmd("doautocmd User KubectlCacheLoaded")
    end)
  end)
end

return M
