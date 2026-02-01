describe("utils.time", function()
  -- Load the module fresh for each test to reset config state
  local time_utils

  before_each(function()
    -- Clear cached modules to get fresh state
    package.loaded["kubectl.utils.time"] = nil
    package.loaded["kubectl.config"] = nil
    package.loaded["kubectl.actions.highlight"] = nil

    -- Mock the config module
    package.loaded["kubectl.config"] = {
      options = {
        obj_fresh = 5, -- 5 minutes
      },
    }

    -- Mock the highlight module
    package.loaded["kubectl.actions.highlight"] = {
      symbols = {
        success = "✓",
      },
    }

    time_utils = require("kubectl.utils.time")
  end)

  describe("diff_str", function()
    it("formats seconds correctly", function()
      local diff_str, is_fresh = time_utils.diff_str(100, 55)
      assert.are.equal("0m45s", diff_str)
      assert.is_true(is_fresh)
    end)

    it("formats minutes and seconds correctly", function()
      local diff_str, is_fresh = time_utils.diff_str(1000, 100)
      assert.are.equal("15m0s", diff_str)
      assert.is_false(is_fresh) -- 15 minutes > 5 minutes fresh threshold
    end)

    it("formats hours and minutes correctly", function()
      local diff_str, _ = time_utils.diff_str(10000, 0)
      assert.are.equal("2h46m", diff_str)
    end)

    it("formats days and hours correctly", function()
      local diff_str, _ = time_utils.diff_str(100000, 0)
      assert.are.equal("1d3h", diff_str)
    end)

    it("formats many days correctly", function()
      local diff_str, _ = time_utils.diff_str(1000000, 0)
      assert.are.equal("11d", diff_str)
    end)

    it("formats years and days correctly", function()
      local diff_str, _ = time_utils.diff_str(40000000, 0)
      assert.are.equal("1y97d", diff_str)
    end)

    it("returns fresh=true for times under threshold", function()
      local _, is_fresh = time_utils.diff_str(100, 0) -- ~1.6 minutes
      assert.is_true(is_fresh)
    end)

    it("returns fresh=false for times over threshold", function()
      local _, is_fresh = time_utils.diff_str(600, 0) -- 10 minutes
      assert.is_false(is_fresh)
    end)

    it("handles zero difference", function()
      local diff_str, is_fresh = time_utils.diff_str(100, 100)
      assert.are.equal("0m0s", diff_str)
      assert.is_true(is_fresh)
    end)
  end)
end)
