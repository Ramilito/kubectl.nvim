local api = vim.api
local ResourceBuilder = require("kubectl.resourcebuilder")
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local helm_view = require("kubectl.views.helm")
local loop = require("kubectl.utils.loop")
local mappings = require("kubectl.mappings")

mappings.map_if_plug_not_set("n", "gk", "<Plug>(kubectl.kill)")
mappings.map_if_plug_not_set("n", "gy", "<Plug>(kubectl.yaml)")

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
  vim.api.nvim_buf_set_keymap(0, "n", "<Plug>(kubectl.yaml)", "", {
    noremap = true,
    silent = true,
    desc = "Get YAML",
    callback = function()
      local name, ns = helm_view.getCurrentSelection()

      if not name then
        vim.notify("Not a valid selection to view yaml", vim.log.levels.INFO)
        return
      end

      local args = { "status", name, "-n", ns, "-o", "json" }

      -- Save the resource data to a temporary file
      local self = ResourceBuilder:new("edit_resource"):setCmd(args, "helm"):fetch():decodeJson()

      local tmpfilename = string.format("%s-%s-%s.yaml", vim.fn.tempname(), name, ns)

      local tmpfile = assert(io.open(tmpfilename, "w+"), "Failed to open temp file")
      tmpfile:write(self.data.manifest)
      tmpfile:close()

      -- open the file
      vim.cmd("tabnew | edit " .. tmpfilename)

      vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = 0 })
      vim.api.nvim_set_option_value("modified", false, { buf = 0 })
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
