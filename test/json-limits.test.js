// Regression for marketplace review 6789183040 (json-length): untrusted
// watchlist JSON (import, gist, watchlists.json) and Qt array-like settings
// must not drive loops or allocations from a forged `length`.
const test = require("node:test")
const assert = require("node:assert/strict")
const { spawnSync } = require("node:child_process")
const fs = require("node:fs"), os = require("node:os"), path = require("node:path")
const Model = require("../Model.js")

const HUGE = 1000000000

// An array-like whose element reads are counted: any read means an adapter
// started iterating a length it should have refused.
function forged(length) {
  const seen = { reads: 0 }
  const obj = { length }
  Object.defineProperty(obj, "0", { enumerable: true, get() { seen.reads++; return "AAPL" } })
  return { obj, seen }
}

test("root adapter: {\"length\":1000000000} is rejected before iterating", () => {
  const started = Date.now()
  assert.deepEqual(Model.readWatchlistsDefinition('{"length":1000000000}'), { definition: null, tooLarge: false })
  assert.equal(Model.parseWatchlistsDefinition('{"length":1000000000,"0":"AAPL"}'), null)
  assert.ok(Date.now() - started < 200)
})

test("nested adapters: forged watchlists / symbols lengths reject the whole definition", () => {
  const cases = [
    '{"watchlists":{"length":1000000000}}',
    '{"symbols":{"length":1000000000}}',
    '{"watchlists":[{"name":"A","symbols":{"length":1000000000}}]}',
    '[{"name":"A","symbols":{"length":1000000000,"0":"AAPL"}}]',
    '{"watchlists":"AAPL,MSFT"}',
  ]
  const started = Date.now()
  for (const text of cases) assert.deepEqual(Model.readWatchlistsDefinition(text), { definition: null, tooLarge: true }, text)
  assert.ok(Date.now() - started < 200)
})

test("definition limits: counts, string lengths, fields and bytes", () => {
  const sym = (i) => "S" + i
  const list = (n, name) => ({ name: name || "L", symbols: Array.from({ length: n }, (_, i) => sym(i)) })
  const read = (value) => Model.readWatchlistsDefinition(typeof value === "string" ? value : JSON.stringify(value))

  assert.equal(read({ watchlists: Array.from({ length: Model.MAX_WATCHLISTS }, () => list(1)) }).definition.watchlists.length, Model.MAX_WATCHLISTS)
  assert.equal(read({ watchlists: Array.from({ length: Model.MAX_WATCHLISTS + 1 }, () => list(1)) }).tooLarge, true)
  assert.equal(read({ watchlists: [list(Model.MAX_SYMBOLS_PER_LIST)] }).definition.watchlists[0].symbols.length, Model.MAX_SYMBOLS_PER_LIST)
  assert.equal(read({ watchlists: [list(Model.MAX_SYMBOLS_PER_LIST + 1)] }).tooLarge, true)
  assert.equal(read(Array.from({ length: Model.MAX_SYMBOLS_PER_LIST + 1 }, (_, i) => sym(i))).tooLarge, true)
  assert.equal(read({ symbols: ["A".repeat(Model.MAX_SYMBOL_LENGTH + 1)] }).tooLarge, true)
  assert.equal(read({ watchlists: [list(1, "n".repeat(Model.MAX_WATCHLIST_NAME_LENGTH + 1))] }).tooLarge, true)
  assert.equal(read({ watchlists: [list(1, "n".repeat(Model.MAX_WATCHLIST_NAME_LENGTH))] }).tooLarge, false)
  const fields = { name: "A", symbols: ["AAPL"] }
  for (let i = 0; i < Model.MAX_DEFINITION_FIELDS; i++) fields["x" + i] = 1
  assert.equal(read({ watchlists: [fields] }).tooLarge, true)
  assert.equal(read(Object.assign({ symbols: ["AAPL"] }, fields)).tooLarge, true)
  const padded = JSON.stringify({ symbols: ["AAPL"], pad: "x".repeat(Model.MAX_DEFINITION_BYTES) })
  assert.equal(read(padded).tooLarge, true)
  const lines = Array.from({ length: Model.MAX_SYMBOLS_PER_LIST + 1 }, (_, i) => sym(i)).join("\n")
  assert.equal(read(lines).tooLarge, true)
  // Ordinary definitions are unchanged.
  assert.deepEqual(read('{"version":1,"activeWatchlist":1,"watchlists":[{"name":"US","symbols":["aapl"]},{"name":"TW","symbols":["TW:2330"]}]}'),
    { definition: { watchlists: [{ name: "US", symbols: ["AAPL"] }, { name: "TW", symbols: ["2330.TW"] }], activeWatchlist: 1 }, tooLarge: false })
})

