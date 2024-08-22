local M = {}
local api = vim.api

-- Define M.symbols for tags
M.symbols = {
  header = "KubectlHeader",
  warning = "KubectlWarning",
  error = "KubectlError",
  info = "KubectlInfo",
  debug = "KubectlDebug",
  success = "KubectlSuccess",
  pending = "KubectlPending",
  deprecated = "KubectlDeprecated",
  experimental = "KubectlExperimental",
  gray = "KubectlGray",
  note = "KubectlNote",
  clear = "KubectlClear",
  tab = "KubectlTab",
  underline = "KubectlUnderline",
}
function M.setup()
  api.nvim_set_hl(0, "KubectlHeader", { fg = "#569CD6" }) -- Blue
  api.nvim_set_hl(0, "KubectlWarning", { fg = "#D19A66" }) -- Orange
  api.nvim_set_hl(0, "KubectlError", { fg = "#D16969" }) -- Red
  api.nvim_set_hl(0, "KubectlInfo", { fg = "#608B4E" }) -- Green
  api.nvim_set_hl(0, "KubectlDebug", { fg = "#DCDCAA" }) -- Yellow
  api.nvim_set_hl(0, "KubectlSuccess", { fg = "#4EC9B0" }) -- Cyan
  api.nvim_set_hl(0, "KubectlPending", { fg = "#C586C0" }) -- Purple
  api.nvim_set_hl(0, "KubectlDeprecated", { fg = "#D4A5A5" }) -- Pink
  api.nvim_set_hl(0, "KubectlExperimental", { fg = "#CE9178" }) -- Brown
  api.nvim_set_hl(0, "KubectlNote", { fg = "#9CDCFE" }) -- Light Blue
  api.nvim_set_hl(0, "KubectlGray", { fg = "#666666" }) -- Dark Gray
  api.nvim_set_hl(0, "KubectlUnderline", { underline = true })
end

return M
