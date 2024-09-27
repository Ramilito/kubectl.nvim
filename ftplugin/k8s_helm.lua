local api = vim.api
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local helm_view = require("kubectl.views.helm")
local loop = require("kubectl.utils.loop")
local mappings = require("kubectl.mappings")

mappings.map_if_plug_not_set("n", "gk", "<Plug>(kubectl.kill)")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.kill)", "", {
    noremap = true,
    silent = true,
    desc = "Uninstall helm deployment",
    callback = function()
      local name, ns = helm_view.getCurrentSelection()
      buffers.confirmation_buffer(
        string.format("Are you sure that you want to uninstall the helm deployment: %s in namespace %s?", name, ns),
        "prompt",
        function(confirm)
          if confirm then
            commands.shell_command_async("helm", { "uninstall", name, "-n", ns }, function(response)
              vim.schedule(function()
                vim.notify(response)
              end)
            end)
          end
        end
      )
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(helm_view.Draw)
  end
end

init()
