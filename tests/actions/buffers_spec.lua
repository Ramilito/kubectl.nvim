describe("actions.buffers", function()
  local buffers

  before_each(function()
    -- Clear module cache
    package.loaded["kubectl.actions.buffers"] = nil
    package.loaded["kubectl.actions.layout"] = nil
    package.loaded["kubectl.state"] = nil

    -- Mock state module
    package.loaded["kubectl.state"] = {
      get_buffer_state = function()
        return {}
      end,
      set_buffer_selections = function() end,
      set_session = function() end,
      picker_register = function() end,
    }

    -- Mock layout module
    package.loaded["kubectl.actions.layout"] = {
      win_size_fit_content = function()
        return { width = 80, height = 20 }
      end,
      fit_framed_to_content = function() end,
      float_dynamic_layout = function(buf)
        return vim.api.nvim_open_win(buf, true, {
          relative = "editor",
          width = 40,
          height = 10,
          row = 5,
          col = 5,
        })
      end,
      set_buf_options = function() end,
      set_win_options = function() end,
    }

    buffers = require("kubectl.actions.buffers")
  end)

  after_each(function()
    -- Clean up any buffers we created
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        local name = vim.api.nvim_buf_get_name(buf)
        if name:match("^kubectl://") then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end
    end
    -- Clean up windows
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) and win ~= vim.api.nvim_get_current_win() then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end)

  describe("get_buffer_by_name", function()
    it("returns nil when buffer does not exist", function()
      local buf = buffers.get_buffer_by_name("nonexistent")
      assert.is_nil(buf)
    end)

    it("finds buffer by basename", function()
      local test_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(test_buf, "kubectl://test_buffer")

      local found = buffers.get_buffer_by_name("test_buffer")
      assert.are.equal(test_buf, found)

      vim.api.nvim_buf_delete(test_buf, { force = true })
    end)

    it("returns first matching buffer", function()
      local buf1 = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf1, "kubectl://my_buffer")

      local found = buffers.get_buffer_by_name("my_buffer")
      assert.are.equal(buf1, found)

      vim.api.nvim_buf_delete(buf1, { force = true })
    end)
  end)

  describe("get_windows_by_name", function()
    it("returns empty table when buffer does not exist", function()
      local wins = buffers.get_windows_by_name("nonexistent")
      assert.are.same({}, wins)
    end)

    it("returns empty table when buffer exists but has no windows", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, "kubectl://orphan_buffer")

      local wins = buffers.get_windows_by_name("orphan_buffer")
      assert.are.same({}, wins)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("finds windows showing the buffer", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, "kubectl://windowed_buffer")

      local win = vim.api.nvim_open_win(buf, false, {
        relative = "editor",
        width = 40,
        height = 10,
        row = 0,
        col = 0,
      })

      local wins = buffers.get_windows_by_name("windowed_buffer")
      assert.are.equal(1, #wins)
      assert.are.equal(win, wins[1])

      vim.api.nvim_win_close(win, true)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("set_content", function()
    it("sets buffer lines from content", function()
      local buf = vim.api.nvim_create_buf(false, true)

      buffers.set_content(buf, {
        content = { "line 1", "line 2", "line 3" },
      })

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.same({ "line 1", "line 2", "line 3" }, lines)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("prepends header data to content", function()
      local buf = vim.api.nvim_create_buf(false, true)

      buffers.set_content(buf, {
        header = { data = { "HEADER 1", "HEADER 2" } },
        content = { "content line" },
      })

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.same({ "HEADER 1", "HEADER 2", "content line" }, lines)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("preserves buffer when both header and content are empty", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "existing" })

      buffers.set_content(buf, {
        content = {},
      })

      -- Empty header+content returns early, preserving existing lines
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.same({ "existing" }, lines)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("handles nil header gracefully", function()
      local buf = vim.api.nvim_create_buf(false, true)

      buffers.set_content(buf, {
        content = { "just content" },
        header = nil,
      })

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.same({ "just content" }, lines)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("apply_marks", function()
    it("handles nil buffer gracefully", function()
      -- Should not error
      buffers.apply_marks(nil, {}, nil)
    end)

    it("applies content marks with row offset", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "header", "content line" })

      local marks = {
        {
          row = 0,
          start_col = 0,
          end_col = 7,
          hl_group = "Normal",
        },
      }

      buffers.apply_marks(buf, marks, { data = { "header" } })

      local ns_id = vim.api.nvim_create_namespace("__kubectl_views")
      local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, { details = true })

      -- Should have at least one mark
      assert.is_true(#extmarks >= 1)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("applies header marks at correct position", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "header line", "content" })

      local header = {
        data = { "header line" },
        marks = {
          {
            row = 0,
            start_col = 0,
            end_col = 6,
            hl_group = "Title",
          },
        },
      }

      buffers.apply_marks(buf, nil, header)

      local ns_id = vim.api.nvim_create_namespace("__kubectl_views")
      local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, { details = true })

      assert.is_true(#extmarks >= 1)
      -- First mark should be at row 0 (header row)
      assert.are.equal(0, extmarks[1][2])

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("clears previous marks before applying new ones", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line 1", "line 2" })

      -- Apply first set of marks
      buffers.apply_marks(buf, {
        { row = 0, start_col = 0, end_col = 4, hl_group = "Normal" },
      }, nil)

      -- Apply second set of marks (should replace first)
      buffers.apply_marks(buf, {
        { row = 1, start_col = 0, end_col = 4, hl_group = "Comment" },
      }, nil)

      local ns_id = vim.api.nvim_create_namespace("__kubectl_views")
      local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, { details = true })

      -- Should only have the second mark
      assert.are.equal(1, #extmarks)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("setup_buffer_marks_state", function()
    it("stores namespace and content row start in buffer state", function()
      local captured_state = {}
      package.loaded["kubectl.state"].get_buffer_state = function(bufnr)
        captured_state.bufnr = bufnr
        return captured_state
      end

      local buf = vim.api.nvim_create_buf(false, true)
      local ns_id = vim.api.nvim_create_namespace("test_ns")

      buffers.setup_buffer_marks_state(buf, ns_id, 3)

      assert.are.equal(ns_id, captured_state.ns_id)
      assert.are.equal(4, captured_state.content_row_start) -- header_row_offset + 1

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("fit_to_content", function()
    it("calls layout.win_size_fit_content with correct args", function()
      local called_with = {}
      package.loaded["kubectl.actions.layout"].win_size_fit_content = function(buf, win, offset)
        called_with = { buf = buf, win = win, offset = offset }
        return { width = 50, height = 10 }
      end

      local result = buffers.fit_to_content(1, 2, 5)

      assert.are.equal(1, called_with.buf)
      assert.are.equal(2, called_with.win)
      assert.are.equal(5, called_with.offset)
      assert.are.same({ width = 50, height = 10 }, result)
    end)

    it("uses default offset of 2", function()
      local called_with = {}
      package.loaded["kubectl.actions.layout"].win_size_fit_content = function(buf, win, offset)
        called_with.offset = offset
        return {}
      end

      buffers.fit_to_content(1, 2)

      assert.are.equal(2, called_with.offset)
    end)
  end)
end)
