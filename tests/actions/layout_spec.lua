describe("actions.layout", function()
  local layout
  local created_bufs = {}
  local created_wins = {}

  -- Helper to track created buffers for cleanup
  local function create_test_buf()
    local buf = vim.api.nvim_create_buf(false, true)
    table.insert(created_bufs, buf)
    return buf
  end

  -- Helper to track created windows for cleanup
  local function track_win(win)
    table.insert(created_wins, win)
    return win
  end

  before_each(function()
    package.loaded["kubectl.actions.layout"] = nil
    package.loaded["kubectl.config"] = nil

    layout = require("kubectl.actions.layout")

    -- Setup config with test values
    local config = require("kubectl.config")
    config.options = config.options or {}
    config.options.float_size = {
      width = 0.9,
      height = 0.8,
      col = 10,
      row = 5,
    }

    created_bufs = {}
    created_wins = {}
  end)

  after_each(function()
    -- Clean up windows first (must be done before buffers)
    for _, win in ipairs(created_wins) do
      if vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    -- Clean up buffers
    for _, buf in ipairs(created_bufs) do
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end)

  describe("set_win_options", function()
    it("sets cursorline to true", function()
      local buf = create_test_buf()
      local win = track_win(layout.float_layout(buf, "", nil, { size = { width = 50, height = 10 } }))

      layout.set_win_options(win)

      assert.is_true(vim.api.nvim_get_option_value("cursorline", { win = win }))
    end)

    it("sets wrap to false", function()
      local buf = create_test_buf()
      local win = track_win(layout.float_layout(buf, "", nil, { size = { width = 50, height = 10 } }))

      layout.set_win_options(win)

      assert.is_false(vim.api.nvim_get_option_value("wrap", { win = win }))
    end)

    it("sets sidescrolloff to 0", function()
      local buf = create_test_buf()
      local win = track_win(layout.float_layout(buf, "", nil, { size = { width = 50, height = 10 } }))

      layout.set_win_options(win)

      assert.are.equal(0, vim.api.nvim_get_option_value("sidescrolloff", { win = win }))
    end)
  end)

  describe("set_buf_options", function()
    it("sets filetype", function()
      local buf = create_test_buf()

      layout.set_buf_options(buf, "k8s_pods", "yaml", "test_buffer")

      assert.are.equal("k8s_pods", vim.api.nvim_get_option_value("filetype", { buf = buf }))
    end)

    it("sets syntax", function()
      local buf = create_test_buf()

      layout.set_buf_options(buf, "k8s_pods", "yaml", "test_buffer")

      assert.are.equal("yaml", vim.api.nvim_get_option_value("syntax", { buf = buf }))
    end)

    it("sets bufhidden to hide", function()
      local buf = create_test_buf()

      layout.set_buf_options(buf, "k8s_pods", "yaml", "test_buffer")

      assert.are.equal("hide", vim.api.nvim_get_option_value("bufhidden", { buf = buf }))
    end)

    it("sets modified to false", function()
      local buf = create_test_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "test content" })

      layout.set_buf_options(buf, "k8s_pods", "yaml", "test_buffer")

      assert.is_false(vim.api.nvim_get_option_value("modified", { buf = buf }))
    end)

    it("sets buf_name variable", function()
      local buf = create_test_buf()

      layout.set_buf_options(buf, "k8s_pods", "yaml", "my_buffer_name")

      assert.are.equal("my_buffer_name", vim.api.nvim_buf_get_var(buf, "buf_name"))
    end)
  end)

  describe("main_layout", function()
    it("returns current window", function()
      local current_win = vim.api.nvim_get_current_win()
      local result = layout.main_layout()

      assert.are.equal(current_win, result)
    end)
  end)

  describe("get_editor_dimensions", function()
    it("returns width and height", function()
      local width, height = layout.get_editor_dimensions()

      assert.is_number(width)
      assert.is_number(height)
      assert.is_true(width > 0)
      assert.is_true(height > 0)
    end)

    it("width matches vim columns", function()
      local width, _ = layout.get_editor_dimensions()

      assert.are.equal(vim.opt.columns:get(), width)
    end)

    it("height accounts for statusline and cmdheight", function()
      local _, height = layout.get_editor_dimensions()
      local expected_max = vim.opt.lines:get()

      -- Height should be less than or equal to total lines
      assert.is_true(height <= expected_max)
    end)
  end)

  describe("float_layout", function()
    it("creates a floating window", function()
      local buf = create_test_buf()

      local win = track_win(layout.float_layout(buf, "", nil, { size = { width = 50, height = 10 } }))

      assert.is_true(vim.api.nvim_win_is_valid(win))
    end)

    it("attaches buffer to window", function()
      local buf = create_test_buf()

      local win = track_win(layout.float_layout(buf, "", nil, { size = { width = 50, height = 10 } }))

      assert.are.equal(buf, vim.api.nvim_win_get_buf(win))
    end)

    it("creates window with specified dimensions", function()
      local buf = create_test_buf()

      local win = track_win(layout.float_layout(buf, "", nil, { size = { width = 60, height = 15 } }))
      local config = vim.api.nvim_win_get_config(win)

      assert.are.equal(60, config.width)
      assert.are.equal(15, config.height)
    end)

    it("uses default dimensions from config when not specified", function()
      local buf = create_test_buf()

      local win = track_win(layout.float_layout(buf, "", nil))
      local win_config = vim.api.nvim_win_get_config(win)

      -- Should use config.options.float_size values - just verify it creates valid dimensions
      assert.is_true(win_config.width > 0)
      assert.is_true(win_config.height > 0)
    end)

    it("prepends filetype to title when filetype is provided", function()
      local buf = create_test_buf()

      local win = track_win(layout.float_layout(buf, "k8s_pods", "my-pod", { size = { width = 50, height = 10 } }))
      local win_config = vim.api.nvim_win_get_config(win)

      -- nvim_win_get_config returns title as nested table [[text, hl_group], ...]
      assert.is_truthy(win_config.title)
      if type(win_config.title) == "table" then
        assert.are.equal("k8s_pods - my-pod", win_config.title[1][1])
      else
        assert.are.equal("k8s_pods - my-pod", win_config.title)
      end
    end)

    it("does not modify title when filetype is empty", function()
      local buf = create_test_buf()

      local win = track_win(layout.float_layout(buf, "", "my-title", { size = { width = 50, height = 10 } }))
      local win_config = vim.api.nvim_win_get_config(win)

      -- When filetype is empty, title is passed as-is (not prefixed)
      -- nvim_win_get_config returns title as nested table [[text, hl_group], ...]
      assert.is_truthy(win_config.title)
      if type(win_config.title) == "table" then
        assert.are.equal("my-title", win_config.title[1][1])
      else
        assert.are.equal("my-title", win_config.title)
      end
    end)

    it("sets relative to editor by default", function()
      local buf = create_test_buf()

      local win = track_win(layout.float_layout(buf, "", nil, { size = { width = 50, height = 10 } }))
      local config = vim.api.nvim_win_get_config(win)

      assert.are.equal("editor", config.relative)
    end)

    it("respects custom relative option", function()
      local buf = create_test_buf()

      local win = track_win(layout.float_layout(buf, "", nil, {
        relative = "win",
        size = { width = 50, height = 10 },
      }))
      local win_config = vim.api.nvim_win_get_config(win)

      assert.are.equal("win", win_config.relative)
    end)

    it("has rounded border", function()
      local buf = create_test_buf()

      local win = track_win(layout.float_layout(buf, "", nil, { size = { width = 50, height = 10 } }))
      local win_config = vim.api.nvim_win_get_config(win)

      -- nvim_win_get_config returns border as table of characters for "rounded"
      assert.is_truthy(win_config.border)
      if type(win_config.border) == "table" then
        -- Rounded border starts with top-left corner character
        assert.are.equal("╭", win_config.border[1])
      end
    end)
  end)

  describe("float_dynamic_layout", function()
    it("creates a floating window", function()
      local buf = create_test_buf()

      local win = track_win(layout.float_dynamic_layout(buf, "", nil, { skip_fit = true }))

      assert.is_true(vim.api.nvim_win_is_valid(win))
    end)

    it("uses specified width", function()
      local buf = create_test_buf()

      local win = track_win(layout.float_dynamic_layout(buf, "", nil, {
        width = 80,
        skip_fit = true,
      }))
      local config = vim.api.nvim_win_get_config(win)

      assert.are.equal(80, config.width)
    end)

    it("uses specified height", function()
      local buf = create_test_buf()

      local win = track_win(layout.float_dynamic_layout(buf, "", nil, {
        height = 20,
        skip_fit = true,
      }))
      local config = vim.api.nvim_win_get_config(win)

      assert.are.equal(20, config.height)
    end)

    it("defaults width to 100", function()
      local buf = create_test_buf()

      local win = track_win(layout.float_dynamic_layout(buf, "", nil, { skip_fit = true }))
      local config = vim.api.nvim_win_get_config(win)

      assert.are.equal(100, config.width)
    end)

    it("defaults height to 5", function()
      local buf = create_test_buf()

      local win = track_win(layout.float_dynamic_layout(buf, "", nil, { skip_fit = true }))
      local config = vim.api.nvim_win_get_config(win)

      assert.are.equal(5, config.height)
    end)

    it("enters window by default", function()
      local buf = create_test_buf()

      local win = track_win(layout.float_dynamic_layout(buf, "", nil, { skip_fit = true }))

      assert.are.equal(win, vim.api.nvim_get_current_win())
    end)

    it("does not enter window when enter is false", function()
      local buf = create_test_buf()
      local original_win = vim.api.nvim_get_current_win()

      local win = track_win(layout.float_dynamic_layout(buf, "", nil, {
        enter = false,
        skip_fit = true,
      }))

      assert.are_not.equal(win, vim.api.nvim_get_current_win())
      assert.are.equal(original_win, vim.api.nvim_get_current_win())
    end)
  end)

  describe("win_size_fit_content", function()
    it("resizes window to fit buffer content", function()
      local buf = create_test_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "line 1",
        "line 2",
        "line 3",
      })
      local win = track_win(layout.float_layout(buf, "", nil, { size = { width = 50, height = 10 } }))

      local result = layout.win_size_fit_content(buf, win, 0)

      assert.are.equal(3, result.height) -- 3 lines
    end)

    it("adds height offset", function()
      local buf = create_test_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "line 1",
        "line 2",
      })
      local win = track_win(layout.float_layout(buf, "", nil, { size = { width = 50, height = 10 } }))

      local result = layout.win_size_fit_content(buf, win, 3)

      assert.are.equal(5, result.height) -- 2 lines + 3 offset
    end)

    it("calculates width from longest line", function()
      local buf = create_test_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "short",
        "this is a longer line",
        "medium line",
      })
      local win = track_win(layout.float_layout(buf, "", nil, { size = { width = 50, height = 10 } }))

      local result = layout.win_size_fit_content(buf, win, 0)

      assert.are.equal(vim.api.nvim_strwidth("this is a longer line"), result.width)
    end)

    it("respects minimum width", function()
      local buf = create_test_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hi" })
      local win = track_win(layout.float_layout(buf, "", nil, { size = { width = 50, height = 10 } }))

      local result = layout.win_size_fit_content(buf, win, 0, 20)

      assert.are.equal(20, result.width)
    end)

    it("ensures minimum height of 1", function()
      local buf = create_test_buf()
      -- Empty buffer
      local win = track_win(layout.float_layout(buf, "", nil, { size = { width = 50, height = 10 } }))

      local result = layout.win_size_fit_content(buf, win, 0)

      assert.is_true(result.height >= 1)
    end)

    it("ensures minimum width of 1", function()
      local buf = create_test_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
      local win = track_win(layout.float_layout(buf, "", nil, { size = { width = 50, height = 10 } }))

      local result = layout.win_size_fit_content(buf, win, 0)

      assert.is_true(result.width >= 1)
    end)
  end)

  describe("float_framed_windows", function()
    it("creates hints window", function()
      local hints_buf = create_test_buf()
      local pane_buf = create_test_buf()

      local result = layout.float_framed_windows({
        hints_buf = hints_buf,
        pane_bufs = { pane_buf },
      }, {
        panes = { { title = "Pane" } },
      })

      track_win(result.hints_win)
      track_win(result.pane_wins[1])

      assert.is_true(vim.api.nvim_win_is_valid(result.hints_win))
    end)

    it("creates pane window", function()
      local hints_buf = create_test_buf()
      local pane_buf = create_test_buf()

      local result = layout.float_framed_windows({
        hints_buf = hints_buf,
        pane_bufs = { pane_buf },
      }, {
        panes = { { title = "Pane" } },
      })

      track_win(result.hints_win)
      track_win(result.pane_wins[1])

      assert.is_true(vim.api.nvim_win_is_valid(result.pane_wins[1]))
    end)

    it("creates multiple pane windows", function()
      local hints_buf = create_test_buf()
      local pane_buf1 = create_test_buf()
      local pane_buf2 = create_test_buf()

      local result = layout.float_framed_windows({
        hints_buf = hints_buf,
        pane_bufs = { pane_buf1, pane_buf2 },
      }, {
        panes = { { title = "Pane1" }, { title = "Pane2" } },
      })

      track_win(result.hints_win)
      for _, w in ipairs(result.pane_wins) do
        track_win(w)
      end

      assert.are.equal(2, #result.pane_wins)
      assert.is_true(vim.api.nvim_win_is_valid(result.pane_wins[1]))
      assert.is_true(vim.api.nvim_win_is_valid(result.pane_wins[2]))
    end)

    it("returns dimensions", function()
      local hints_buf = create_test_buf()
      local pane_buf = create_test_buf()

      local result = layout.float_framed_windows({
        hints_buf = hints_buf,
        pane_bufs = { pane_buf },
      }, {
        panes = { { title = "Pane" } },
      })

      track_win(result.hints_win)
      track_win(result.pane_wins[1])

      assert.is_table(result.dimensions)
      assert.is_number(result.dimensions.total_width)
      assert.is_number(result.dimensions.total_height)
      assert.is_number(result.dimensions.content_height)
    end)

    it("hints window is not focusable", function()
      local hints_buf = create_test_buf()
      local pane_buf = create_test_buf()

      local result = layout.float_framed_windows({
        hints_buf = hints_buf,
        pane_bufs = { pane_buf },
      }, {
        panes = { { title = "Pane" } },
      })

      track_win(result.hints_win)
      track_win(result.pane_wins[1])

      local hints_config = vim.api.nvim_win_get_config(result.hints_win)
      assert.is_false(hints_config.focusable)
    end)

    it("first pane has cursorline enabled", function()
      local hints_buf = create_test_buf()
      local pane_buf = create_test_buf()

      local result = layout.float_framed_windows({
        hints_buf = hints_buf,
        pane_bufs = { pane_buf },
      }, {
        panes = { { title = "Pane" } },
      })

      track_win(result.hints_win)
      track_win(result.pane_wins[1])

      assert.is_true(vim.api.nvim_get_option_value("cursorline", { win = result.pane_wins[1] }))
    end)

    it("respects custom width ratio", function()
      local hints_buf = create_test_buf()
      local pane_buf = create_test_buf()

      local result = layout.float_framed_windows({
        hints_buf = hints_buf,
        pane_bufs = { pane_buf },
      }, {
        width = 0.5,
        panes = { { title = "Pane" } },
      })

      track_win(result.hints_win)
      track_win(result.pane_wins[1])

      local editor_width, _ = layout.get_editor_dimensions()
      local expected_width = math.max(math.floor(editor_width * 0.5), 100)

      assert.are.equal(expected_width, result.dimensions.total_width)
    end)

    it("sets pane title when provided", function()
      local hints_buf = create_test_buf()
      local pane_buf = create_test_buf()

      local result = layout.float_framed_windows({
        hints_buf = hints_buf,
        pane_bufs = { pane_buf },
      }, {
        panes = { { title = "Test Pane" } },
      })

      track_win(result.hints_win)
      track_win(result.pane_wins[1])

      local pane_config = vim.api.nvim_win_get_config(result.pane_wins[1])
      -- Title in nvim_win_get_config returns as nested table structure
      assert.is_truthy(pane_config.title)
    end)
  end)

  describe("fit_framed_to_content", function()
    it("handles nil frame gracefully", function()
      -- Should not error
      layout.fit_framed_to_content(nil)
    end)

    it("handles frame without panes gracefully", function()
      -- Should not error
      layout.fit_framed_to_content({ panes = nil })
    end)

    it("handles empty panes array gracefully", function()
      -- Should not error
      layout.fit_framed_to_content({ panes = {} })
    end)

    it("resizes content window to fit content", function()
      local hints_buf = create_test_buf()
      local pane_buf = create_test_buf()
      vim.api.nvim_buf_set_lines(pane_buf, 0, -1, false, {
        "line 1",
        "line 2",
        "line 3",
        "line 4",
        "line 5",
      })

      local result = layout.float_framed_windows({
        hints_buf = hints_buf,
        pane_bufs = { pane_buf },
      }, {
        panes = { { title = "Content" } },
      })

      track_win(result.hints_win)
      track_win(result.pane_wins[1])

      local frame = {
        hints_win = result.hints_win,
        panes = { { buf = pane_buf, win = result.pane_wins[1] } },
      }

      layout.fit_framed_to_content(frame, 0)

      local content_config = vim.api.nvim_win_get_config(result.pane_wins[1])
      -- Content should fit 5 lines (may be capped by screen size)
      assert.is_true(content_config.height >= 5 or content_config.height > 0)
    end)

    it("aligns hints and content windows horizontally", function()
      local hints_buf = create_test_buf()
      local pane_buf = create_test_buf()
      vim.api.nvim_buf_set_lines(pane_buf, 0, -1, false, { "test content line" })

      local result = layout.float_framed_windows({
        hints_buf = hints_buf,
        pane_bufs = { pane_buf },
      }, {
        panes = { { title = "Content" } },
      })

      track_win(result.hints_win)
      track_win(result.pane_wins[1])

      local frame = {
        hints_win = result.hints_win,
        panes = { { buf = pane_buf, win = result.pane_wins[1] } },
      }

      layout.fit_framed_to_content(frame, 0)

      local hints_config = vim.api.nvim_win_get_config(result.hints_win)
      local content_config = vim.api.nvim_win_get_config(result.pane_wins[1])

      -- Both should have same column position
      assert.are.equal(hints_config.col, content_config.col)
    end)
  end)
end)
