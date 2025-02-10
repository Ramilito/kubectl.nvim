local api = vim.api
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local cronjob_view = require("kubectl.views.cronjobs")
local loop = require("kubectl.utils.loop")
local mappings = require("kubectl.mappings")
local tables = require("kubectl.utils.tables")
local err_msg = "Failed to extract cronjob name or namespace."

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.select)", "", {
    noremap = true,
    silent = true,
    desc = "Go to jobs",
    callback = function()
      local name, ns = cronjob_view.getCurrentSelection()
      if not name or not ns then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      local job_view = require("kubectl.views.jobs")
      local job_def = require("kubectl.views.jobs.definition")

      job_view.View()
      -- Order is important since .View() will reset this selection
      job_def.owner = { name = name, ns = ns }
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.create_job)", "", {
    noremap = true,
    silent = true,
    desc = "Create job from cronjob",
    callback = function()
      local name, ns = cronjob_view.getCurrentSelection()
      if not name or not ns then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      cronjob_view.create_from_cronjob(name, ns)
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.suspend_cronjob)", "", {
    noremap = true,
    silent = true,
    desc = "Suspend selected cronjob",
    callback = function()
      local name, ns, current = tables.getCurrentSelection(2, 1, 4)
      if not name or not ns or not current then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end
      current = current == "true" and true or false
      local action = current and "unsuspend" or "suspend"
      buffers.confirmation_buffer(
        string.format("Are you sure that you want to %s the cronjob: %s", action, name),
        "prompt",
        function(confirm)
          if confirm then
            commands.shell_command_async("kubectl", {
              "patch",
              "cronjob/" .. name,
              "-n",
              ns,
              "-p",
              '{"spec" : {"suspend" : ' .. tostring(not current) .. "}}",
            }, function(response)
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
    loop.start_loop(cronjob_view.Draw)
  end
end

init()

vim.schedule(function()
  mappings.map_if_plug_not_set("n", "gc", "<Plug>(kubectl.create_job)")
  mappings.map_if_plug_not_set("n", "gss", "<Plug>(kubectl.suspend_cronjob)")
end)
