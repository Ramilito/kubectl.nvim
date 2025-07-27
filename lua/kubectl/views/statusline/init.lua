local commands = require("kubectl.actions.commands")
local M = {
  interval = 2000,
}

M.View = function()
  vim.o.laststatus = 3
  local timer = vim.uv.new_timer()

  timer:start(0, M.interval, function()
    vim.schedule(function()
      M.Draw()
    end)
  end)
end

M.Draw = function()
  commands.run_async("get_statusline_async", {}, function(data, err)
    if err then
      return
    end
    print(data)

		-- local ok, result = pcall(vim.api.nvim_set_option_value, "statusline", M.generateStatusline(), { scope = "global" })
		-- print(ok, result)
  end)

end

function M.generateStatusline()
  return "test"
end

return M
