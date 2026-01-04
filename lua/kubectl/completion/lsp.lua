local M = {
  client_id = nil,
  sources = {},
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

---Register a completion source for a filetype
---@param filetype string
---@param source fun(): table[]
function M.register_source(filetype, source)
  M.sources[filetype] = source
end

local function get_completion_items(bufnr)
  local filetype = vim.bo[bufnr].filetype
  local source = M.sources[filetype]

  if source then
    return source()
  end

  return {}
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
        local buf = vim.api.nvim_get_current_buf()
        local items = get_completion_items(buf)
        -- Defer callback to allow text/window changes
        vim.schedule(function()
          callback(nil, { isIncomplete = false, items = items })
        end)
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
    -- Enable completion on prompt buffers (for blink.cmp)
    vim.b[buf].completion = true
  end
end

function M.stop()
  if M.client_id then
    vim.lsp.stop_client(M.client_id)
    M.client_id = nil
  end
end

return M
