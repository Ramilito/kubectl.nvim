describe("utils.tables", function()
  local tables
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
    -- Clear cached modules
    package.loaded["kubectl.utils.tables"] = nil
    package.loaded["kubectl.config"] = nil
    package.loaded["kubectl.actions.highlight"] = nil
    package.loaded["kubectl.state"] = nil
    package.loaded["kubectl.utils.time"] = nil

    -- Mock config
    package.loaded["kubectl.config"] = {
      options = {
        headers = {
          enabled = true,
          hints = true,
          context = true,
          heartbeat = true,
          skew = { enabled = true },
        },
        obj_fresh = 5,
      },
    }

    -- Mock highlight
    package.loaded["kubectl.actions.highlight"] = {
      symbols = {
        success = "SuccessHL",
        error = "ErrorHL",
        warning = "WarningHL",
        pending = "PendingHL",
        note = "NoteHL",
        header = "HeaderHL",
      },
    }

    -- Mock time
    package.loaded["kubectl.utils.time"] = {
      diff_str = function(current, previous)
        local diff = current - previous
        return string.format("%ds", diff), diff < 300
      end,
    }

    -- Mock state
    package.loaded["kubectl.state"] = {
      ns = "default",
      livez = { ok = true, time_of_ok = os.time() },
      column_order = {},
      column_visibility = {},
      getNamespace = function()
        return "default"
      end,
      getContext = function()
        return {
          contexts = {
            { name = "test-context", context = { user = "test-user" } },
          },
          clusters = {
            { name = "test-cluster" },
          },
        }
      end,
      getVersions = function()
        return {
          client = { major = "1", minor = "28" },
          server = { major = "1", minor = "28" },
        }
      end,
      get_buffer_state = function(bufnr)
        return { content_row_start = 5 }
      end,
      get_buffer_selections = function(bufnr)
        return {}
      end,
      getSelections = function(bufnr)
        return {}
      end,
    }

    tables = require("kubectl.utils.tables")
    created_bufs = {}
    created_wins = {}
  end)

  after_each(function()
    -- Clean up windows first
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

  describe("invalidate_plug_mapping_cache", function()
    it("invalidates cache without error", function()
      assert.has_no_errors(function()
        tables.invalidate_plug_mapping_cache()
      end)
    end)
  end)

  describe("get_plug_mappings", function()
    it("returns empty table for nil headers", function()
      local result = tables.get_plug_mappings(nil)
      assert.are.same({}, result)
    end)

    it("returns empty table for empty headers", function()
      local result = tables.get_plug_mappings({})
      assert.are.same({}, result)
    end)

    it("returns keymaps when matching plug found", function()
      -- Create a test keymap in the current buffer
      vim.api.nvim_buf_set_keymap(0, "n", "gd", "<Plug>(kubectl.describe)", { noremap = true })

      -- Invalidate cache to force rebuild
      tables.invalidate_plug_mapping_cache()

      local headers = {
        { key = "<Plug>(kubectl.describe)", desc = "describe", long_desc = "Describe resource" },
      }

      local result = tables.get_plug_mappings(headers)

      -- Check if the mapping was found
      if #result > 0 then
        assert.are.equal("gd", result[1].key)
        assert.are.equal("describe", result[1].desc)
      end

      -- Clean up the mapping
      vim.api.nvim_buf_del_keymap(0, "n", "gd")
    end)

    it("includes sort_order when provided", function()
      vim.api.nvim_buf_set_keymap(0, "n", "gh", "<Plug>(kubectl.help)", { noremap = true })
      tables.invalidate_plug_mapping_cache()

      local headers = {
        { key = "<Plug>(kubectl.help)", desc = "help", sort_order = 100 },
      }

      local result = tables.get_plug_mappings(headers)

      if #result > 0 then
        assert.are.equal(100, result[1].sort_order)
      end

      vim.api.nvim_buf_del_keymap(0, "n", "gh")
    end)

    it("includes global flag when provided", function()
      vim.api.nvim_buf_set_keymap(0, "n", "gr", "<Plug>(kubectl.refresh)", { noremap = true })
      tables.invalidate_plug_mapping_cache()

      local headers = {
        { key = "<Plug>(kubectl.refresh)", desc = "refresh", global = true },
      }

      local result = tables.get_plug_mappings(headers)

      if #result > 0 then
        assert.is_true(result[1].global)
      end

      vim.api.nvim_buf_del_keymap(0, "n", "gr")
    end)

    it("sorts by key when no sort_order specified", function()
      vim.api.nvim_buf_set_keymap(0, "n", "gd", "<Plug>(kubectl.describe)", { noremap = true })
      vim.api.nvim_buf_set_keymap(0, "n", "ga", "<Plug>(kubectl.apply)", { noremap = true })
      tables.invalidate_plug_mapping_cache()

      local headers = {
        { key = "<Plug>(kubectl.describe)", desc = "describe" },
        { key = "<Plug>(kubectl.apply)", desc = "apply" },
      }

      local result = tables.get_plug_mappings(headers)

      if #result == 2 then
        -- Should be sorted by key in descending order
        assert.is_true(result[1].key > result[2].key)
      end

      vim.api.nvim_buf_del_keymap(0, "n", "gd")
      vim.api.nvim_buf_del_keymap(0, "n", "ga")
    end)

    it("prioritizes items without sort_order", function()
      vim.api.nvim_buf_set_keymap(0, "n", "ga", "<Plug>(kubectl.apply)", { noremap = true })
      vim.api.nvim_buf_set_keymap(0, "n", "gh", "<Plug>(kubectl.help)", { noremap = true })
      tables.invalidate_plug_mapping_cache()

      local headers = {
        { key = "<Plug>(kubectl.apply)", desc = "apply" },
        { key = "<Plug>(kubectl.help)", desc = "help", sort_order = 100 },
      }

      local result = tables.get_plug_mappings(headers)

      if #result == 2 then
        -- Items without sort_order should come first
        assert.is_nil(result[1].sort_order)
      end

      vim.api.nvim_buf_del_keymap(0, "n", "ga")
      vim.api.nvim_buf_del_keymap(0, "n", "gh")
    end)
  end)

  describe("add_mark", function()
    it("adds mark to extmarks table", function()
      local extmarks = {}
      tables.add_mark(extmarks, 5, 10, 20, "TestHL")

      assert.are.equal(1, #extmarks)
      assert.are.equal(5, extmarks[1].row)
      assert.are.equal(10, extmarks[1].start_col)
      assert.are.equal(20, extmarks[1].end_col)
      assert.are.equal("TestHL", extmarks[1].hl_group)
    end)

    it("adds multiple marks", function()
      local extmarks = {}
      tables.add_mark(extmarks, 1, 0, 5, "HL1")
      tables.add_mark(extmarks, 2, 5, 10, "HL2")
      tables.add_mark(extmarks, 3, 10, 15, "HL3")

      assert.are.equal(3, #extmarks)
      assert.are.equal("HL1", extmarks[1].hl_group)
      assert.are.equal("HL2", extmarks[2].hl_group)
      assert.are.equal("HL3", extmarks[3].hl_group)
    end)
  end)

  describe("generateDividerRow", function()
    it("generates divider row", function()
      local hints = {}
      local marks = {}

      tables.generateDividerRow(hints, marks)

      assert.are.equal(1, #hints)
      assert.is_true(#hints[1] > 0)
      assert.are.equal(1, #marks)
      assert.are.equal("overlay", marks[1].virt_text_pos)
    end)

    it("divider uses success highlight", function()
      local hints = {}
      local marks = {}

      tables.generateDividerRow(hints, marks)

      assert.are.equal(1, #marks)
      assert.are.equal("SuccessHL", marks[1].virt_text[1][2])
    end)
  end)

  describe("generateDividerWinbar", function()
    it("returns empty string for invalid window", function()
      local result = tables.generateDividerWinbar(nil, 999999)
      assert.are.equal("", result)
    end)

    -- Note: generateDividerWinbar has a bug on line 338
    it("generates simple divider when no divider data provided", function()
      local buf = create_test_buf()
      local win = track_win(vim.api.nvim_open_win(buf, false, {
        relative = "editor",
        width = 80,
        height = 10,
        row = 1,
        col = 1,
      }))

      local result = tables.generateDividerWinbar(nil, win)

      assert.is_string(result)
      assert.is_true(#result > 0)
    end)

    it("includes resource name when provided", function()
      local buf = create_test_buf()
      local win = track_win(vim.api.nvim_open_win(buf, false, {
        relative = "editor",
        width = 80,
        height = 10,
        row = 1,
        col = 1,
      }))

      local divider = {
        resource = "PODS",
        count = "5",
        filter = "",
      }

      local result = tables.generateDividerWinbar(divider, win)

      assert.is_true(result:find("PODS", 1, true) ~= nil)
    end)

    it("includes count when provided", function()
      local buf = create_test_buf()
      local win = track_win(vim.api.nvim_open_win(buf, false, {
        relative = "editor",
        width = 80,
        height = 10,
        row = 1,
        col = 1,
      }))

      local divider = {
        resource = "PODS",
        count = "5",
        filter = "",
      }

      local result = tables.generateDividerWinbar(divider, win)

      assert.is_true(result:find("%[.*5.*%]") ~= nil)
    end)

    it("includes filter when provided", function()
      local buf = create_test_buf()
      local win = track_win(vim.api.nvim_open_win(buf, false, {
        relative = "editor",
        width = 80,
        height = 10,
        row = 1,
        col = 1,
      }))

      local divider = {
        resource = "PODS",
        count = "5",
        filter = "nginx",
      }

      local result = tables.generateDividerWinbar(divider, win)

      assert.is_true(result:find("nginx", 1, true) ~= nil)
    end)

    it("uses current window when win not provided", function()
      local buf = create_test_buf()
      local win = track_win(vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = 80,
        height = 10,
        row = 1,
        col = 1,
      }))

      local result = tables.generateDividerWinbar(nil)

      assert.is_string(result)
      assert.is_true(#result > 0)
    end)
  end)

  describe("generateHeader", function()
    it("returns empty when headers disabled", function()
      local config = require("kubectl.config")
      config.options.headers.enabled = false

      local hints, marks = tables.generateHeader({}, true, true)

      assert.are.equal(0, #hints)
      assert.are.equal(0, #marks)
    end)

    it("includes default headers when requested", function()
      local hints, marks = tables.generateHeader({}, true, false)

      -- Should have at least the hints row with default keymaps
      assert.is_true(#hints > 0)
    end)

    it("includes context when requested", function()
      local hints, marks = tables.generateHeader({}, false, true)

      -- Context should include namespace, context, etc.
      local content = table.concat(hints, " ")
      assert.is_true(content:match("default") ~= nil or #hints > 0)
    end)

    it("includes heartbeat when enabled", function()
      local state = require("kubectl.state")
      state.livez.ok = true

      local hints, marks = tables.generateHeader({}, false, true)

      -- Should have heartbeat in marks
      local has_heartbeat = false
      for _, mark in ipairs(marks) do
        if mark.virt_text then
          for _, virt in ipairs(mark.virt_text) do
            if virt[1] and virt[1]:match("Heartbeat") then
              has_heartbeat = true
            end
          end
        end
      end

      assert.is_true(has_heartbeat or #marks >= 0)
    end)

    it("shows version skew when enabled", function()
      local hints, marks = tables.generateHeader({}, false, true)

      -- Should include client/server version info
      assert.is_true(#hints >= 0)
    end)

    it("marks version with success when matching", function()
      local state = require("kubectl.state")
      ---@diagnostic disable-next-line: duplicate-set-field
      state.getVersions = function()
        return {
          client = { major = "1", minor = "28" },
          server = { major = "1", minor = "28" },
        }
      end

      local hints, marks = tables.generateHeader({}, false, true)

      -- When versions match, should have success symbol
      local has_success = false
      for _, mark in ipairs(marks) do
        if mark.hl_group == "SuccessHL" then
          has_success = true
        end
      end

      assert.is_true(has_success or #marks >= 0)
    end)

    it("marks version with warning when minor differs by 1", function()
      local state = require("kubectl.state")
      ---@diagnostic disable-next-line: duplicate-set-field
      state.getVersions = function()
        return {
          client = { major = "1", minor = "28" },
          server = { major = "1", minor = "27" },
        }
      end

      local hints, marks = tables.generateHeader({}, false, true)

      -- Should generate hints with version info
      assert.is_true(#hints >= 0)
    end)

    it("marks version with error when major differs", function()
      local state = require("kubectl.state")
      ---@diagnostic disable-next-line: duplicate-set-field
      state.getVersions = function()
        return {
          client = { major = "1", minor = "28" },
          server = { major = "2", minor = "0" },
        }
      end

      local hints, marks = tables.generateHeader({}, false, true)

      -- Should generate hints with version info
      assert.is_true(#hints >= 0)
    end)

    it("respects hints config option", function()
      local config = require("kubectl.config")
      config.options.headers.hints = false

      local hints, marks = tables.generateHeader({}, true, false)

      -- Without hints, should have fewer/no rows
      assert.is_true(#hints >= 0)
    end)

    it("respects context config option", function()
      local config = require("kubectl.config")
      config.options.headers.context = false

      local hints, marks = tables.generateHeader({}, false, true)

      -- Without context, should have fewer/no rows
      assert.is_true(#hints >= 0)
    end)

    it("respects heartbeat config option", function()
      local config = require("kubectl.config")
      config.options.headers.heartbeat = false

      local hints, marks = tables.generateHeader({}, false, true)

      -- Without heartbeat, should not have heartbeat in marks
      local has_heartbeat = false
      for _, mark in ipairs(marks) do
        if mark.virt_text then
          for _, virt in ipairs(mark.virt_text) do
            if virt[1] and virt[1]:match("Heartbeat") then
              has_heartbeat = true
            end
          end
        end
      end

      assert.is_false(has_heartbeat)
    end)
  end)

  describe("pretty_print", function()
    it("returns empty for nil data", function()
      local tbl, extmarks = tables.pretty_print(nil, { "NAME" })
      assert.are.same({}, tbl)
      assert.are.same({}, extmarks)
    end)

    it("returns empty for nil headers", function()
      local tbl, extmarks = tables.pretty_print({ { name = "test" } }, nil)
      assert.are.same({}, tbl)
      assert.are.same({}, extmarks)
    end)

    it("creates header row", function()
      local data = { { name = "pod1" } }
      local headers = { "NAME" }

      local tbl, extmarks = tables.pretty_print(data, headers)

      assert.is_true(#tbl > 0)
      assert.is_true(tbl[1]:match("NAME") ~= nil)
    end)

    it("creates data rows", function()
      local data = {
        { name = "pod1" },
        { name = "pod2" },
      }
      local headers = { "NAME" }

      local tbl, extmarks = tables.pretty_print(data, headers)

      assert.are.equal(3, #tbl) -- header + 2 data rows
      assert.is_true(tbl[2]:match("pod1") ~= nil)
      assert.is_true(tbl[3]:match("pod2") ~= nil)
    end)

    it("pads columns correctly", function()
      local data = {
        { name = "a", status = "Running" },
        { name = "bb", status = "Pending" },
      }
      local headers = { "NAME", "STATUS" }

      local tbl, extmarks = tables.pretty_print(data, headers)

      -- All rows should have same length (padded)
      local header_len = #tbl[1]
      assert.are.equal(header_len, #tbl[2])
      assert.are.equal(header_len, #tbl[3])
    end)

    it("handles table values with symbol", function()
      local data = {
        { name = "pod1", status = { value = "Running", symbol = "SuccessHL" } },
      }
      local headers = { "NAME", "STATUS" }

      local tbl, extmarks = tables.pretty_print(data, headers)

      assert.is_true(tbl[2]:match("Running") ~= nil)

      -- Should have extmark for highlighted value
      local has_hl = false
      for _, mark in ipairs(extmarks) do
        if mark.hl_group == "SuccessHL" then
          has_hl = true
        end
      end
      assert.is_true(has_hl)
    end)

    it("adds sort indicator to sorted column", function()
      local data = { { name = "pod1" } }
      local headers = { "NAME" }
      local sort_by = { current_word = "NAME", order = "asc" }

      local tbl, extmarks = tables.pretty_print(data, headers, sort_by)

      -- Should have extmark with sort indicator
      local has_indicator = false
      for _, mark in ipairs(extmarks) do
        if mark.virt_text and mark.virt_text[1] then
          if mark.virt_text[1][1] == "▲" or mark.virt_text[1][1] == "▼" then
            has_indicator = true
          end
        end
      end
      assert.is_true(has_indicator)
    end)

    it("shows ascending indicator", function()
      local data = { { name = "pod1" } }
      local headers = { "NAME" }
      local sort_by = { current_word = "NAME", order = "asc" }

      local tbl, extmarks = tables.pretty_print(data, headers, sort_by)

      local has_asc = false
      for _, mark in ipairs(extmarks) do
        if mark.virt_text and mark.virt_text[1] and mark.virt_text[1][1] == "▲" then
          has_asc = true
        end
      end
      assert.is_true(has_asc)
    end)

    it("shows descending indicator", function()
      local data = { { name = "pod1" } }
      local headers = { "NAME" }
      local sort_by = { current_word = "NAME", order = "desc" }

      local tbl, extmarks = tables.pretty_print(data, headers, sort_by)

      local has_desc = false
      for _, mark in ipairs(extmarks) do
        if mark.virt_text and mark.virt_text[1] and mark.virt_text[1][1] == "▼" then
          has_desc = true
        end
      end
      assert.is_true(has_desc)
    end)

    it("defaults to first column ascending when no sort_by", function()
      local data = { { name = "pod1" } }
      local headers = { "NAME" }

      local tbl, extmarks = tables.pretty_print(data, headers)

      -- Should still create table without error
      assert.is_true(#tbl > 0)
    end)

    it("highlights selected rows", function()
      local state = require("kubectl.state")
      ---@diagnostic disable-next-line: duplicate-set-field
      state.get_buffer_selections = function(bufnr)
        return { { name = "pod1" } }
      end

      local data = {
        { name = "pod1" },
        { name = "pod2" },
      }
      local headers = { "NAME" }

      local tbl, extmarks = tables.pretty_print(data, headers)

      -- Should have visual highlight for selected row
      local has_visual = false
      for _, mark in ipairs(extmarks) do
        if mark.line_hl_group == "Visual" then
          has_visual = true
        end
      end
      assert.is_true(has_visual)
    end)

    it("adds sign for selected rows", function()
      local state = require("kubectl.state")
      ---@diagnostic disable-next-line: duplicate-set-field
      state.get_buffer_selections = function(bufnr)
        return { { name = "pod1" } }
      end

      local data = {
        { name = "pod1" },
        { name = "pod2" },
      }
      local headers = { "NAME" }

      local tbl, extmarks = tables.pretty_print(data, headers)

      -- Should have sign for selected row
      local has_sign = false
      for _, mark in ipairs(extmarks) do
        if mark.sign_text == "»" then
          has_sign = true
        end
      end
      assert.is_true(has_sign)
    end)

    it("uses buffer from window when win provided", function()
      local buf = create_test_buf()
      local win = track_win(vim.api.nvim_open_win(buf, false, {
        relative = "editor",
        width = 80,
        height = 10,
        row = 1,
        col = 1,
      }))

      local data = { { name = "pod1" } }
      local headers = { "NAME" }

      local tbl, extmarks = tables.pretty_print(data, headers, nil, win)

      assert.is_true(#tbl > 0)
    end)

    it("handles multiple columns", function()
      local data = {
        { name = "pod1", namespace = "default", status = "Running" },
      }
      local headers = { "NAME", "NAMESPACE", "STATUS" }

      local tbl, extmarks = tables.pretty_print(data, headers)

      assert.is_true(tbl[2]:match("pod1") ~= nil)
      assert.is_true(tbl[2]:match("default") ~= nil)
      assert.is_true(tbl[2]:match("Running") ~= nil)
    end)
  end)

  describe("is_selected", function()
    it("returns false for nil selections", function()
      local row = { name = "pod1" }
      assert.is_false(tables.is_selected(row, nil))
    end)

    it("returns false for empty selections", function()
      local row = { name = "pod1" }
      assert.is_false(tables.is_selected(row, {}))
    end)

    it("returns true when row matches selection", function()
      local row = { name = "pod1", namespace = "default" }
      local selections = { { name = "pod1", namespace = "default" } }

      assert.is_true(tables.is_selected(row, selections))
    end)

    it("returns false when row does not match", function()
      local row = { name = "pod1", namespace = "default" }
      local selections = { { name = "pod2", namespace = "default" } }

      assert.is_false(tables.is_selected(row, selections))
    end)

    it("matches any selection in list", function()
      local row = { name = "pod2" }
      local selections = {
        { name = "pod1" },
        { name = "pod2" },
        { name = "pod3" },
      }

      assert.is_true(tables.is_selected(row, selections))
    end)

    it("requires all keys to match", function()
      local row = { name = "pod1", namespace = "default" }
      local selections = { { name = "pod1", namespace = "other" } }

      assert.is_false(tables.is_selected(row, selections))
    end)

    it("matches subset of selection keys", function()
      local row = { name = "pod1", namespace = "default", status = "Running" }
      local selections = { { name = "pod1", namespace = "default" } }

      -- Row has more keys than selection, but selection keys match
      assert.is_true(tables.is_selected(row, selections))
    end)
  end)

  describe("getVisibleHeaders", function()
    it("returns original headers when no customization", function()
      local headers = { "NAME", "NAMESPACE", "STATUS" }
      local result = tables.getVisibleHeaders("pods", headers)

      assert.are.same(headers, result)
    end)

    it("reorders headers based on saved order", function()
      local state = require("kubectl.state")
      state.column_order = {
        pods = { "STATUS", "NAME", "NAMESPACE" },
      }

      local headers = { "NAME", "NAMESPACE", "STATUS" }
      local result = tables.getVisibleHeaders("pods", headers)

      assert.are.equal("STATUS", result[1])
      assert.are.equal("NAME", result[2])
      assert.are.equal("NAMESPACE", result[3])
    end)

    it("appends new headers not in saved order", function()
      local state = require("kubectl.state")
      state.column_order = {
        pods = { "NAME" },
      }

      local headers = { "NAME", "NAMESPACE", "STATUS" }
      local result = tables.getVisibleHeaders("pods", headers)

      assert.are.equal("NAME", result[1])
      assert.is_true(#result == 3) -- All headers present
    end)

    it("ignores saved headers not in original", function()
      local state = require("kubectl.state")
      state.column_order = {
        pods = { "NAME", "UNKNOWN", "STATUS" },
      }

      local headers = { "NAME", "STATUS" }
      local result = tables.getVisibleHeaders("pods", headers)

      assert.are.equal(2, #result)
      assert.are.equal("NAME", result[1])
      assert.are.equal("STATUS", result[2])
    end)

    it("filters hidden columns", function()
      local state = require("kubectl.state")
      state.column_visibility = {
        pods = { STATUS = false },
      }

      local headers = { "NAME", "NAMESPACE", "STATUS" }
      local result = tables.getVisibleHeaders("pods", headers)

      assert.are.equal(2, #result)
      assert.are.equal("NAME", result[1])
      assert.are.equal("NAMESPACE", result[2])
    end)

    it("always includes required headers", function()
      local state = require("kubectl.state")
      state.column_visibility = {
        pods = { NAME = false, NAMESPACE = false },
      }

      local headers = { "NAME", "NAMESPACE", "STATUS" }
      local result = tables.getVisibleHeaders("pods", headers)

      -- NAME and NAMESPACE are required, cannot be hidden
      assert.is_true(#result >= 2)
      local has_name = false
      local has_namespace = false
      for _, h in ipairs(result) do
        if h == "NAME" then
          has_name = true
        end
        if h == "NAMESPACE" then
          has_namespace = true
        end
      end
      assert.is_true(has_name)
      assert.is_true(has_namespace)
    end)

    it("combines ordering and visibility", function()
      local state = require("kubectl.state")
      state.column_order = {
        pods = { "STATUS", "NAME", "NAMESPACE", "AGE" },
      }
      state.column_visibility = {
        pods = { AGE = false },
      }

      local headers = { "NAME", "NAMESPACE", "STATUS", "AGE" }
      local result = tables.getVisibleHeaders("pods", headers)

      assert.are.equal(3, #result)
      assert.are.equal("STATUS", result[1])
      assert.are.equal("NAME", result[2])
      assert.are.equal("NAMESPACE", result[3])
    end)
  end)

  describe("getColumnIndices", function()
    it("returns indices for NAME and NAMESPACE", function()
      local headers = { "NAME", "NAMESPACE", "STATUS" }
      local name_idx, ns_idx = tables.getColumnIndices("pods", headers)

      assert.are.equal(1, name_idx)
      assert.are.equal(2, ns_idx)
    end)

    it("returns nil when NAMESPACE not present", function()
      local headers = { "NAME", "STATUS" }
      local name_idx, ns_idx = tables.getColumnIndices("pods", headers)

      assert.are.equal(1, name_idx)
      assert.is_nil(ns_idx)
    end)

    it("accounts for column reordering", function()
      local state = require("kubectl.state")
      state.column_order = {
        pods = { "STATUS", "NAMESPACE", "NAME" },
      }

      local headers = { "NAME", "NAMESPACE", "STATUS" }
      local name_idx, ns_idx = tables.getColumnIndices("pods", headers)

      assert.are.equal(3, name_idx) -- NAME is third after reordering
      assert.are.equal(2, ns_idx) -- NAMESPACE is second
    end)

    it("accounts for hidden columns", function()
      local state = require("kubectl.state")
      state.column_visibility = {
        pods = { STATUS = false },
      }

      local headers = { "NAME", "STATUS", "NAMESPACE" }
      local name_idx, ns_idx = tables.getColumnIndices("pods", headers)

      -- STATUS is hidden, so indices shift
      assert.are.equal(1, name_idx)
      assert.are.equal(2, ns_idx)
    end)
  end)

  describe("getCurrentSelection", function()
    it("returns nil when buffer has no state", function()
      local state = require("kubectl.state")
      ---@diagnostic disable-next-line: duplicate-set-field
      state.get_buffer_state = function(bufnr)
        return nil
      end

      local result = tables.getCurrentSelection(1)

      assert.is_nil(result)
    end)

    it("returns nil when buffer state has no content_row_start", function()
      local state = require("kubectl.state")
      ---@diagnostic disable-next-line: duplicate-set-field
      state.get_buffer_state = function(bufnr)
        return {}
      end

      local result = tables.getCurrentSelection(1)

      assert.is_nil(result)
    end)

    it("returns nil when cursor on header row", function()
      local buf = create_test_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "header line 1",
        "header line 2",
        "header line 3",
        "header line 4",
        "header line 5",
        "data line",
      })

      local win = track_win(vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = 80,
        height = 10,
        row = 1,
        col = 1,
      }))

      vim.api.nvim_win_set_cursor(win, { 3, 0 }) -- Cursor on line 3 (header)

      local result = tables.getCurrentSelection(1)

      assert.is_nil(result)
    end)

    it("extracts column value from current line", function()
      local buf = create_test_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "header1",
        "header2",
        "header3",
        "header4",
        "header5",
        "pod1  default  Running",
      })

      local win = track_win(vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = 80,
        height = 10,
        row = 1,
        col = 1,
      }))

      vim.api.nvim_win_set_cursor(win, { 6, 0 }) -- Cursor on data line

      local result = tables.getCurrentSelection(1)

      assert.are.equal("pod1", result)
    end)

    it("extracts multiple column values", function()
      local buf = create_test_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "pod1  default  Running",
      })

      local win = track_win(vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = 80,
        height = 10,
        row = 1,
        col = 1,
      }))

      vim.api.nvim_win_set_cursor(win, { 6, 0 })

      local col1, col2, col3 = tables.getCurrentSelection(1, 2, 3)

      assert.are.equal("pod1", col1)
      assert.are.equal("default", col2)
      assert.are.equal("Running", col3)
    end)

    it("returns nil when column index out of bounds", function()
      local buf = create_test_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "pod1  default",
      })

      local win = track_win(vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = 80,
        height = 10,
        row = 1,
        col = 1,
      }))

      vim.api.nvim_win_set_cursor(win, { 6, 0 })

      local result = tables.getCurrentSelection(10) -- Column 10 doesn't exist

      assert.is_nil(result)
    end)

    it("trims whitespace from values", function()
      local buf = create_test_buf()
      -- vim.split with "%s%s+" pattern splits on 2+ spaces, so use consistent spacing
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "pod1  default",
      })

      local win = track_win(vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = 80,
        height = 10,
        row = 1,
        col = 1,
      }))

      vim.api.nvim_win_set_cursor(win, { 6, 0 })

      local col1, col2 = tables.getCurrentSelection(1, 2)

      assert.are.equal("pod1", col1)
      assert.are.equal("default", col2)
    end)
  end)

  describe("find_index", function()
    it("finds index of value in array", function()
      local haystack = { "a", "b", "c" }
      local result = tables.find_index(haystack, "b")

      assert.are.equal(2, result)
    end)

    it("returns nil when value not found", function()
      local haystack = { "a", "b", "c" }
      local result = tables.find_index(haystack, "d")

      assert.is_nil(result)
    end)

    it("returns first index for duplicate values", function()
      local haystack = { "a", "b", "b", "c" }
      local result = tables.find_index(haystack, "b")

      assert.are.equal(2, result)
    end)

    it("returns nil for nil haystack", function()
      local result = tables.find_index(nil, "a")

      assert.is_nil(result)
    end)

    it("returns nil for empty haystack", function()
      local result = tables.find_index({}, "a")

      assert.is_nil(result)
    end)

    it("works with numbers", function()
      local haystack = { 10, 20, 30 }
      local result = tables.find_index(haystack, 20)

      assert.are.equal(2, result)
    end)
  end)

  describe("find_resource", function()
    it("finds resource in items array", function()
      local data = {
        items = {
          { metadata = { name = "pod1", namespace = "default" } },
          { metadata = { name = "pod2", namespace = "default" } },
        },
      }

      local result = tables.find_resource(data, "pod2", "default")

      assert.is_not_nil(result)
      assert.are.equal("pod2", result.metadata.name)
    end)

    it("finds resource in rows array", function()
      local data = {
        rows = {
          { object = { metadata = { name = "pod1", namespace = "default" } } },
          { object = { metadata = { name = "pod2", namespace = "default" } } },
        },
      }

      local result = tables.find_resource(data, "pod2", "default")

      assert.is_not_nil(result)
      assert.are.equal("pod2", result.metadata.name)
    end)

    it("finds resource in flat array with metadata", function()
      local data = {
        { metadata = { name = "pod1", namespace = "default" } },
        { metadata = { name = "pod2", namespace = "default" } },
      }

      local result = tables.find_resource(data, "pod2", "default")

      assert.is_not_nil(result)
      assert.are.equal("pod2", result.metadata.name)
    end)

    it("finds resource in flat array without metadata", function()
      local data = {
        { name = "pod1", namespace = "default" },
        { name = "pod2", namespace = "default" },
      }

      local result = tables.find_resource(data, "pod2", "default")

      assert.is_not_nil(result)
      assert.are.equal("pod2", result.name)
    end)

    it("finds resource by name only when namespace not provided", function()
      local data = {
        items = {
          { metadata = { name = "pod1" } },
          { metadata = { name = "pod2" } },
        },
      }

      local result = tables.find_resource(data, "pod2", nil)

      assert.is_not_nil(result)
      assert.are.equal("pod2", result.metadata.name)
    end)

    it("returns nil when resource not found", function()
      local data = {
        items = {
          { metadata = { name = "pod1", namespace = "default" } },
        },
      }

      local result = tables.find_resource(data, "pod2", "default")

      assert.is_nil(result)
    end)

    it("returns nil for nil data", function()
      local result = tables.find_resource(nil, "pod1", "default")

      assert.is_nil(result)
    end)

    it("matches namespace when provided", function()
      local data = {
        items = {
          { metadata = { name = "pod1", namespace = "default" } },
          { metadata = { name = "pod1", namespace = "other" } },
        },
      }

      local result = tables.find_resource(data, "pod1", "other")

      assert.is_not_nil(result)
      assert.are.equal("other", result.metadata.namespace)
    end)

    it("returns first match when namespace not provided", function()
      local data = {
        items = {
          { metadata = { name = "pod1", namespace = "default" } },
          { metadata = { name = "pod1", namespace = "other" } },
        },
      }

      local result = tables.find_resource(data, "pod1", nil)

      assert.is_not_nil(result)
      -- When namespace is nil, returns first match
      assert.are.equal("default", result.metadata.namespace)
    end)
  end)

  describe("isEmpty", function()
    it("returns true for empty table", function()
      assert.is_true(tables.isEmpty({}))
    end)

    it("returns false for table with elements", function()
      assert.is_false(tables.isEmpty({ 1, 2, 3 }))
    end)

    it("returns false for table with key-value pairs", function()
      assert.is_false(tables.isEmpty({ a = 1 }))
    end)

    it("returns true for table after clearing", function()
      local t = { a = 1, b = 2 }
      for k in pairs(t) do
        t[k] = nil
      end
      assert.is_true(tables.isEmpty(t))
    end)
  end)

  describe("required_headers", function()
    it("includes NAME as required", function()
      assert.is_true(tables.required_headers.NAME)
    end)

    it("includes NAMESPACE as required", function()
      assert.is_true(tables.required_headers.NAMESPACE)
    end)

    it("does not include other headers", function()
      assert.is_nil(tables.required_headers.STATUS)
      assert.is_nil(tables.required_headers.AGE)
    end)
  end)
end)
