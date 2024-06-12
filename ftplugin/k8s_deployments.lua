local api = vim.api
local Menu = require("nui.menu")
local deployment_view = require("kubectl.views.deployments")
local hl = require("kubectl.actions.highlight")
local loop = require("kubectl.utils.loop")
local pod_view = require("kubectl.views.pods")
local root_view = require("kubectl.views.root")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views")

api.nvim_buf_set_keymap(0, "n", "g?", "", {
  noremap = true,
  silent = true,
  callback = function()
    view.Hints({
      "      Hint: "
        .. hl.symbols.pending
        .. "d "
        .. hl.symbols.clear
        .. "desc | "
        .. hl.symbols.pending
        .. "<cr> "
        .. hl.symbols.clear
        .. "pods",
    })
  end,
})

api.nvim_buf_set_keymap(0, "n", "r", "", {
  noremap = true,
  silent = true,
  callback = function()
    local menu = Menu({
      position = "50%",
      size = {
        width = 25,
        height = 5,
      },
      border = {
        style = "single",
        text = {
          top = "Are you sure that you want to restart the deployment?",
          top_align = "center",
        },
      },
      win_options = {
        winhighlight = "Normal:Normal,FloatBorder:Normal",
      },
    }, {
      lines = {
        Menu.item("Yes"),
        Menu.item("Cancel"),
      },
      max_width = 20,
      keymap = {
        close = { "<Esc>", "<C-c>" },
        submit = { "<CR>", "<Space>" },
      },
      on_close = function()
        print("Cancelled!")
      end,
      on_submit = function(item)
        if item.text == "Yes" then
          local namespace, deployment_name = tables.getCurrentSelection(unpack({ 1, 2 }))
          local output = vim.fn.system("kubectl rollout restart deployment/" .. deployment_name .. " -n " .. namespace)
          print(output)
        else
          print("Cancelled!")
        end
      end,
    })

    menu:mount()
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
