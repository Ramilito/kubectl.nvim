local api = vim.api
local commands = require("kubectl.actions.commands")
local cronjob_view = require("kubectl.views.cronjobs")
local definition = require("kubectl.views.jobs.definition")
local job_view = require("kubectl.views.jobs")
local loop = require("kubectl.utils.loop")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  local gl = require("kubectl.config").options.keymaps.global
  api.nvim_buf_set_keymap(bufnr, "n", gl.help.key, "", {
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
    desc = "Go to pods",
    callback = function()
      local name, ns = job_view.getCurrentSelection()
      view.set_and_open_pod_selector("jobs", name, ns)
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<bs>", "", {
    noremap = true,
    silent = true,
    desc = "Go up",
    callback = function()
      cronjob_view.View()
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "gc", "", {
    noremap = true,
    silent = true,
    desc = "Create job from job",
    callback = function()
      local name, ns = job_view.getCurrentSelection()
      vim.ui.input({ prompt = "New job name " }, function(input)
        if not input or input == "" then
          return
        end
        commands.shell_command_async(
          "kubectl",
          { "create", "job", input, "--from", "jobs/" .. name, "-n", ns },
          function(response)
            vim.schedule(function()
              vim.notify(response)
            end)
          end
        )
      end)
    end,
  })
end

--- Initialize the module
local function init()
  set_keymaps(0)
  if not loop.is_running() then
    loop.start_loop(job_view.Draw)
  end
end

init()
