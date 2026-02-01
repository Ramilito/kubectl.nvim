local grid

describe("utils.grid", function()
  before_each(function()
    -- Clear module caches
    package.loaded["kubectl.utils.grid"] = nil
    package.loaded["kubectl.actions.highlight"] = nil

    -- Mock highlight module
    package.loaded["kubectl.actions.highlight"] = {
      symbols = {
        note = "KubectlNote",
        success = "KubectlSuccess",
        header = "KubectlHeader",
      },
    }

    grid = require("kubectl.utils.grid")
  end)

  describe("_pad_string", function()
    it("pads string to specified width", function()
      assert.are.equal("hello     ", grid._pad_string("hello", 10))
    end)

    it("returns original string if already at width", function()
      assert.are.equal("hello", grid._pad_string("hello", 5))
    end)

    it("handles empty string", function()
      assert.are.equal("     ", grid._pad_string("", 5))
    end)

    it("handles zero width", function()
      assert.are.equal("hello", grid._pad_string("hello", 0))
    end)

    it("handles width less than string length", function()
      -- string.rep with negative count returns empty string
      assert.are.equal("hello", grid._pad_string("hello", 3))
    end)
  end)

  describe("_section_widths", function()
    it("calculates width from name and value", function()
      local rows = {
        status = {
          { name = "Running", value = "5" },
        },
      }
      local grid_layout = { { "status" } }

      local widths = grid._section_widths(rows, grid_layout)

      -- "Running" (7) + " " (1) + "5" (1) = 9
      assert.are.equal(9, widths.status)
    end)

    it("returns max width across multiple rows", function()
      local rows = {
        status = {
          { name = "Running", value = "5" },
          { name = "Pending", value = "123" },
        },
      }
      local grid_layout = { { "status" } }

      local widths = grid._section_widths(rows, grid_layout)

      -- "Pending" (7) + " " (1) + "123" (3) = 11
      assert.are.equal(11, widths.status)
    end)

    it("handles multiple sections", function()
      local rows = {
        col1 = {
          { name = "A", value = "1" },
        },
        col2 = {
          { name = "LongerName", value = "999" },
        },
      }
      local grid_layout = { { "col1", "col2" } }

      local widths = grid._section_widths(rows, grid_layout)

      assert.are.equal(3, widths.col1) -- "A" + " " + "1"
      assert.are.equal(14, widths.col2) -- "LongerName" + " " + "999"
    end)

    it("returns empty table for empty rows", function()
      local widths = grid._section_widths({}, { { "status" } })
      assert.are.same({}, widths)
    end)

    it("handles missing section in rows", function()
      local rows = {
        other = {
          { name = "X", value = "1" },
        },
      }
      local grid_layout = { { "status" } }

      local widths = grid._section_widths(rows, grid_layout)

      assert.is_nil(widths.status)
    end)

    it("skips rows without name or value", function()
      local rows = {
        status = {
          { name = "Valid", value = "1" },
          { name = "NoValue" },
          { value = "NoName" },
          {},
        },
      }
      local grid_layout = { { "status" } }

      local widths = grid._section_widths(rows, grid_layout)

      -- Only "Valid" + " " + "1" = 7 should be counted
      assert.are.equal(7, widths.status)
    end)
  end)

  describe("_calculate_extra_padding", function()
    -- Note: This function modifies widths in-place and depends on window width
    -- Testing is limited since it requires a real Neovim window

    it("returns 0 for nil columns", function()
      local result = grid._calculate_extra_padding(nil, {})
      assert.are.equal(0, result)
    end)

    it("returns 0 for nil widths", function()
      local result = grid._calculate_extra_padding({ "col1" }, nil)
      assert.are.equal(0, result)
    end)
  end)

  describe("pretty_print", function()
    it("returns empty tables for nil data", function()
      local layout, extmarks = grid.pretty_print(nil, {})
      assert.are.same({}, layout)
      assert.are.same({}, extmarks)
    end)

    it("handles empty data when sections reference missing keys", function()
      -- When data is empty but sections reference keys, the code errors
      -- This documents current behavior - data must contain the sections
      assert.has_error(function()
        grid.pretty_print({}, { { "section1" } })
      end)
    end)

    it("formats single section with single item", function()
      local data = {
        pods = {
          { name = "Running", value = "3", symbol = "KubectlSuccess" },
        },
      }
      local sections = { { "pods" } }

      local layout, extmarks = grid.pretty_print(data, sections)

      assert.is_table(layout)
      assert.is_true(#layout > 0)
      -- Should have layout lines
      assert.is_string(layout[1])

      assert.is_table(extmarks)
      assert.is_true(#extmarks > 0)
    end)

    it("formats multiple items in a section", function()
      local data = {
        status = {
          { name = "Running", value = "5", symbol = "KubectlSuccess" },
          { name = "Pending", value = "2", symbol = "KubectlWarning" },
          { name = "Failed", value = "1", symbol = "KubectlError" },
        },
      }
      local sections = { { "status" } }

      local layout, extmarks = grid.pretty_print(data, sections)

      assert.is_table(layout)
      -- Should contain header row and data rows
      local non_empty_lines = 0
      for _, line in ipairs(layout) do
        if line ~= "" then
          non_empty_lines = non_empty_lines + 1
        end
      end
      -- At least header + 3 data rows
      assert.is_true(non_empty_lines >= 4)
    end)

    it("formats multiple sections in same grid row", function()
      local data = {
        pods = {
          { name = "Running", value = "3", symbol = "KubectlSuccess" },
        },
        services = {
          { name = "Active", value = "2", symbol = "KubectlSuccess" },
        },
      }
      local sections = { { "pods", "services" } }

      local layout, extmarks = grid.pretty_print(data, sections)

      assert.is_table(layout)
      -- Header should contain both column names
      local found_header = false
      for _, line in ipairs(layout) do
        if line:match("pods") and line:match("services") then
          found_header = true
          break
        end
      end
      assert.is_true(found_header, "Header should contain both column names")
    end)

    it("formats multiple grid rows (separate sections)", function()
      local data = {
        pods = {
          { name = "Running", value = "3", symbol = "KubectlSuccess" },
        },
        nodes = {
          { name = "Ready", value = "2", symbol = "KubectlSuccess" },
        },
      }
      local sections = {
        { "pods" },
        { "nodes" },
      }

      local layout, extmarks = grid.pretty_print(data, sections)

      assert.is_table(layout)
      -- Should have 2 separate header groups
      local header_count = 0
      for _, mark in ipairs(extmarks) do
        if mark.hl_group == "KubectlHeader" then
          header_count = header_count + 1
        end
      end
      assert.are.equal(2, header_count, "Should have 2 header rows")
    end)

    it("handles sections with different item counts", function()
      local data = {
        col1 = {
          { name = "Item1", value = "1", symbol = "KubectlSuccess" },
          { name = "Item2", value = "2", symbol = "KubectlSuccess" },
          { name = "Item3", value = "3", symbol = "KubectlSuccess" },
        },
        col2 = {
          { name = "ItemA", value = "A", symbol = "KubectlSuccess" },
        },
      }
      local sections = { { "col1", "col2" } }

      local layout, extmarks = grid.pretty_print(data, sections)

      assert.is_table(layout)
      -- Should handle uneven columns without error
      assert.is_true(#layout > 0)
    end)

    it("generates extmarks for item names with note highlight", function()
      local data = {
        status = {
          { name = "Running", value = "5", symbol = "KubectlSuccess" },
        },
      }
      local sections = { { "status" } }

      local _, extmarks = grid.pretty_print(data, sections)

      -- Find extmark for name highlight
      local has_note_mark = false
      for _, mark in ipairs(extmarks) do
        if mark.hl_group == "KubectlNote" then
          has_note_mark = true
          break
        end
      end
      assert.is_true(has_note_mark, "Should have extmark with note highlight for item name")
    end)

    it("generates extmarks for item values with symbol highlight", function()
      local data = {
        status = {
          { name = "Running", value = "5", symbol = "KubectlCustomSymbol" },
        },
      }
      local sections = { { "status" } }

      local _, extmarks = grid.pretty_print(data, sections)

      -- Find extmark for value highlight using the item's symbol
      local has_symbol_mark = false
      for _, mark in ipairs(extmarks) do
        if mark.hl_group == "KubectlCustomSymbol" then
          has_symbol_mark = true
          break
        end
      end
      assert.is_true(has_symbol_mark, "Should have extmark with item's symbol highlight for value")
    end)

    it("generates header extmarks", function()
      local data = {
        pods = {
          { name = "Running", value = "3", symbol = "KubectlSuccess" },
        },
      }
      local sections = { { "pods" } }

      local _, extmarks = grid.pretty_print(data, sections)

      local has_header_mark = false
      for _, mark in ipairs(extmarks) do
        if mark.hl_group == "KubectlHeader" then
          has_header_mark = true
          break
        end
      end
      assert.is_true(has_header_mark, "Should have header extmark")
    end)

    it("generates separator line extmarks with virtual text", function()
      local data = {
        pods = {
          { name = "Running", value = "3", symbol = "KubectlSuccess" },
        },
      }
      local sections = { { "pods" } }

      local _, extmarks = grid.pretty_print(data, sections)

      local has_virt_text = false
      for _, mark in ipairs(extmarks) do
        if mark.virt_text then
          has_virt_text = true
          -- Virtual text should contain dash character for separator
          assert.is_table(mark.virt_text)
          assert.is_true(#mark.virt_text > 0)
          break
        end
      end
      assert.is_true(has_virt_text, "Should have virtual text extmarks for separators")
    end)

    it("handles empty section in data gracefully", function()
      local data = {
        pods = {},
        services = {
          { name = "Active", value = "2", symbol = "KubectlSuccess" },
        },
      }
      local sections = { { "pods", "services" } }

      -- Should not error
      local layout, extmarks = grid.pretty_print(data, sections)
      assert.is_table(layout)
      assert.is_table(extmarks)
    end)

    it("errors when section referenced but missing in data", function()
      local data = {
        services = {
          { name = "Active", value = "2", symbol = "KubectlSuccess" },
        },
      }
      -- pods is not in data but is in sections - this causes an error
      local sections = { { "pods", "services" } }

      -- Current behavior: errors when accessing missing section
      assert.has_error(function()
        grid.pretty_print(data, sections)
      end)
    end)

    it("uses pipe separator between columns", function()
      local data = {
        col1 = {
          { name = "Item", value = "1", symbol = "KubectlSuccess" },
        },
        col2 = {
          { name = "Other", value = "2", symbol = "KubectlSuccess" },
        },
      }
      local sections = { { "col1", "col2" } }

      local layout, _ = grid.pretty_print(data, sections)

      -- Find a data row and check for pipe separator
      local has_pipe = false
      for _, line in ipairs(layout) do
        if line:match("⎪") then
          has_pipe = true
          break
        end
      end
      assert.is_true(has_pipe, "Should use pipe separator between columns")
    end)

    it("formats item as 'name (value)'", function()
      local data = {
        status = {
          { name = "Running", value = "5", symbol = "KubectlSuccess" },
        },
      }
      local sections = { { "status" } }

      local layout, _ = grid.pretty_print(data, sections)

      local found_format = false
      for _, line in ipairs(layout) do
        if line:match("Running %(5%)") then
          found_format = true
          break
        end
      end
      assert.is_true(found_format, "Should format items as 'name (value)'")
    end)
  end)
end)
