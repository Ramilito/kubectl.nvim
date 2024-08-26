local definition = require("kubectl.views.pvc.definition")
local loop = require("kubectl.utils.loop")
local pvc_view = require("kubectl.views.pvc")
local commands = require("kubectl.actions.commands")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "g?", "", {
    noremap = true,
    silent = true,
    desc = "Help",
    callback = function()
      view.Hints(definition.hints)
    end,
  })

  vim.api.nvim_buf_set_keymap(bufnr, "n", "<CR>", "", {
    noremap = true,
    silent = true,
    desc = "Go to PVs",
    callback = function()
      local pv_view = require("kubectl.views.pv")
      local name, ns = pvc_view.getCurrentSelection()
      if not name or not ns then
        return pv_view.View()
      end

      -- get pv of pvc
      local pv_name_args = { "get", "pvc", name, "-n", ns, "-o", 'jsonpath="{.spec.volumeName}"' }
      local pv_name = commands.execute_shell_command("kubectl", pv_name_args)

      -- add to filter and view
      require("kubectl.state").filter = pv_name
      pv_view.View()
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(pvc_view.Draw)
  end
end

init()
