local buffers = require("kubectl.actions.buffers")
local cronjob_view = require("kubectl.resources.cronjobs")
local manager = require("kubectl.resource_manager")
local mapping_helpers = require("kubectl.utils.mapping_helpers")
local mappings = require("kubectl.mappings")
local tables = require("kubectl.utils.tables")

local M = {}
local err_msg = "Failed to extract cronjob name or namespace."

M.overrides = {
  ["<Plug>(kubectl.create_job)"] = {
    noremap = true,
    silent = true,
    desc = "Create job from cronjob",
    callback = mapping_helpers.safe_callback(cronjob_view, cronjob_view.create_from_cronjob),
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
      local title = string.format("%s cronjob", action:gsub("^%l", string.upper))

      local builder = manager.get_or_create("cronjob_suspend")
      builder.view_framed({
        resource = "cronjob_suspend",
        ft = "k8s_cronjob_suspend",
        title = title,
        panes = { { title = title } },
      })

      local buf = builder.buf_nr

      -- Build content
      local content = { name, ns, "", "" }
      local marks = {
        { row = 0, start_col = 0, virt_text = { { "Name: ", "KubectlHeader" } }, virt_text_pos = "inline" },
        { row = 1, start_col = 0, virt_text = { { "Namespace: ", "KubectlHeader" } }, virt_text_pos = "inline" },
      }

      buffers.set_content(buf, { content = content })
      buffers.apply_marks(buf, marks, nil)

      -- Set up y/n keymaps
      vim.keymap.set("n", "y", function()
        local client = require("kubectl.client")
        local status = client.suspend_cronjob(name, ns, not current_action)
        if status then
          vim.notify(status)
        end
        builder.frame.close()
      end, { buffer = buf, noremap = true, silent = true })

      vim.keymap.set("n", "n", function()
        builder.frame.close()
      end, { buffer = buf, noremap = true, silent = true })

      -- Fit to content
      builder.fitToContent(1)

      -- Add centered confirmation text
      local win_width = vim.api.nvim_win_get_config(builder.win_nr).width or 100
      local confirm_text = "[y]es [n]o"
      local padding = string.rep(" ", math.floor((win_width - #confirm_text) / 2))
      buffers.apply_marks(buf, {
        {
          row = #content - 1,
          start_col = 0,
          virt_text = { { padding .. "[y]es ", "KubectlError" }, { "[n]o", "KubectlInfo" } },
          virt_text_pos = "inline",
        },
      }, nil)

      vim.cmd([[syntax match KubectlPending /.*/]])
    end,
  },
}

M.register = function()
  mappings.map_if_plug_not_set("n", "gc", "<Plug>(kubectl.create_job)")
  mappings.map_if_plug_not_set("n", "gss", "<Plug>(kubectl.suspend_cronjob)")
end

return M
