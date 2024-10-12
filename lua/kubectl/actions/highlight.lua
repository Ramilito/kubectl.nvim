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
  white = "KubectlWhite",
  note = "KubectlNote",
  clear = "KubectlClear",
  tab = "KubectlTab",
  underline = "KubectlUnderline",
  match = "KubectlPmatch",
}

local highlights = {
  KubectlHeader = { fg = "#569CD6" }, -- Blue
  KubectlWarning = { fg = "#D19A66" }, -- Orange
  KubectlError = { fg = "#D16969" }, -- Red
  KubectlInfo = { fg = "#608B4E" }, -- Green
  KubectlDebug = { fg = "#DCDCAA" }, -- Yellow
  KubectlSuccess = { fg = "#4EC9B0" }, -- Cyan
  KubectlPending = { fg = "#C586C0" }, -- Purple
  KubectlDeprecated = { fg = "#D4A5A5" }, -- Pink
  KubectlExperimental = { fg = "#CE9178" }, -- Brown
  KubectlNote = { fg = "#9CDCFE" }, -- Light Blue
  KubectlGray = { fg = "#666666" }, -- Dark Gray
  KubectlWhite = { fg = "#FFFFFF" }, -- White
  KubectlPselect = { bg = "#3e4451" }, -- Grey Blue
  KubectlPmatch = { link = "KubectlWarning" },
  KubectlUnderline = { underline = true },
}

local function add_bold_variant()
  for group, attrs in pairs(highlights) do
    highlights[group .. "Bold"] = vim.tbl_extend("force", attrs, { bold = true })
  end

  for key, group in pairs(M.symbols) do
    M.symbols[key .. "_bold"] = group .. "Bold"
  end
end

function M.setup()
  add_bold_variant()
  for group, attrs in pairs(highlights) do
    local success, hl = pcall(api.nvim_get_hl, 0, group)
    if not success or not hl then
      api.nvim_set_hl(0, group, attrs)
    end
  end
end

return M
