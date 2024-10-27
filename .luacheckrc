cache = true

std = luajit
codes = true

self = false
ignore = {
  -- Neovim lua API + luacheck thinks variables like `vim.wo.spell = true` is
  -- invalid when it actually is valid. So we have to display rule `W122`.
  --
  "122",
}
-- Global objects defined by the C code
read_globals = {
  "vim",
}
