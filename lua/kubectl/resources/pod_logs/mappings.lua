local client = require("kubectl.client")
local mappings = require("kubectl.mappings")
local pod_view = require("kubectl.resources.pods")
local str = require("kubectl.utils.string")

local M = {}

--- Toggle JSON: expand/collapse with fold support
local function toggle_json()
  local row = vim.api.nvim_win_get_cursor(0)[1]

  -- If there's a fold at cursor, toggle it
  if vim.fn.foldlevel(row) > 0 then
    vim.cmd("normal! za")
    return
  end

  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
  local result = client.toggle_json(line)
  if not result then
    return vim.notify("No valid JSON found", vim.log.levels.WARN)
  end

  local content = line:sub(1, result.start_idx - 1) .. result.json .. line:sub(result.end_idx + 1)
  local new_lines = vim.split(content, "\n")
  vim.api.nvim_buf_set_lines(0, row - 1, row, false, new_lines)

  -- Create open fold over expanded JSON
  if #new_lines > 1 then
    vim.wo.foldmethod = "manual"
    vim.cmd(row .. "," .. (row + #new_lines - 1) .. "fold")
    vim.cmd("normal! zo")
  end
end

M.overrides = {
  ["<Plug>(kubectl.follow)"] = {
    noremap = true,
    silent = true,
    desc = "Tail logs",
    callback = function()
      pod_view.TailLogs()
    end,
  },

  ["<Plug>(kubectl.previous_logs)"] = {
    noremap = true,
    silent = true,
    desc = "Previous logs",
    callback = function()
      if pod_view.log.show_previous == true then
        pod_view.log.show_previous = false
      else
        pod_view.log.show_previous = true
      end
      pod_view.Logs(false)
    end,
  },

  ["<Plug>(kubectl.wrap)"] = {
    noremap = true,
    silent = true,
    desc = "Toggle wrap",
    callback = function()
      vim.api.nvim_set_option_value("wrap", not vim.api.nvim_get_option_value("wrap", {}), {})
    end,
  },

  ["<Plug>(kubectl.timestamps)"] = {
    noremap = true,
    silent = true,
    desc = "Toggle timestamps",
    callback = function()
      if pod_view.log.show_timestamps == true then
        pod_view.log.show_timestamps = false
      else
        pod_view.log.show_timestamps = true
      end
      pod_view.Logs(false)
    end,
  },

  ["<Plug>(kubectl.history)"] = {
    noremap = true,
    silent = true,
    desc = "Log history",
    callback = function()
      vim.ui.input({ prompt = "Since (5s, 2m, 3h)=", default = pod_view.log.log_since }, function(input)
        pod_view.log.log_since = input or pod_view.log.log_since
        pod_view.Logs(false)
      end)
    end,
  },
  ["<Plug>(kubectl.prefix)"] = {
    noremap = true,
    silent = true,
    desc = "Toggle prefix",
    callback = function()
      if pod_view.log.show_log_prefix == true then
        pod_view.log.show_log_prefix = false
      else
        pod_view.log.show_log_prefix = true
      end
      pod_view.Logs(false)
    end,
  },
  ["<Plug>(kubectl.select)"] = {
    noremap = true,
    silent = true,
    desc = "Add divider",
    callback = function()
      str.divider(0)
    end,
  },
  ["<Plug>(kubectl.expand_json)"] = {
    noremap = true,
    silent = true,
    desc = "Toggle JSON",
    callback = toggle_json,
  },
}

function M.register()
  mappings.map_if_plug_not_set("n", "f", "<Plug>(kubectl.follow)")
  mappings.map_if_plug_not_set("n", "gw", "<Plug>(kubectl.wrap)")
  mappings.map_if_plug_not_set("n", "gp", "<Plug>(kubectl.prefix)")
  mappings.map_if_plug_not_set("n", "gt", "<Plug>(kubectl.timestamps)")
  mappings.map_if_plug_not_set("n", "gh", "<Plug>(kubectl.history)")
  mappings.map_if_plug_not_set("n", "<CR>", "<Plug>(kubectl.select)")
  mappings.map_if_plug_not_set("n", "gpp", "<Plug>(kubectl.previous_logs)")
  mappings.map_if_plug_not_set("n", "gj", "<Plug>(kubectl.expand_json)")
end

return M
