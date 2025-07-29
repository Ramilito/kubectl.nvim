local commands = require("kubectl.actions.commands")
local manager = require("kubectl.resource_manager")
local state = require("kubectl.state")

local M = { handles = nil, loading = false, timestamp = nil, cached_api_resources = { values = {}, shortNames = {} } }

local ttl = require("kubectl.config").options.api_resources_cache_ttl
local data = vim.fn.stdpath("data") .. "/kubectl"

M.LoadFallbackData = function(force)
  if M.loading then
    return
  end

  local ctx = state.context["current-context"]
  local path = string.format("%s/%s.json", data .. "/api_resources", ctx)

  local stat = vim.uv.fs_stat(path)
  if stat then
    local cached = commands.read_file("api_resources/" .. ctx .. ".json")
    if cached then
      M.cached_api_resources = cached
    end
  end

  local is_stale = not stat or (os.time() - stat.mtime.sec >= ttl)

  if force or is_stale then
    M.load_cache(M.cached_api_resources)
    M.timestamp = os.time()
    return
  end
end

local function process_apis(resource, cached_api_resources)
  local name = string.lower(resource.crd_name)
  local value = {
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

  cached_api_resources.values[name] = value

  if resource.short_names then
    for _, shortName in ipairs(resource.short_names) do
      cached_api_resources.shortNames[shortName] = value
    end
  end
  state.sortby[name] = { mark = {}, current_word = "", order = "asc" }
end

function M.load_cache(cached_api_resources)
  M.loading = true

  local builder = manager.get_or_create("api_resources")
  commands.run_async("get_api_resources_async", {}, function(result, err)
    if err then
      vim.print("error: failed loading api_resources", err)
      return
    end
    builder.data = result
    builder.decodeJson()

    for _, resource in ipairs(builder.data) do
      if resource.gvk then
        process_apis(resource, cached_api_resources)
      end
    end

    M.loading = false
    M.timestamp = os.time()
    vim.schedule(function()
      vim.cmd("doautocmd User KubectlCacheLoaded")
      local ctx = state.context["current-context"]
      local ok, msg = commands.save_file("api_resources/" .. ctx .. ".json", cached_api_resources)
      if not ok then
        vim.notify("Failed to save api_resources: " .. msg, vim.log.levels.ERROR)
      end
    end)
  end)
end

return M
