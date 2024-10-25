local api = vim.api
local commands = require("kubectl.actions.commands")
local job_view = require("kubectl.views.jobs")
local loop = require("kubectl.utils.loop")
local mappings = require("kubectl.mappings")
local state = require("kubectl.state")
local view = require("kubectl.views")

--- Set key mappings for the buffer
local function set_keymaps(bufnr)
  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.select)", "", {
    noremap = true,
    silent = true,
    desc = "Go to pods",
    callback = function()
      local name, ns = job_view.getCurrentSelection()
      state.setFilter("")
      view.set_and_open_pod_selector(name, ns)
    end,
  })

  api.nvim_buf_set_keymap(bufnr, "n", "<Plug>(kubectl.create_job)", "", {
    noremap = true,
    silent = true,
    desc = "Create job from job",
    callback = function()
      local name, ns = job_view.getCurrentSelection()
      if name and ns then
        job_view.create_from_job(name, ns)
      else
        api.nvim_err_writeln("Failed to create job.")
      end
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

vim.schedule(function()
  mappings.map_if_plug_not_set("n", "gc", "<Plug>(kubectl.create_job)")
end)
