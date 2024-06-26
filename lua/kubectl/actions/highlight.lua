local M = {}
local api = vim.api

vim.api.nvim_set_hl(0, "KubectlHeader", { fg = "#569CD6" }) -- Blue
vim.api.nvim_set_hl(0, "KubectlWarning", { fg = "#D19A66" }) -- Orange
vim.api.nvim_set_hl(0, "KubectlError", { fg = "#D16969" }) -- Red
vim.api.nvim_set_hl(0, "KubectlInfo", { fg = "#608B4E" }) -- Green
vim.api.nvim_set_hl(0, "KubectlDebug", { fg = "#DCDCAA" }) -- Yellow
vim.api.nvim_set_hl(0, "KubectlSuccess", { fg = "#4EC9B0" }) -- Cyan
vim.api.nvim_set_hl(0, "KubectlPending", { fg = "#C586C0" }) -- Purple
vim.api.nvim_set_hl(0, "KubectlDeprecated", { fg = "#D4A5A5" }) -- Pink
vim.api.nvim_set_hl(0, "KubectlExperimental", { fg = "#CE9178" }) -- Brown
vim.api.nvim_set_hl(0, "KubectlNote", { fg = "#9CDCFE" }) -- Light Blue
vim.api.nvim_set_hl(0, "KubectlGray", { fg = "#A9A9A9" }) -- Dark Gray

-- Define M.symbols for tags
M.symbols = {
  header = "◆",
  warning = "⚠",
  error = "✖",
  info = "ℹ",
  debug = "⚑",
  success = "✓",
  pending = "☐",
  deprecated = "☠",
  experimental = "⚙",
  gray= "░",
  note = "✎",
  clear = "➤",
  tab = "↹",
}

local tag_patterns = {
  { pattern = M.symbols.header .. "[^" .. M.symbols.header .. M.symbols.clear .. "]*", group = "KubectlHeader" }, -- Headers
  { pattern = M.symbols.warning .. "[^" .. M.symbols.warning .. M.symbols.clear .. "]*", group = "KubectlWarning" }, -- Warnings
  { pattern = M.symbols.error .. "[^" .. M.symbols.error .. M.symbols.clear .. "]*", group = "KubectlError" }, -- Errors
  { pattern = M.symbols.info .. "[^" .. M.symbols.info .. M.symbols.clear .. "]*", group = "KubectlInfo" }, -- Info
  { pattern = M.symbols.debug .. "[^" .. M.symbols.debug .. M.symbols.clear .. "]*", group = "KubectlDebug" }, -- Debug
  { pattern = M.symbols.success .. "[^" .. M.symbols.success .. M.symbols.clear .. "]*", group = "KubectlSuccess" }, -- Success
  { pattern = M.symbols.pending .. "[^" .. M.symbols.pending .. M.symbols.clear .. "]*", group = "KubectlPending" }, -- Pending
  { pattern = M.symbols.gray .. "[^" .. M.symbols.pending .. M.symbols.clear .. "]*", group = "KubectlGray" }, -- Pending
  {
    pattern = M.symbols.deprecated .. "[^" .. M.symbols.deprecated .. M.symbols.clear .. "]*",
    group = "KubectlDeprecated",
  }, -- Deprecated
  {
    pattern = M.symbols.experimental .. "[^" .. M.symbols.experimental .. M.symbols.clear .. "]*",
    group = "KubectlExperimental",
  }, -- Experimental
  { pattern = M.symbols.note .. "[^" .. M.symbols.note .. M.symbols.clear .. "]*", group = "KubectlNote" }, -- Note
}

function M.setup(win)
  win = win or vim.api.nvim_get_current_win()
  for _, tag in ipairs(tag_patterns) do
    vim.fn.matchadd(tag.group, tag.pattern, 100, -1, { conceal = "", window = win })
  end
end

function M.set_highlighting(win)
  win = win or vim.api.nvim_get_current_win()
  for _, symbol in pairs(M.symbols) do
    vim.cmd("call win_execute(" .. win .. ", 'syntax match Conceal" .. ' "' .. symbol .. '" conceal' .. "')")
  end

  api.nvim_set_option_value("conceallevel", 3, { scope = "local", win = win })
  api.nvim_set_option_value("concealcursor", "nc", { scope = "local", win = win })
end

return M
