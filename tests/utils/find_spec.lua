local find = require("kubectl.utils.find")

describe("utils.find", function()
  describe("escape", function()
    it("escapes caret", function()
      assert.are.equal("%^", find.escape("^"))
    end)

    it("escapes dollar sign", function()
      assert.are.equal("%$", find.escape("$"))
    end)

    it("escapes parentheses", function()
      assert.are.equal("%(", find.escape("("))
      assert.are.equal("%)", find.escape(")"))
    end)

    it("escapes percent", function()
      assert.are.equal("%%", find.escape("%"))
    end)

    it("escapes dot", function()
      assert.are.equal("%.", find.escape("."))
    end)

    it("escapes brackets", function()
      assert.are.equal("%[%]", find.escape("[]"))
    end)

    it("escapes quantifiers", function()
      assert.are.equal("%*%+%-%?", find.escape("*+-?"))
    end)

    it("leaves regular characters unchanged", function()
      assert.are.equal("abc123", find.escape("abc123"))
    end)

    it("escapes mixed string", function()
      assert.are.equal("foo%.bar%[0%]", find.escape("foo.bar[0]"))
    end)
  end)

  describe("is_in_table", function()
    it("returns false for nil string", function()
      assert.is_false(find.is_in_table({ "a", "b" }, nil, false))
    end)

    it("finds exact match in flat table", function()
      assert.is_true(find.is_in_table({ "apple", "banana" }, "apple", true))
    end)

    it("finds partial match in flat table", function()
      assert.is_true(find.is_in_table({ "apple", "banana" }, "app", false))
    end)

    it("is case insensitive", function()
      assert.is_true(find.is_in_table({ "Apple" }, "apple", true))
      assert.is_true(find.is_in_table({ "apple" }, "APPLE", true))
    end)

    it("returns false when no match", function()
      assert.is_false(find.is_in_table({ "apple", "banana" }, "cherry", false))
    end)

    it("finds match in nested table", function()
      local nested = { { "apple" }, { "banana" } }
      assert.is_true(find.is_in_table(nested, "apple", false))
    end)

    it("finds partial match in deeply nested table", function()
      local deep = { { { "apple" } } }
      assert.is_true(find.is_in_table(deep, "app", false))
    end)

    it("converts numbers to string for matching", function()
      assert.is_true(find.is_in_table({ 123, 456 }, "123", true))
    end)

    it("exact match fails on partial", function()
      assert.is_false(find.is_in_table({ "apple" }, "app", true))
    end)
  end)

  describe("single", function()
    it("returns nil for nil table", function()
      assert.is_nil(find.single(nil, { "key" }, "value"))
    end)

    it("finds item by single key", function()
      local tbl = { { name = "foo" }, { name = "bar" } }
      local result = find.single(tbl, { "name" }, "bar")
      assert.are.same({ name = "bar" }, result)
    end)

    it("finds item by nested keys", function()
      local tbl = {
        { metadata = { name = "pod1" } },
        { metadata = { name = "pod2" } },
      }
      local result = find.single(tbl, { "metadata", "name" }, "pod2")
      assert.are.same({ metadata = { name = "pod2" } }, result)
    end)

    it("returns nil when no match", function()
      local tbl = { { name = "foo" } }
      assert.is_nil(find.single(tbl, { "name" }, "bar"))
    end)

    it("handles missing intermediate key", function()
      local tbl = { { other = "value" } }
      assert.is_nil(find.single(tbl, { "name", "nested" }, "value"))
    end)

    it("returns first match when multiple exist", function()
      local tbl = { { name = "foo", id = 1 }, { name = "foo", id = 2 } }
      local result = find.single(tbl, { "name" }, "foo")
      assert.are.equal(1, result.id)
    end)
  end)

  describe("filter", function()
    it("filters by predicate", function()
      local tbl = { 1, 2, 3, 4, 5 }
      local result = find.filter(tbl, function(v)
        return v > 3
      end)
      assert.are.same({ 4, 5 }, result)
    end)

    it("returns empty table when no matches", function()
      local tbl = { 1, 2, 3 }
      local result = find.filter(tbl, function(v)
        return v > 10
      end)
      assert.are.same({}, result)
    end)

    it("returns all when all match", function()
      local tbl = { 1, 2, 3 }
      local result = find.filter(tbl, function()
        return true
      end)
      assert.are.same({ 1, 2, 3 }, result)
    end)

    it("works with table items", function()
      local tbl = {
        { status = "Running" },
        { status = "Pending" },
        { status = "Running" },
      }
      local result = find.filter(tbl, function(v)
        return v.status == "Running"
      end)
      assert.are.equal(2, #result)
    end)
  end)

  describe("filter_line", function()
    it("returns empty table for nil array", function()
      assert.are.same({}, find.filter_line(nil, "pattern", 1))
    end)

    it("returns original array for nil pattern", function()
      local arr = { { "a" }, { "b" } }
      assert.are.same(arr, find.filter_line(arr, nil, 1))
    end)

    it("returns original array for empty pattern", function()
      local arr = { { "a" }, { "b" } }
      assert.are.same(arr, find.filter_line(arr, "", 1))
    end)

    it("filters by single pattern", function()
      local arr = { { "apple" }, { "banana" }, { "apricot" } }
      local result = find.filter_line(arr, "ap", 1)
      assert.are.equal(2, #result)
    end)

    it("filters by multiple comma-separated patterns (AND)", function()
      local arr = {
        { "pod", "Running" },
        { "pod", "Pending" },
        { "deployment", "Running" },
      }
      local result = find.filter_line(arr, "pod,Running", 1)
      assert.are.equal(1, #result)
      assert.are.same({ "pod", "Running" }, result[1])
    end)

    it("supports negative patterns with !", function()
      local arr = { { "Running" }, { "Pending" }, { "Failed" } }
      local result = find.filter_line(arr, "!Pending", 1)
      assert.are.equal(2, #result)
    end)

    it("combines positive and negative patterns", function()
      local arr = {
        { "pod1", "Running" },
        { "pod2", "Pending" },
        { "deploy1", "Running" },
      }
      local result = find.filter_line(arr, "Running,!deploy", 1)
      assert.are.equal(1, #result)
      assert.are.same({ "pod1", "Running" }, result[1])
    end)

    it("respects startAt parameter", function()
      local arr = { { "header" }, { "data1" }, { "data2" } }
      local result = find.filter_line(arr, "data", 2)
      assert.are.equal(2, #result)
    end)

    it("defaults startAt to 1", function()
      local arr = { { "a" }, { "b" } }
      local result = find.filter_line(arr, "a")
      assert.are.equal(1, #result)
    end)
  end)

  describe("array", function()
    it("finds matching item", function()
      local arr = { "a", "b", "c" }
      assert.are.equal("b", find.array(arr, "b"))
    end)

    it("returns nil when no match", function()
      local arr = { "a", "b", "c" }
      assert.is_nil(find.array(arr, "d"))
    end)

    it("matches by reference for tables", function()
      local obj = { name = "test" }
      local arr = { obj, { name = "other" } }
      assert.are.equal(obj, find.array(arr, obj))
    end)

    it("returns first match", function()
      local arr = { "a", "b", "a" }
      assert.are.equal("a", find.array(arr, "a"))
    end)
  end)

  describe("tbl_idx", function()
    it("finds index of matching item", function()
      local tbl = { "a", "b", "c" }
      assert.are.equal(2, find.tbl_idx(tbl, "b"))
    end)

    it("returns nil when no match", function()
      local tbl = { "a", "b", "c" }
      assert.is_nil(find.tbl_idx(tbl, "d"))
    end)

    it("returns first index when duplicates exist", function()
      local tbl = { "a", "b", "a" }
      assert.are.equal(1, find.tbl_idx(tbl, "a"))
    end)

    it("works with numbers", function()
      local tbl = { 10, 20, 30 }
      assert.are.equal(2, find.tbl_idx(tbl, 20))
    end)
  end)

  describe("dictionary", function()
    it("finds matching key-value pair", function()
      local dict = { a = 1, b = 2, c = 3 }
      local key, value = find.dictionary(dict, function(k, v)
        return v == 2
      end)
      assert.are.equal("b", key)
      assert.are.equal(2, value)
    end)

    it("can match by key", function()
      local dict = { foo = "bar", baz = "qux" }
      local key, value = find.dictionary(dict, function(k)
        return k == "foo"
      end)
      assert.are.equal("foo", key)
      assert.are.equal("bar", value)
    end)

    it("returns nil when no match", function()
      local dict = { a = 1, b = 2 }
      local key, value = find.dictionary(dict, function(_, v)
        return v == 999
      end)
      assert.is_nil(key)
      assert.is_nil(value)
    end)

    it("can use both key and value in match", function()
      local dict = { pod1 = "Running", pod2 = "Pending" }
      local key, value = find.dictionary(dict, function(k, v)
        return k:match("pod") and v == "Running"
      end)
      assert.are.equal("pod1", key)
      assert.are.equal("Running", value)
    end)
  end)
end)
