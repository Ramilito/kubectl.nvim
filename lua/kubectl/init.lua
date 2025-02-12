local cache = require("kubectl.cache")
local ctx_view = require("kubectl.views.contexts")
local informer = require("kubectl.actions.informer")
local ns_view = require("kubectl.views.namespace")
local state = require("kubectl.state")
local view = require("kubectl.views")

local M = {
  is_open = false,
}

--- Open the kubectl view
function M.open()
  local hl = require("kubectl.actions.highlight")
  local kube = require("kubectl.actions.kube")

  hl.setup()
  kube.start_kubectl_proxy(function()
    cache.LoadFallbackData()
    state.setup()
  end)
end

function M.close()
  -- Only stop proxy and save session if not a floating buffer
  local win_config = vim.api.nvim_win_get_config(0)

  if win_config.relative == "" then
    local kube = require("kubectl.actions.kube")
    state.set_session()
    state.stop_livez()
    kube.stop_kubectl_proxy()()
    informer.stop()
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
  config.setup(options)
  state.setNS(config.options.namespace)
  mappings.setup()

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

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    -- TODO: do we need to save session here or is it enough to do it when M.close is called?
    state.set_session()
  end,
})

return M
