local api = vim.api
local buffers = require("kubectl.actions.buffers")
local commands = require("kubectl.actions.commands")
local cronjob_view = require("kubectl.views.cronjobs")
local definition = require("kubectl.views.cronjobs.definition")
local loop = require("kubectl.utils.loop")
local root_view = require("kubectl.views.root")
local tables = require("kubectl.utils.tables")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "g?", "", {
    noremap = true,
    silent = true,
    desc = "Help",
    callback = function()
      view.Hints(definition.hints)
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<CR>", "", {
    noremap = true,
    silent = true,
    desc = "Go to jobs",
    callback = function()
      local name, ns = cronjob_view.getCurrentSelection()
      local job_view = require("kubectl.views.jobs")
      local job_def = require("kubectl.views.jobs.definition")

      job_view.View()
      -- Order is important since .View() will reset this selection
      job_def.owner = { name = name, ns = ns }
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<bs>", "", {
    noremap = true,
    silent = true,
    desc = "Go up",
    callback = function()
      root_view.View()
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "gc", "", {
    noremap = true,
    silent = true,
    desc = "Create job from cronjob",
    callback = function()
      local name, ns = cronjob_view.getCurrentSelection()
      vim.ui.input({ prompt = "New job name " }, function(input)
        if not input or input == "" then
          return
        end
        commands.shell_command_async(
          "kubectl",
          { "create", "job", input, "--from", "cronjobs/" .. name, "-n", ns },
          function(response)
            vim.schedule(function()
              vim.notify(response)
            end)
          end
        )
      end)
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "gx", "", {
    noremap = true,
    silent = true,
    desc = "Suspend selected cronjob",
    callback = function()
      local name, ns, current = tables.getCurrentSelection(2, 1, 4)
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
