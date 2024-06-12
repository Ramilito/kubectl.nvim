local api = vim.api
local Input = require("nui.input")
local commands = require("kubectl.actions.commands")
local deployment_view = require("kubectl.views.deployments")
local hl = require("kubectl.actions.highlight")
local loop = require("kubectl.utils.loop")
local pod_view = require("kubectl.views.pods")
local root_view = require("kubectl.views.root")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views")
local event = require("nui.utils.autocmd").event

api.nvim_buf_set_keymap(0, "n", "g?", "", {
  noremap = true,
  silent = true,
  callback = function()
    view.Hints({
      "      Hint: " .. hl.symbols.pending .. "d " .. hl.symbols.clear .. "desc",
    })
  end,
})

api.nvim_buf_set_keymap(0, "n", "<C-i>", "", {
  noremap = true,
  silent = true,
  desc = "Set image",
  callback = function()
    -- kubectl set image deployment/mydeployment my-container=new-image

    -- get pod for deployment -> kubectl get pods -n stable -l=app=ps-service-windcave
    local namespace, deployment_name = tables.getCurrentSelection(unpack({ 1, 2 }))

    if deployment_name and namespace then
      print("in now")

      local input = Input({
        position = "50%",
        size = {
          width = 20,
        },
        border = {
          style = "single",
          text = {
            top = "[Image name]",
            top_align = "center",
          },
        },
        win_options = {
          winhighlight = "Normal:Normal,FloatBorder:Normal",
        },
      }, {
        prompt = "> ",
        default_value = "",
        on_close = function()
          print("Closed!")
        end,
        on_submit = function(value)
          -- print("Set image to: " .. value)
          -- print("deployment name " .. deployment_name)
          -- print("namespace " .. namespace)
          local output =
            vim.fn.system({ "kubectl", "set", "image", "-n", namespace, "deployment/", deployment_name, "=", value })

          print("output ", output)
          -- commands.execute_shell_command(
          --   "kubectl",
          --   "set image" .. " deployment/" .. deployment_name .. deployment_name .. "=" .. value .. " -n" .. namespace
          -- )
        end,
      })

      -- unmount input by pressing `<Esc>` in normal mode
      input:map("n", "<Esc>", function()
        input:unmount()
      end, { noremap = true })

      -- mount/open the component
      input:mount()

      -- unmount component when cursor leaves buffer
      input:on(event.BufLeave, function()
        input:unmount()
      end)
    else
      vim.api.nvim_err_writeln("Failed to describe pod name or namespace.")
    end
  end,
})

api.nvim_buf_set_keymap(0, "n", "d", "", {
  noremap = true,
  silent = true,
  desc = "Desc",
  callback = function()
    local namespace, deployment_name = tables.getCurrentSelection(unpack({ 1, 2 }))
    if deployment_name and namespace then
      deployment_view.DeploymentDesc(deployment_name, namespace)
    else
      vim.api.nvim_err_writeln("Failed to describe pod name or namespace.")
    end
  end,
})

api.nvim_buf_set_keymap(0, "n", "<CR>", "", {
  noremap = true,
  silent = true,
  desc = "kgp",
  callback = function()
    pod_view.Pods()
  end,
})

api.nvim_buf_set_keymap(0, "n", "<bs>", "", {
  noremap = true,
  silent = true,
  desc = "Back",
  callback = function()
    root_view.Root()
  end,
})

api.nvim_buf_set_keymap(0, "n", "R", "", {
  noremap = true,
  silent = true,
  callback = function()
    deployment_view.Deployments()
  end,
})

if not loop.is_running() then
  loop.start_loop(deployment_view.Deployments)
end
