local cache = require("kubectl.cache")
local config = require("kubectl.config")
local ctx_view = require("kubectl.views.contexts")
local ns_view = require("kubectl.views.namespace")
local state = require("kubectl.state")
local view = require("kubectl.views")

local M = {
  is_open = false,
}

--- Open the kubectl view
function M.open()
  local hl = require("kubectl.actions.highlight")

  local client = require("kubectl.client")
  client.set_implementation()

  hl.setup()

  if config.options.headers.enabled then
    view.Header()
  end
  state.setup()
  cache.LoadFallbackData()
end

function M.close()
  -- Only stop proxy and save session if not a floating buffer
  local win_config = vim.api.nvim_win_get_config(0)

  if win_config.relative == "" then
    state.stop_livez()
  end
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
  local completion = require("kubectl.completion")
  local mappings = require("kubectl.mappings")
  local config = require("kubectl.config")
  local loop = require("kubectl.utils.loop")
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
          state.set_session(ev.file)
          if not loop.is_running(ev.buf) then
            local current_view = require("kubectl.views").view_and_definition(ev.file)
            loop.start_loop(current_view.Draw, { buf = ev.buf })
            vim.opt_local.foldmethod = "manual"
          end
        end
      end,
    })
  end)

  vim.api.nvim_create_user_command("Kubectl", function(opts)
    local action = opts.fargs[1]
    if action == "get" then
      if #opts.fargs == 2 then
        local resource_type = opts.fargs[2]
        view.view_or_fallback(resource_type)
      else
        view.UserCmd(opts.fargs)
      end
    elseif action == "diff" then
      completion.diff(opts.fargs[2])
    elseif action == "apply" then
      completion.apply()
    elseif action == "top" then
      local top_view
      if #opts.fargs == 2 then
        local top_type = opts.fargs[2]
        top_view = require("kubectl.views.top-" .. top_type)
      else
        top_view = require("kubectl.views.top_pods")
      end
      top_view.View()
    elseif action == "api-resources" then
      require("kubectl.views.api-resources").View()
    else
      view.UserCmd(opts.fargs)
    end
  end, {
    nargs = "*",
    complete = completion.user_command_completion,
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
      vim.notify("[Kubectl.nvim] Downloading prebuilt binary...", vim.log.levels.INFO, { title = "kubectl.nvim" })
    end,

    root_dir = root_dir,
    output_dir = "/target/release",
    binary_name = "kubectl_client", -- excluding `lib` prefix
  }, callback)
end

return M
