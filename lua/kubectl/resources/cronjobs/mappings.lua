local cronjob_view = require("kubectl.resources.cronjobs")
local mappings = require("kubectl.mappings")
local err_msg = "Failed to extract cronjob name or namespace."
local buffers = require("kubectl.actions.buffers")
local tables = require("kubectl.utils.tables")

local M = {}

M.overrides = {
  ["<Plug>(kubectl.create_job)"] = {
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
  },
  ["<Plug>(kubectl.suspend_cronjob)"] = {
    noremap = true,
    silent = true,
    desc = "Suspend selected cronjob",
    callback = function()
      local name, ns, current = tables.getCurrentSelection(2, 1, 4)
      if not name or not ns or not current then
        vim.notify(err_msg, vim.log.levels.ERROR)
        return
      end

      local current_action = current == "true" and true or false
      local action = current_action and "unsuspend" or "suspend"
      buffers.confirmation_buffer(
        string.format("Are you sure that you want to %s the cronjob: %s", action, name),
        "prompt",
        function(confirm)
          if confirm then
            local client = require("kubectl.client")
            local status = client.suspend_cronjob(name, ns, not current_action)
            if status then
              vim.notify(status)
            end
          end
        end
      )
    end,
  },
}

M.register = function()
  mappings.map_if_plug_not_set("n", "gc", "<Plug>(kubectl.create_job)")
  mappings.map_if_plug_not_set("n", "gss", "<Plug>(kubectl.suspend_cronjob)")
end

return M
