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

// Trimmed real responses from query1.finance.yahoo.com/v8/finance/chart/<SYM>?range=1d&interval=1d
const AAPL_LINE = JSON.stringify({ chart: { result: [{ meta: {
  currency: "USD", symbol: "AAPL", exchangeName: "NMS", fullExchangeName: "NasdaqGS",
  regularMarketTime: 1786996801, regularMarketPrice: 305.59, fiftyTwoWeekHigh: 344.57,
  fiftyTwoWeekLow: 223.78, regularMarketDayHigh: 307.66, regularMarketDayLow: 302.939,
  regularMarketVolume: 32743947, longName: "Apple Inc.", shortName: "Apple Inc.",
  chartPreviousClose: 305.93, priceHint: 2
}, timestamp: [1786996800], indicators: { quote: [{ close: [305.59] }] } }], error: null } })

const GOOGL_LINE = JSON.stringify({ chart: { result: [{ meta: {
  currency: "USD", symbol: "GOOGL", fullExchangeName: "NasdaqGS", regularMarketPrice: 344.0,
  chartPreviousClose: 345.9, shortName: "Alphabet Inc.", regularMarketTime: 1786996801
} }], error: null } })

const NOT_FOUND_LINE = JSON.stringify({ chart: { result: null,
  error: { code: "Not Found", description: "No data found, symbol may be delisted" } } })

test("chartUrl: encodes the symbol into the v8 chart endpoint", () => {
  assert.equal(Model.chartUrl("AAPL"), "https://query1.finance.yahoo.com/v8/finance/chart/AAPL?range=1d&interval=1d")
  assert.equal(Model.chartUrl("^GSPC"), "https://query1.finance.yahoo.com/v8/finance/chart/%5EGSPC?range=1d&interval=1d")
})

test("curlCommand: one curl, one URL per symbol, newline write-out, custom UA", () => {
  const cmd = Model.curlCommand(["AAPL", "BTC-USD"], "test-agent/1.0")
  assert.deepEqual(cmd.slice(0, 8), ["curl", "-sS", "--max-time", "10", "-A", "test-agent/1.0", "-w", "\n"])
  assert.deepEqual(cmd.slice(8), [Model.chartUrl("AAPL"), Model.chartUrl("BTC-USD")])
})

test("quoteUrl / shellQuote", () => {
  assert.equal(Model.quoteUrl("BTC-USD"), "https://finance.yahoo.com/quote/BTC-USD")
  assert.equal(Model.shellQuote("it's"), "'it'\\''s'")
})

test("parseChartResponse: successful line", () => {
  const q = Model.parseChartResponse(AAPL_LINE)
  assert.equal(q.error, "")
  assert.equal(q.symbol, "AAPL")
  assert.equal(q.name, "Apple Inc.")
  assert.equal(q.currency, "USD")
  assert.equal(q.exchange, "NasdaqGS")
  assert.equal(q.price, 305.59)
  assert.equal(q.prevClose, 305.93)
  assert.ok(Math.abs(q.change - -0.34) < 1e-9)
  assert.ok(Math.abs(q.changePct - (-0.34 / 305.93 * 100)) < 1e-9)
  assert.equal(q.dayLow, 302.939)
  assert.equal(q.dayHigh, 307.66)
  assert.equal(q.week52Low, 223.78)
  assert.equal(q.week52High, 344.57)
  assert.equal(q.marketTime, 1786996801)
})

test("parseChartResponse: missing optional fields become null, name falls back to symbol", () => {
  const q = Model.parseChartResponse(JSON.stringify({ chart: { result: [{ meta: { symbol: "X", regularMarketPrice: 2 } }] } }))
  assert.equal(q.error, "")
  assert.equal(q.name, "X")
  assert.equal(q.prevClose, null)
  assert.equal(q.change, null)
  assert.equal(q.changePct, null)
  assert.equal(q.dayLow, null)
})

test("parseChartResponse: error, empty and garbage lines", () => {
  assert.equal(Model.parseChartResponse(NOT_FOUND_LINE).error, "Not Found")
  assert.equal(Model.parseChartResponse("").error, "No data")
  assert.equal(Model.parseChartResponse("<html>429</html>").error, "Bad response")
  assert.equal(Model.parseChartResponse(JSON.stringify({ chart: { result: [{ meta: { symbol: "Y" } }] } })).error, "No data")
})

test("parseQuoteLines: one Quote per requested symbol, in request order, matched by symbol", () => {
  const quotes = Model.parseQuoteLines(GOOGL_LINE + "\n" + AAPL_LINE + "\n", ["AAPL", "GOOGL"])
  assert.deepEqual(quotes.map(q => q.symbol), ["AAPL", "GOOGL"])
  assert.equal(quotes[0].price, 305.59)
  assert.equal(quotes[1].price, 344.0)
})

test("parseQuoteLines: error lines are attributed positionally when the line count matches", () => {
  const quotes = Model.parseQuoteLines([AAPL_LINE, NOT_FOUND_LINE, GOOGL_LINE].join("\n") + "\n", ["AAPL", "NOPE", "GOOGL"])
  assert.equal(quotes[1].symbol, "NOPE")
  assert.equal(quotes[1].error, "Not Found")
  assert.equal(quotes[2].symbol, "GOOGL")
  assert.equal(quotes[2].error, "")
})

test("parseQuoteLines: missing lines yield 'No data' for the unmatched symbols", () => {
  const quotes = Model.parseQuoteLines(AAPL_LINE + "\n", ["AAPL", "GOOGL", "NVDA"])
  assert.equal(quotes[0].error, "")
  assert.equal(quotes[1].error, "No data")
  assert.equal(quotes[2].error, "No data")
  assert.equal(quotes[2].symbol, "NVDA")
})

test("parseQuoteLines: the requested symbol wins over Yahoo's casing", () => {
  const quotes = Model.parseQuoteLines(AAPL_LINE + "\n", ["AAPL"])
  assert.equal(quotes[0].symbol, "AAPL")
  assert.deepEqual(Model.parseQuoteLines("", []), [])
})
