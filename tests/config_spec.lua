describe("config", function()
  local config

  before_each(function()
    -- Clear the module cache to get fresh state
    package.loaded["kubectl.config"] = nil
    config = require("kubectl.config")
  end)

  describe("defaults", function()
    it("has sensible default values", function()
      assert.are.equal("All", config.options.namespace)
      assert.are.equal(5, config.options.obj_fresh)
      assert.is_true(config.options.auto_refresh.enabled)
      assert.are.equal(500, config.options.auto_refresh.interval)
    end)

    it("has correct kubectl_cmd defaults", function()
      assert.are.equal("kubectl", config.options.kubectl_cmd.cmd)
      assert.are.same({}, config.options.kubectl_cmd.env)
      assert.are.same({}, config.options.kubectl_cmd.args)
    end)

    it("has correct headers defaults", function()
      assert.is_true(config.options.headers.enabled)
      assert.is_true(config.options.headers.hints)
      assert.is_true(config.options.headers.context)
      assert.are.equal(20, config.options.headers.blend)
    end)

    it("has correct float_size defaults", function()
      assert.are.equal(0.9, config.options.float_size.width)
      assert.are.equal(0.8, config.options.float_size.height)
      assert.are.equal(10, config.options.float_size.col)
      assert.are.equal(5, config.options.float_size.row)
    end)
  end)

  describe("setup", function()
    it("sets config_did_setup flag", function()
      assert.is_false(config.config_did_setup)
      config.setup({})
      assert.is_true(config.config_did_setup)
    end)

    it("merges user options with defaults", function()
      config.setup({
        namespace = "kube-system",
        obj_fresh = 10,
      })
      assert.are.equal("kube-system", config.options.namespace)
      assert.are.equal(10, config.options.obj_fresh)
      -- Defaults should still be present
      assert.is_true(config.options.auto_refresh.enabled)
    end)

    it("deep merges nested options", function()
      config.setup({
        headers = {
          enabled = false,
        },
      })
      assert.is_false(config.options.headers.enabled)
      -- Other header options should still be defaults
      assert.is_true(config.options.headers.hints)
      assert.is_true(config.options.headers.context)
    end)

    it("handles nil options gracefully", function()
      config.setup(nil)
      assert.is_true(config.config_did_setup)
      assert.are.equal("All", config.options.namespace)
    end)

    it("handles empty options table", function()
      config.setup({})
      assert.is_true(config.config_did_setup)
      assert.are.equal("All", config.options.namespace)
    end)
  end)
end)
