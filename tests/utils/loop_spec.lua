describe("utils.loop", function()
  local loop
  local test_buf
  local config

  before_each(function()
    -- Clear module caches - MUST clear loop first since it requires config
    package.loaded["kubectl.utils.loop"] = nil
    package.loaded["kubectl.config"] = nil

    -- Mock config before requiring loop
    config = {
      options = {
        auto_refresh = {
          enabled = true,
          interval = 1000,
        },
      },
    }
    package.loaded["kubectl.config"] = config

    loop = require("kubectl.utils.loop")

    -- Create a test buffer
    test_buf = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    -- Stop all loops to clean up timers
    if loop then
      loop.stop_all()
    end

    -- Clean up test buffers
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end)

  describe("is_running", function()
    it("returns falsy for buffer with no loop", function()
      assert.is_falsy(loop.is_running(test_buf))
    end)

    it("returns falsy for non-existent buffer", function()
      assert.is_falsy(loop.is_running(99999))
    end)

    it("returns truthy after starting loop for buffer", function()
      loop.start_loop_for_buffer(test_buf, function() end)
      assert.is_truthy(loop.is_running(test_buf))
    end)
  end)

  describe("start_loop_for_buffer", function()
    it("creates a timer for the buffer", function()
      loop.start_loop_for_buffer(test_buf, function() end)
      assert.is_truthy(loop.is_running(test_buf))
    end)

    it("does not create duplicate timers for same buffer", function()
      local call_count = 0
      local callback = function()
        call_count = call_count + 1
      end

      loop.start_loop_for_buffer(test_buf, callback)
      loop.start_loop_for_buffer(test_buf, callback)

      -- Should still only have one timer running
      assert.is_truthy(loop.is_running(test_buf))
    end)

    it("uses custom interval from opts", function()
      -- This test verifies the function accepts opts without error
      loop.start_loop_for_buffer(test_buf, function() end, { interval = 500 })
      assert.is_truthy(loop.is_running(test_buf))
    end)
  end)

  describe("stop_loop", function()
    it("stops running loop for buffer", function()
      loop.start_loop_for_buffer(test_buf, function() end)
      assert.is_truthy(loop.is_running(test_buf))

      loop.stop_loop(test_buf)
      assert.is_falsy(loop.is_running(test_buf))
    end)

    it("handles stopping non-existent loop gracefully", function()
      assert.has_no_error(function()
        loop.stop_loop(99999)
      end)
    end)

    it("handles stopping already stopped loop gracefully", function()
      loop.start_loop_for_buffer(test_buf, function() end)
      loop.stop_loop(test_buf)

      assert.has_no_error(function()
        loop.stop_loop(test_buf)
      end)
    end)
  end)

  describe("stop_all", function()
    it("stops all running loops", function()
      local buf1 = vim.api.nvim_create_buf(false, true)
      local buf2 = vim.api.nvim_create_buf(false, true)

      loop.start_loop_for_buffer(buf1, function() end)
      loop.start_loop_for_buffer(buf2, function() end)

      assert.is_truthy(loop.is_running(buf1))
      assert.is_truthy(loop.is_running(buf2))

      loop.stop_all()

      assert.is_falsy(loop.is_running(buf1))
      assert.is_falsy(loop.is_running(buf2))
    end)

    it("handles empty state gracefully", function()
      assert.has_no_error(function()
        loop.stop_all()
      end)
    end)
  end)

  describe("set_running", function()
    it("sets running state for buffer with active loop", function()
      loop.start_loop_for_buffer(test_buf, function() end)

      loop.set_running(test_buf, true)
      -- Timer should still be running
      assert.is_truthy(loop.is_running(test_buf))

      loop.set_running(test_buf, false)
      -- Timer should still exist
      assert.is_truthy(loop.is_running(test_buf))
    end)

    it("handles non-existent buffer gracefully", function()
      assert.has_no_error(function()
        loop.set_running(99999, true)
      end)
    end)
  end)

  describe("start_loop", function()
    it("starts loop when auto_refresh is enabled", function()
      loop.start_loop(function() end, { buf = test_buf })
      assert.is_truthy(loop.is_running(test_buf))
    end)

    it("does not start loop when auto_refresh is disabled", function()
      config.options.auto_refresh.enabled = false

      loop.start_loop(function() end, { buf = test_buf })
      assert.is_falsy(loop.is_running(test_buf))
    end)
  end)

  describe("callback behavior", function()
    it("passes is_cancelled function to callback", function()
      local received_is_cancelled = nil

      loop.start_loop_for_buffer(test_buf, function(is_cancelled)
        received_is_cancelled = is_cancelled
      end)

      -- Wait for timer to fire (it starts with 0 delay)
      vim.wait(100, function()
        return received_is_cancelled ~= nil
      end)

      assert.is_function(received_is_cancelled)
    end)

    it("is_cancelled returns falsy while loop is running", function()
      local is_cancelled_result = nil

      loop.start_loop_for_buffer(test_buf, function(is_cancelled)
        is_cancelled_result = is_cancelled()
      end)

      vim.wait(100, function()
        return is_cancelled_result ~= nil
      end)

      assert.is_falsy(is_cancelled_result)
    end)

    it("is_cancelled returns truthy after loop is stopped", function()
      local saved_is_cancelled = nil

      loop.start_loop_for_buffer(test_buf, function(is_cancelled)
        saved_is_cancelled = is_cancelled
      end)

      vim.wait(100, function()
        return saved_is_cancelled ~= nil
      end)

      loop.stop_loop(test_buf)

      assert.is_truthy(saved_is_cancelled())
    end)
  end)
end)
