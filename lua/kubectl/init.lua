local splash = require("kubectl.splash")

local M = {
  is_open = false,
  did_setup = false,
  client_state = "pending", -- "pending", "initializing", "ready", "failed"
  client_callbacks = {},
}

--- Initialize the kubectl client (shared by UI and completion)
--- @param callback fun(ok: boolean)
function M.init_client(callback)
  if M.client_state == "ready" then
    callback(true)
    return
  end

  if M.client_state == "failed" then
    callback(false)
    return
  end

  table.insert(M.client_callbacks, callback)

  if M.client_state == "initializing" then
    return -- Already initializing, callback queued
  end

  M.client_state = "initializing"
  local client = require("kubectl.client")
  client.set_implementation(function(ok)
    M.client_state = ok and "ready" or "failed"
    for _, cb in ipairs(M.client_callbacks) do
      cb(ok)
    end
    M.client_callbacks = {}
  end)
end

--- Initialize cache for completions (no UI side effects)
function M.init_cache()
  local cache = require("kubectl.cache")

  if cache.cached_api_resources and not vim.tbl_isempty(cache.cached_api_resources.values or {}) then
    return
  end

  M.init_client(function(ok)
    if ok then
      local state = require("kubectl.state")
      local commands = require("kubectl.actions.commands")

      -- Load context first (required by cache)
      commands.run_async("get_minified_config_async", {}, function(data)
        local result = vim.json.decode(data or "{}")
        if result then
          state.context = result
        end
        cache.LoadFallbackData()
      end)
    end
  end)
end

--- Initialize UI components (called after client is ready)
local function init_ui()
  local config = require("kubectl.config")
  local header = require("kubectl.views.header")
  local state = require("kubectl.state")
  local statusline = require("kubectl.views.statusline")

  vim.schedule(function()
    state.setup()

    if config.options.headers.enabled then
      header.View()
    end
    if config.options.statusline.enabled then
      statusline.View()
    end

    local queue = require("kubectl.event_queue")
    queue.start(500)
    splash.done("Context: " .. (state.context["current-context"] or ""))
  end)
end

--- Open the kubectl view
function M.open()
  local hl = require("kubectl.actions.highlight")
  hl.setup()
  splash.show()
  vim.schedule(function()
    M.init()
  end)
end

function M.init()
  splash.status("Client module loaded ✔ ")
  M.init_client(function(ok)
    if ok then
      splash.status("Client ininitalized ✔ ")
      init_ui()
    else
      splash.fail("Failed to load context")
    end
  end)
end

function M.close()
  local win_config = vim.api.nvim_win_get_config(0)
  local state = require("kubectl.state")
  local statusline = require("kubectl.views.statusline")
  local header = require("kubectl.views.header")

  if win_config.relative == "" then
    state.stop_livez()
  end
  statusline.Close()
  header.Close()
  splash.hide()
  local queue = require("kubectl.event_queue")
  queue.stop()

  vim.api.nvim_buf_delete(0, { force = true })
end

--- @param opts { tab: boolean }: Options for toggle function
function M.toggle(opts)
  opts = opts or {}
  if M.is_open then
    M.close()
    M.is_open = false
  else
    if opts.tab then
      vim.cmd("tabnew")
    end
    M.open()
    M.is_open = true
  end
end

--- Setup kubectl with options
--- @param options KubectlOptions The configuration options for kubectl
function M.setup(options)
  local kubectl = require("kubectl.kubectl")
  local mappings = require("kubectl.mappings")
  local loop = require("kubectl.utils.loop")
  local config = require("kubectl.config")
  local state = require("kubectl.state")
  local ns_view = require("kubectl.views.namespace")

  M.download_if_available(function(_)
    config.setup(options)
    state.setNS(config.options.namespace)

    local group = vim.api.nvim_create_augroup("Kubectl", { clear = true })
    vim.api.nvim_create_autocmd("FileType", {
      group = group,
      pattern = "k8s_*",
      callback = function(ev)
        mappings.setup(ev)

        local win_config = vim.api.nvim_win_get_config(0)

        if win_config.relative == "" then
          if not loop.is_running(ev.buf) then
            local resource_name = ev.match:sub(#"k8s_" + 1)
            local current_view = require("kubectl.views").resource_and_definition(resource_name)
            loop.start_loop(current_view.Draw, { buf = ev.buf })
            vim.opt_local.foldmethod = "manual"
          end
        end
      end,
    })

    -- LSP completion for specific filetypes
    vim.api.nvim_create_autocmd("FileType", {
      group = group,
      pattern = { "k8s_aliases" },
      callback = function()
        require("kubectl.completion.lsp").start()
      end,
    })
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = group,
      desc = "Best-effort, non-blocking shutdown of background tasks/clients",
      callback = function()
        pcall(function()
          require("kubectl.client").shutdown_async()
        end)
      end,
    })
    M.did_setup = true
  end)

  vim.api.nvim_create_user_command("Kubectl", function(opts)
    kubectl.execute(opts.fargs)
  end, {
    nargs = "*",
    complete = kubectl.complete,
  })

  vim.api.nvim_create_user_command("K", function(opts)
    kubectl.execute(opts.fargs)
  end, {
    nargs = "*",
    complete = kubectl.complete,
  })

  vim.api.nvim_create_user_command("Kubens", function(opts)
    if #opts.fargs == 0 then
      ns_view.View()
    else
      ns_view.changeNamespace(opts.fargs[1])
    end
  end, {
    nargs = "*",
    complete = ns_view.listNamespaces,
  })

  local ctx_view = require("kubectl.resources.contexts")
  vim.api.nvim_create_user_command("Kubectx", function(opts)
    if #opts.fargs == 0 then
      ctx_view.View()
    else
      ctx_view.change_context(opts.fargs[1])
    end
  end, {
    nargs = "*",
    complete = ctx_view.list_contexts,
  })
end

function M.download_if_available(callback)
  local success, downloader = pcall(require, "blink.download")
  if not success then
    return callback()
  end

  -- See https://github.com/Saghen/blink.download for more info
  local root_dir = vim.fn.resolve(debug.getinfo(1).source:match("@?(.*/)") .. "../../")

  downloader.ensure_downloaded({
    -- omit this property to disable downloading
    -- i.e. https://github.com/Saghen/blink.delimiters/releases/download/v0.1.0/x86_64-unknown-linux-gnu.so
    download_url = function(version, system_triple, extension)
      return "https://github.com/ramilito/kubectl.nvim/releases/download/"
        .. version
        .. "/"
        .. system_triple
        .. extension
    end,
    on_download = function()
      vim.notify(
        "[Kubectl.nvim] Downloading binary; restart Neovim to apply.",
        vim.log.levels.INFO,
        { title = "kubectl.nvim" }
      )
    end,

    root_dir = root_dir,
    output_dir = "/target/release",
    binary_name = "kubectl_client", -- excluding `lib` prefix
  }, callback)
end

return M
