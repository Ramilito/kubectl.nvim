local M = {
  client_id = nil,
}

---@param opts { capabilities: table, handlers: table }
---@return function
local function server(opts)
  local capabilities = opts.capabilities or {}
  local handlers = opts.handlers or {}

  return function(dispatchers)
    local closing = false
    local srv = {}
    local request_id = 0

    function srv.request(method, params, callback, notify_reply_callback)
      local handler = handlers[method]
      if handler then
        handler(method, params, callback)
      elseif method == "initialize" then
        callback(nil, { capabilities = capabilities })
      elseif method == "shutdown" then
        callback(nil, nil)
      end
      request_id = request_id + 1
      if notify_reply_callback then
        notify_reply_callback(request_id)
      end
      return true, request_id
    end

    function srv.notify(method, _params)
      if method == "exit" then
        dispatchers.on_exit(0, 15)
      end
    end

    function srv.is_closing()
      return closing
    end

    function srv.terminate()
      closing = true
    end

    return srv
  end
end

local function get_completion_items()
  local items = {}

  -- Lazy init: trigger cache initialization on first completion request
  require("kubectl").init_cache()

  local cache_ok, cache = pcall(require, "kubectl.cache")
  if cache_ok and cache.cached_api_resources and cache.cached_api_resources.values then
    for name, resource in pairs(cache.cached_api_resources.values) do
      if type(name) == "string" and type(resource) == "table" then
        local scope = resource.namespaced and "namespaced" or "cluster-scoped"
        local kind_name = (resource.gvk and resource.gvk.k) or name
        table.insert(items, {
          label = name,
          labelDetails = { description = kind_name },
          documentation = scope,
          kind_name = "Kind",
          kind_icon = "󱃾",
        })
        if resource.short_names then
          for _, short in ipairs(resource.short_names) do
            if type(short) == "string" then
              table.insert(items, {
                label = short,
                labelDetails = { description = kind_name },
                insertText = name,
                kind_name = "Kind",
                kind_icon = "󱃾",
              })
            end
          end
        end
      end
    end
  end

  local ns_ok, ns_view = pcall(require, "kubectl.views.namespace")
  if ns_ok and ns_view.namespaces then
    for _, ns in ipairs(ns_view.namespaces) do
      if type(ns) == "string" then
        table.insert(items, {
          label = ns,
          kind_name = "Namespace",
          kind_icon = "󱃾",
        })
      end
    end
  end

  local ctx_ok, ctx_view = pcall(require, "kubectl.resources.contexts")
  if ctx_ok and ctx_view.contexts then
    for _, context in ipairs(ctx_view.contexts) do
      if type(context) == "string" then
        table.insert(items, {
          label = context,
          kind_name = "Cluster",
          kind_icon = "󱃾",
        })
      end
    end
  end

  return items
end

local function reuse_client(client, config)
  return client.name == config.name
end

function M.start()
  local lsp_server = server({
    capabilities = {
      completionProvider = {
        triggerCharacters = { ":", "-" },
      },
    },
    handlers = {
      ["textDocument/completion"] = function(_method, _params, callback)
        local items = get_completion_items()
        callback(nil, { isIncomplete = false, items = items })
      end,
    },
  })

  local buf = vim.api.nvim_get_current_buf()

  local client_id = vim.lsp.start({
    name = "kubectl",
    cmd = lsp_server,
  }, {
    bufnr = buf,
    reuse_client = reuse_client,
  })

  if client_id then
    M.client_id = client_id
  end
end

function M.stop()
  if M.client_id then
    vim.lsp.stop_client(M.client_id)
    M.client_id = nil
  end
end

return M
