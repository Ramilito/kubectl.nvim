  function builder.drawHeader(cancellationToken)
    if not config.options.headers then
      return builder
    end
    if cancellationToken and cancellationToken() then
      return builder
    end

    builder.buf_header_nr, builder.win_header_nr = buffers.header_buffer(builder.win_header_nr)
    local ok, win_config = pcall(vim.api.nvim_win_get_config, builder.win_header_nr)
    local current_buf = vim.api.nvim_get_current_buf()

    if ok and (win_config.relative ~= "" or current_buf ~= builder.buf_nr) then
      return builder
    end
    if builder.win_header_nr and vim.api.nvim_win_is_valid(builder.win_header_nr) then
      buffers.set_content(builder.buf_header_nr, {
        content = builder.header.data,
        marks   = builder.header.marks,
      })
      vim.api.nvim_set_option_value("winbar", "", { scope = "local", win = builder.win_header_nr })
      vim.api.nvim_set_option_value("statusline", " ", { scope = "local", win = builder.win_header_nr })

      local rows = vim.api.nvim_buf_line_count(builder.buf_header_nr)
      win_config.height = rows
      pcall(vim.api.nvim_win_set_config, builder.win_header_nr, win_config)
    end
    return builder
  end
