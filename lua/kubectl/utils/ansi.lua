local M = {}

function M.parse_ansi_code(line)
  local parts = {}
  local active_color = nil
  local pattern = "([^\27]*)\27%[([%d;]*)m"

  local function get_color(code)
    if code == "0" then
      return nil
    elseif code:match("38;2;%d+;%d+;%d+") then
      local r, g, b = code:match("38;2;(%d+);(%d+);(%d+)")
      return { tonumber(r), tonumber(g), tonumber(b) }
    elseif code:match("3[0-7]") then
      local ansi_colors = {
        [30] = { 0, 0, 0 }, -- Black
        [31] = { 205, 49, 49 }, -- Red
        [32] = { 13, 188, 121 }, -- Green
        [33] = { 229, 229, 16 }, -- Yellow
        [34] = { 36, 114, 200 }, -- Blue
        [35] = { 188, 63, 188 }, -- Magenta
        [36] = { 17, 168, 205 }, -- Cyan
        [37] = { 229, 229, 229 }, -- White
      }
      local num_code = tonumber(code:match("3([0-7])"))
      return ansi_colors[num_code + 30]
    end
    return active_color
  end

  for pre_text, code, post_text in line:gmatch(pattern) do
    if #pre_text > 0 then
      table.insert(parts, { text = pre_text, color = active_color })
    end

    active_color = get_color(code)

    -- Update the line to the remaining text after the ANSI code
    line = post_text
  end

  -- Add any remaining text after the last escape sequence
  if line and #line > 0 then
    table.insert(parts, { text = line, color = active_color })
  end

  return parts
end

function M.strip_ansi_codes(line)
  return line:gsub("\27%[%d+;?%d*;?%d*;?%d*;?%d*;?%d*;?%d*m", ""):gsub("\27%[m", "")
end

function M.apply_highlighting(bufnr, lines, stripped_lines)
  local namespace_id = vim.api.nvim_create_namespace("ansi_highlight")

  for linenr, line in ipairs(lines) do
    local parts = M.parse_ansi_code(line)
    local stripped_line = stripped_lines[linenr]

    vim.api.nvim_buf_set_lines(bufnr, linenr - 1, linenr, false, { stripped_line })

    local stripped_colnr = 0
    for _, part in ipairs(parts) do
      local start_col = stripped_colnr
      local end_col = stripped_colnr + #part.text:gsub("\27%[0m", "")
      if part.color then
        local hl_group = string.format("AnsiColor_%02x%02x%02x", part.color[1], part.color[2], part.color[3])
        if vim.fn.hlID(hl_group) == 0 then
          vim.api.nvim_command(
            string.format("highlight %s guifg=#%02x%02x%02x", hl_group, part.color[1], part.color[2], part.color[3])
          )
        end
        vim.api.nvim_buf_add_highlight(bufnr, namespace_id, hl_group, linenr - 1, start_col, end_col)
      end
      stripped_colnr = end_col
    end
  end
end

return M
