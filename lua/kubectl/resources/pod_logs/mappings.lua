local client = require("kubectl.client")
local log_session = require("kubectl.views.logs.session")
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

--- Get current options and update session manager
---@param key string Option key to toggle
---@param value any New value (or nil to toggle boolean)
---@return kubectl.LogSessionOptions Updated options
local function update_option(key, value)
  local opts = log_session.get_options()
  if value ~= nil then
    opts[key] = value
  else
    opts[key] = not opts[key]
  end
  -- Update the global options in the session manager
  log_session.set_options(opts)
  return opts
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
      update_option("previous")
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
      update_option("timestamps")
      pod_view.Logs(false)
    end,
  },

  ["<Plug>(kubectl.history)"] = {
    noremap = true,
    silent = true,
    desc = "Log history",
    callback = function()
      local opts = log_session.get_options()
      vim.ui.input({ prompt = "Since (5s, 2m, 3h)=", default = opts.since }, function(input)
        if input then
          update_option("since", input)
        end
        pod_view.Logs(false)
      end)
    end,
  },
  ["<Plug>(kubectl.prefix)"] = {
    noremap = true,
    silent = true,
    desc = "Toggle prefix",
    callback = function()
      update_option("prefix")
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
