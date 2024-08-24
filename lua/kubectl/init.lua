local commands = require("kubectl.actions.commands")
local informer = require("kubectl.actions.informer")
local state = require("kubectl.state")

local M = {
  is_open = false,
}

--- Open the kubectl view
function M.open()
  local hl = require("kubectl.actions.highlight")
  local kube = require("kubectl.actions.kube")

  hl.setup()
  kube.start_kubectl_proxy(function()
    state.setup()
  end)
end

function M.close()
  -- Only stop proxy and save session if not a floating buffer
  local win_config = vim.api.nvim_win_get_config(0)

  if win_config.relative == "" then
    local kube = require("kubectl.actions.kube")
    state.set_session()
    kube.stop_kubectl_proxy()()
    informer.stop()
  end
  vim.api.nvim_buf_delete(0, { force = true })
end

function M.toggle()
  if M.is_open then
    M.close()
    M.is_open = false
  else
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

  local group = vim.api.nvim_create_augroup("Kubectl", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "k8s_*",
    callback = function()
      mappings.register()
    end,
  })

  vim.api.nvim_create_user_command("Kubectl", function(opts)
    local view = require("kubectl.views")
    local action = opts.fargs[1]
    local ok, x_view
    if action == "get" then
      if #opts.fargs == 2 then
        local resource_type = opts.fargs[2]
        local viewsTable = require("kubectl.utils.viewsTable")
        for key, item in pairs(viewsTable) do
          if vim.tbl_contains(item, resource_type) then
            ok, x_view = pcall(require, "kubectl.views." .. key)
            if ok then
              break
            end
          end
        end
        if ok then
          pcall(x_view.View)
        else
          view = require("kubectl.views.fallback")
          view.View(nil, opts.fargs[2])
        end
      else
        view.UserCmd(opts.fargs)
      end
    elseif action == "diff" then
      completion.diff(opts.fargs[2])
    elseif action == "apply" then
      completion.apply()
    else
      view.UserCmd(opts.fargs)
    end
  end, {
    nargs = "*",
    complete = completion.user_command_completion,
  })

  vim.api.nvim_create_user_command("Kubens", function(opts)
    completion.change_namespace(opts.fargs[1])
  end, {
    nargs = "*",
    complete = completion.list_namespace,
  })

  vim.api.nvim_create_user_command("Kubectx", function(opts)
    completion.change_context(opts.fargs[1])
  end, {
    nargs = "*",
    complete = completion.list_contexts,
  })
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    -- TODO: do we need to save session here or is it enough to do it when M.close is called?
    state.set_session()
  end,
})

return M
