const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

test("normalizeSymbols: arrays are trimmed, upper-cased, de-duplicated", () => {
  assert.deepEqual(Model.normalizeSymbols([" aapl", "NVDA", "aapl", "", null]), ["AAPL", "NVDA"])
})

test("normalizeSymbols: comma/space separated strings work (omarchy bar set without --json)", () => {
  assert.deepEqual(Model.normalizeSymbols("aapl, nvda spcx;googl"), ["AAPL", "NVDA", "SPCX", "GOOGL"])
})

test("normalizeSymbols: empty or junk input falls back to the defaults", () => {
  assert.deepEqual(Model.normalizeSymbols(null), Model.DEFAULT_SYMBOLS)
  assert.deepEqual(Model.normalizeSymbols([]), Model.DEFAULT_SYMBOLS)
  assert.deepEqual(Model.normalizeSymbols("   "), Model.DEFAULT_SYMBOLS)
  assert.deepEqual(Model.normalizeSymbols(42), Model.DEFAULT_SYMBOLS)
  assert.deepEqual(Model.normalizeSymbols(null, ["SPY"]), ["SPY"])
})

test("normalizeSymbols: returns a copy, never the shared default array", () => {
  const a = Model.normalizeSymbols(null)
  a.push("X")
  assert.deepEqual(Model.normalizeSymbols(null), Model.DEFAULT_SYMBOLS)
})

test("refreshMinutes: clamps to >= 1, non-numeric falls back", () => {
  assert.equal(Model.refreshMinutes(15), 15)
  assert.equal(Model.refreshMinutes("3"), 3)
  assert.equal(Model.refreshMinutes(0), 1)
  assert.equal(Model.refreshMinutes(-4), 1)
  assert.equal(Model.refreshMinutes("abc"), 5)
  assert.equal(Model.refreshMinutes(undefined), 5)
  assert.equal(Model.refreshMinutes(null, 7), 7)
})

test("cycleSeconds: 0 is allowed (pinned), negatives and junk fall back", () => {
  assert.equal(Model.cycleSeconds(30), 30)
  assert.equal(Model.cycleSeconds("0"), 0)
  assert.equal(Model.cycleSeconds(-1), 10)
  assert.equal(Model.cycleSeconds("nope"), 10)
  assert.equal(Model.cycleSeconds(undefined, 4), 4)
})
