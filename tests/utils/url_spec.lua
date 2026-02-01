describe("utils.url", function()
  local url_utils

  before_each(function()
    -- Clear cached modules
    package.loaded["kubectl.utils.url"] = nil
    package.loaded["kubectl.state"] = nil

    -- Mock state module
    package.loaded["kubectl.state"] = {
      ns = "default",
      getProxyUrl = function()
        return "http://localhost:8001"
      end,
    }

    url_utils = require("kubectl.utils.url")
  end)

  describe("breakUrl", function()
    it("parses URL without query parameters", function()
      local base_url, query = url_utils.breakUrl("https://example.com/path")
      assert.are.equal("https://example.com/path", base_url)
      assert.are.same({}, query)
    end)

    it("parses URL with single query parameter", function()
      local base_url, query = url_utils.breakUrl("https://example.com/path?foo=bar")
      assert.are.equal("https://example.com/path", base_url)
      assert.are.same({ foo = "bar" }, query)
    end)

    it("parses URL with multiple query parameters", function()
      local base_url, query = url_utils.breakUrl("https://example.com/path?foo=bar&baz=qux")
      assert.are.equal("https://example.com/path", base_url)
      assert.are.same({ foo = "bar", baz = "qux" }, query)
    end)

    it("returns query as string when as_string is true", function()
      local base_url, query = url_utils.breakUrl("https://example.com/path?foo=bar&baz=qux", true)
      assert.are.equal("https://example.com/path", base_url)
      assert.are.equal("foo=bar&baz=qux", query)
    end)

    it("returns nil for non-http URLs by default", function()
      local base_url, query = url_utils.breakUrl("ftp://example.com/path")
      assert.is_nil(base_url)
      assert.is_nil(query)
    end)

    it("allows non-http URLs when check_https is false", function()
      local base_url, query = url_utils.breakUrl("ftp://example.com/path?a=b", false, false)
      assert.are.equal("ftp://example.com/path", base_url)
      assert.are.same({ a = "b" }, query)
    end)

    it("handles http URLs", function()
      local base_url, query = url_utils.breakUrl("http://example.com/path")
      assert.are.equal("http://example.com/path", base_url)
      assert.are.same({}, query)
    end)

    it("handles empty query string", function()
      local base_url, query = url_utils.breakUrl("https://example.com/path?")
      assert.are.equal("https://example.com/path", base_url)
      assert.are.same({}, query)
    end)
  end)

  describe("addHeaders", function()
    it("adds default JSON headers", function()
      local args = url_utils.addHeaders({ "http://example.com" })
      assert.are.same({
        "-X",
        "GET",
        "-sS",
        "-H",
        "Content-Type: application/json",
        "http://example.com",
      }, args)
    end)

    it("adds YAML headers when contentType is yaml", function()
      local args = url_utils.addHeaders({ "http://example.com" }, "yaml")
      assert.are.same({
        "-X",
        "GET",
        "-sS",
        "-H",
        "Accept: application/yaml",
        "-H",
        "Content-Type: application/yaml",
        "http://example.com",
      }, args)
    end)

    it("adds text/html headers", function()
      local args = url_utils.addHeaders({ "http://example.com" }, "text/html")
      assert.are.same({
        "-X",
        "GET",
        "-sS",
        "-H",
        "Accept: application/yaml",
        "-H",
        "Content-Type: text/plain",
        "http://example.com",
      }, args)
    end)
  end)

  describe("replacePlaceholders", function()
    it("replaces {{BASE}} with proxy URL", function()
      local result = url_utils.replacePlaceholders("{{BASE}}/api/v1")
      assert.are.equal("http://localhost:8001/api/v1", result)
    end)

    it("replaces {{NAMESPACE}} with namespace path", function()
      local result = url_utils.replacePlaceholders("/api/v1/{{NAMESPACE}}pods")
      assert.are.equal("/api/v1/namespaces/default/pods", result)
    end)

    it("removes {{NAMESPACE}} when namespace is All", function()
      package.loaded["kubectl.state"].ns = "All"
      local result = url_utils.replacePlaceholders("/api/v1/{{NAMESPACE}}pods")
      assert.are.equal("/api/v1/pods", result)
    end)
  end)
end)
