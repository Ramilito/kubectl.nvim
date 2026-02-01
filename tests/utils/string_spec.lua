local string_utils = require("kubectl.utils.string")

describe("utils.string", function()
  describe("capitalize", function()
    it("capitalizes the first letter of a lowercase string", function()
      assert.are.equal("Hello", string_utils.capitalize("hello"))
    end)

    it("keeps the first letter capitalized if already uppercase", function()
      assert.are.equal("World", string_utils.capitalize("World"))
    end)

    it("handles single character strings", function()
      assert.are.equal("A", string_utils.capitalize("a"))
      assert.are.equal("Z", string_utils.capitalize("Z"))
    end)

    it("returns empty string for empty input", function()
      assert.are.equal("", string_utils.capitalize(""))
    end)

    it("returns nil for nil input", function()
      assert.is_nil(string_utils.capitalize(nil))
    end)

    it("preserves the rest of the string", function()
      assert.are.equal("HelloWorld", string_utils.capitalize("helloWorld"))
    end)

    it("handles strings with numbers", function()
      assert.are.equal("123abc", string_utils.capitalize("123abc"))
    end)

    it("handles strings starting with special characters", function()
      assert.are.equal("_test", string_utils.capitalize("_test"))
    end)
  end)
end)
