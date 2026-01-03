local completers = require("kubectl.commands.completers")
local registry = require("kubectl.commands")

local M = {}

--- Execute kubectl diff on a file or current buffer
---@param path string|nil Path to file, "." for current buffer, or nil
function M.execute_diff(path)
  local ansi = require("kubectl.utils.ansi")
  local buffers = require("kubectl.actions.buffers")
  local commands = require("kubectl.actions.commands")
  local config = require("kubectl.config")

  if path == "." then
    path = vim.fn.expand("%:p")
  end

  local buf = buffers.floating_buffer("k8s_diff", "diff")

  if config.options.diff.bin == "kubediff" then
    local column_size = vim.api.nvim_win_get_width(0)
    local args = { "-t", tostring(column_size) }
    if path then
      table.insert(args, "-p")
      table.insert(args, path)
    end
    commands.shell_command_async(config.options.diff.bin, args, function(data)
      local stripped_output = {}

      local content = vim.split(data, "\n")
      for _, line in ipairs(content) do
        local stripped = ansi.strip_ansi_codes(line)
        table.insert(stripped_output, stripped)
      end
      vim.schedule(function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, stripped_output)
        vim.api.nvim_set_option_value("modified", false, { buf = buf })
        ansi.apply_highlighting(buf, content, stripped_output)
      end)
    end)
  else
    commands.execute_terminal(
      "kubectl",
      { "diff", "-f", path },
      { env = { KUBECTL_EXTERNAL_DIFF = config.options.diff.bin } }
    )
  end
end

---@type CommandSpec
M.spec = {
  name = "diff",
  flags = vim.list_extend({
    { name = "filename", short = "f", takes_value = true },
  }, completers.common_flags),

  execute = function(args)
    local path = args[1]
    M.execute_diff(path)
  end,

  complete = function(positional, _)
    -- Complete file paths (Neovim handles this)
    if #positional <= 1 then
      return { "." }
    end
    return {}
  end,
}

registry.register(M.spec)

return M