test("Qt array-like settings: only a small non-negative integer length is copied", () => {
  for (const bad of [HUGE, Model.MAX_SETTINGS_LIST + 1, -1, 1.5, NaN, Infinity, "2"]) {
    const { obj, seen } = forged(bad)
    assert.equal(Model.boundedList(obj, Model.MAX_SETTINGS_LIST), null, String(bad))
    assert.deepEqual(Model.normalizeSymbols(obj), Model.DEFAULT_SYMBOLS)
    assert.deepEqual(Model.normalizeCurrencies(obj), Model.DEFAULT_CURRENCIES)
    assert.deepEqual(Model.normalizeAgentCommand(obj), Model.DEFAULT_AGENT_COMMAND)
    assert.deepEqual(Model.normalizeAgentPrompts(obj), Model.DEFAULT_AGENT_PROMPTS)
    assert.equal(Model.normalizeWatchlists(obj, ["SPY"])[0].symbols[0], "SPY")
    assert.deepEqual(Model.normalizeWatchlists([{ name: "A", symbols: obj }], ["SPY"]), [{ name: "Main", symbols: ["SPY"] }])
    assert.equal(seen.reads, 0, "no element read for length " + bad)
  }
  const ok = { length: 2, 0: "aapl", 1: "msft" }
  assert.deepEqual(Model.normalizeSymbols(ok), ["AAPL", "MSFT"])
  assert.deepEqual(Model.normalizeWatchlists({ length: 1, 0: { name: "Q", symbols: ok } }), [{ name: "Q", symbols: ["AAPL", "MSFT"] }])
})

test("local edits are clamped so a saved definition always reloads", () => {
  const many = Array.from({ length: Model.MAX_WATCHLISTS + 5 }, (_, i) => ({
    name: "n".repeat(200), symbols: Array.from({ length: Model.MAX_SYMBOLS_PER_LIST + 20 }, (_, j) => "S" + i + "X" + j)
  }))
  const clone = Model.cloneWatchlists(many)
  assert.equal(clone.length, Model.MAX_WATCHLISTS)
  assert.equal(clone[0].symbols.length, Model.MAX_SYMBOLS_PER_LIST)
  assert.equal(clone[0].name.length, Model.MAX_WATCHLIST_NAME_LENGTH)
  const again = Model.readWatchlistsDefinition(Model.serializeWatchlists(clone))
  assert.equal(again.tooLarge, false)
  assert.equal(again.definition.watchlists.length, Model.MAX_WATCHLISTS)
})

test("import and gist pull are byte-capped in the child process (real sh)", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "stock-hq-import-"))
  const file = path.join(dir, "big.json")
  fs.writeFileSync(file, JSON.stringify({ symbols: ["AAPL"], pad: "x".repeat(Model.MAX_DEFINITION_BYTES * 2) }))
  const cmd = Model.importReadCommand(file)
  const r = spawnSync(cmd[0], cmd.slice(1))
  assert.equal(r.status, 0)
  assert.equal(r.stdout.length, Model.MAX_DEFINITION_BYTES + 1)
  assert.equal(Model.readWatchlistsDefinition(r.stdout.toString()).tooLarge, true)
  fs.rmSync(dir, { recursive: true, force: true })

  const pull = Model.gistPullCommand("0123456789abcdef0123", "stocks.json")
  assert.match(pull[2], /\| head -c \d+$/)
  const big = Model.ghCommand("head -c 600000 /dev/zero | tr '\\0' a", [], Model.MAX_DEFINITION_BYTES)
  const out = spawnSync(big[0], big.slice(1)).stdout
  assert.ok(out.length <= Model.MAX_DEFINITION_BYTES + 32, String(out.length))
  const result = Model.parseCommandResult(out.toString())
  assert.equal(result.code, 0)
  assert.equal(Model.readWatchlistsDefinition(result.output).tooLarge, true)
})
