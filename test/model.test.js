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
  assert.equal(Model.chartUrl("AAPL"), "https://query1.finance.yahoo.com/v8/finance/chart/AAPL?range=1d&interval=5m")
  assert.equal(Model.chartUrl("^GSPC"), "https://query1.finance.yahoo.com/v8/finance/chart/%5EGSPC?range=1d&interval=5m")
  assert.equal(Model.chartUrl("AAPL", "1mo"), "https://query1.finance.yahoo.com/v8/finance/chart/AAPL?range=1mo&interval=1d")
})

test("curlCommand: one curl, one URL per symbol, newline write-out, custom UA", () => {
  const cmd = Model.curlCommand(["AAPL", "BTC-USD"], "test-agent/1.0")
  assert.deepEqual(cmd.slice(0, 8), ["curl", "-sS", "--max-time", "10", "-A", "test-agent/1.0", "-w", "\n"])
  assert.deepEqual(cmd.slice(8), [Model.chartUrl("AAPL"), Model.chartUrl("BTC-USD")])
  assert.deepEqual(Model.curlCommand(["AAPL"], "ua", "6mo").slice(8), [Model.chartUrl("AAPL", "6mo")])
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

function quote(symbol, price, prev, error) {
  const q = Model.emptyQuote(symbol, error || "")
  q.price = price === undefined ? null : price
  q.prevClose = prev === undefined ? null : prev
  q.change = q.price !== null && q.prevClose !== null ? q.price - q.prevClose : null
  q.changePct = q.change !== null && q.prevClose ? q.change / q.prevClose * 100 : null
  return q
}

test("isValid / isDown / validCount", () => {
  assert.equal(Model.isValid(quote("AAPL", 305.59, 305.93)), true)
  assert.equal(Model.isValid(quote("NOPE", null, null, "Not Found")), false)
  assert.equal(Model.isValid(null), false)
  assert.equal(Model.isDown(quote("AAPL", 305.59, 305.93)), true)
  assert.equal(Model.isDown(quote("GOOGL", 346, 345.9)), false)
  assert.equal(Model.isDown(quote("FLAT", 10, 10)), false)
  assert.equal(Model.isDown(null), false)
  assert.equal(Model.validCount([quote("A", 1, 1), quote("B", null, null, "Not Found"), quote("C", 2, 1)]), 2)
  assert.equal(Model.validCount(null), 0)
})

test("firstValidIndex / nextIndex skip invalid quotes and wrap", () => {
  const list = [quote("A", null, null, "Not Found"), quote("B", 1, 1), quote("C", 2, 1), quote("D", null, null, "No data")]
  assert.equal(Model.firstValidIndex(list), 1)
  assert.equal(Model.firstValidIndex([quote("X", null, null, "Not Found")]), -1)
  assert.equal(Model.firstValidIndex([]), -1)
  assert.equal(Model.nextIndex(1, list, 1), 2)
  assert.equal(Model.nextIndex(2, list, 1), 1)      // wraps past D and A
  assert.equal(Model.nextIndex(1, list, -1), 2)     // backwards wraps past A and D
  assert.equal(Model.nextIndex(-1, list, 1), 1)     // no current -> first valid
  assert.equal(Model.nextIndex(0, [quote("B", 1, 1)], 1), 0)
  assert.equal(Model.nextIndex(0, [quote("X", null, null, "Not Found")], 1), -1)
  assert.equal(Model.nextIndex(0, [], 1), -1)
})

test("shouldRetry: only when some failure is not a plain 'Not Found'", () => {
  assert.equal(Model.shouldRetry([quote("A", null, null, "Not Found")]), false)
  assert.equal(Model.shouldRetry([quote("A", null, null, "Not Found"), quote("B", null, null, "No data")]), true)
  assert.equal(Model.shouldRetry([quote("A", null, null, "Bad response")]), true)
  assert.equal(Model.shouldRetry([]), true)
})

test("formatPrice: 2 decimals, 4 below 1, thousands separators", () => {
  assert.equal(Model.formatPrice(305.59), "305.59")
  assert.equal(Model.formatPrice(344), "344.00")
  assert.equal(Model.formatPrice(65432.1), "65,432.10")
  assert.equal(Model.formatPrice(1234567.891), "1,234,567.89")
  assert.equal(Model.formatPrice(0.12345), "0.1235")
  assert.equal(Model.formatPrice(-2.5), "-2.50")
  assert.equal(Model.formatPrice(null), "")
  assert.equal(Model.formatPrice(NaN), "")
})

test("formatChange: arrow, signed absolute change, percent", () => {
  assert.equal(Model.formatChange(quote("A", 306.87, 305.59)), "▲ +1.28 (0.42%)")
  assert.equal(Model.formatChange(quote("B", 410.05, 412.10)), "▼ -2.05 (0.50%)")
  assert.equal(Model.formatChange(quote("C", 10, 10)), "• +0.00 (0.00%)")
  assert.equal(Model.formatChange(quote("D", 0.5, 0.4)), "▲ +0.1000 (25.00%)")
  assert.equal(Model.formatChange(quote("E", 5, null)), "")
  assert.equal(Model.formatChange(null), "")
})

test("barLabel: full, compact, error, no-change", () => {
  assert.equal(Model.barLabel(quote("AAPL", 306.87, 305.59), false), "AAPL 306.87 ▲0.42%")
  assert.equal(Model.barLabel(quote("AAPL", 306.87, 305.59), true), "AAPL ▲0.42%")
  assert.equal(Model.barLabel(quote("MSFT", 410.05, 412.10), false), "MSFT 410.05 ▼0.50%")
  assert.equal(Model.barLabel(quote("X", 5, null), false), "X 5.00")
  assert.equal(Model.barLabel(quote("NOPE", null, null, "Not Found"), false), "NOPE !")
  assert.equal(Model.barLabel(null, false), "")
})

test("verticalLabel / loadingLabel", () => {
  assert.equal(Model.verticalLabel(quote("AAPL", 306.87, 305.59)), "AAPL\n▲")
  assert.equal(Model.verticalLabel(quote("NOPE", null, null, "Not Found")), "NOPE\n!")
  assert.equal(Model.verticalLabel(null), "")
  assert.equal(Model.loadingLabel("AAPL"), "AAPL …")
  assert.equal(Model.loadingLabel(""), "…")
})

// ---- Revision 2: ranges, series, tape, chart geometry

test("chartRange / chartInterval: validated ranges map to Yahoo intervals", () => {
  assert.deepEqual(Model.CHART_RANGES, ["1d", "5d", "1mo", "6mo", "1y"])
  assert.equal(Model.chartRange("1mo"), "1mo")
  assert.equal(Model.chartRange(" 6MO "), "6mo")
  assert.equal(Model.chartRange("2y"), "1d")
  assert.equal(Model.chartRange(null), "1d")
  assert.equal(Model.chartRange(null, "5d"), "5d")
  assert.equal(Model.chartInterval("1d"), "5m")
  assert.equal(Model.chartInterval("5d"), "15m")
  assert.equal(Model.chartInterval("1mo"), "1d")
  assert.equal(Model.chartInterval("6mo"), "1d")
  assert.equal(Model.chartInterval("1y"), "1wk")
  assert.equal(Model.chartInterval("bogus"), "1d")
})

test("tickerWidth / scrollSpeed clamps", () => {
  assert.equal(Model.tickerWidth(500), 500)
  assert.equal(Model.tickerWidth("240"), 240)
  assert.equal(Model.tickerWidth(10), 80)
  assert.equal(Model.tickerWidth("x"), 180)
  assert.equal(Model.tickerWidth(undefined, 300), 300)
  assert.equal(Model.scrollSpeed(60), 60)
  assert.equal(Model.scrollSpeed("12.5"), 12.5)
  assert.equal(Model.scrollSpeed(0), 0)
  assert.equal(Model.scrollSpeed(-3), 20)
  assert.equal(Model.scrollSpeed("fast"), 20)
  assert.equal(Model.scrollSpeed(null, 25), 25)
})

const SERIES_LINE = JSON.stringify({ chart: { result: [{ meta: {
  currency: "USD", symbol: "AAPL", regularMarketPrice: 305.59, previousClose: 305.93,
  chartPreviousClose: 333.74, regularMarketVolume: 32743947, shortName: "Apple Inc.", regularMarketTime: 1786996801
}, timestamp: [100, 200, 300, 400], indicators: { quote: [{
  close: [305.76, null, 305.69, 305.59], open: [null, 305.8, 305.7, 305.6]
}] } }], error: null } })

test("parseChartResponse: series skips nulls, reads open/volume, prefers previousClose", () => {
  const q = Model.parseChartResponse(SERIES_LINE)
  assert.deepEqual(q.series, [{ t: 100, c: 305.76 }, { t: 300, c: 305.69 }, { t: 400, c: 305.59 }])
  assert.equal(q.open, 305.8)
  assert.equal(q.volume, 32743947)
  assert.equal(q.prevClose, 305.93)
  const bare = Model.parseChartResponse(JSON.stringify({ chart: { result: [{ meta: { symbol: "X", regularMarketPrice: 2 } }] } }))
  assert.deepEqual(bare.series, [])
  assert.equal(bare.open, null)
  assert.equal(bare.volume, null)
  assert.deepEqual(Model.emptyQuote("Z", "No data").series, [])
})

test("parseSeriesLines: symbol -> series map, missing symbols get []", () => {
  const map = Model.parseSeriesLines(SERIES_LINE + "\n" + NOT_FOUND_LINE + "\n", ["AAPL", "NOPE"])
  assert.equal(map.AAPL.length, 3)
  assert.deepEqual(map.NOPE, [])
})

test("seriesBounds / seriesDirection", () => {
  const s = [{ t: 0, c: 10 }, { t: 5, c: 14 }, { t: 10, c: 12 }]
  assert.deepEqual(Model.seriesBounds(s), { min: 10, max: 14 })
  assert.equal(Model.seriesBounds([]), null)
  assert.equal(Model.seriesBounds(null), null)
  assert.equal(Model.seriesDirection(s), 2)
  assert.equal(Model.seriesDirection([{ t: 0, c: 3 }, { t: 1, c: 1 }]), -2)
  assert.equal(Model.seriesDirection([{ t: 0, c: 3 }]), 0)
  assert.equal(Model.seriesDirection([]), 0)
})

test("seriesPoints: time-proportional x, value-scaled y within padding", () => {
  const s = [{ t: 0, c: 10 }, { t: 5, c: 14 }, { t: 10, c: 12 }]
  const pts = Model.seriesPoints(s, 100, 40, 2)
  assert.equal(pts.length, 3)
  assert.deepEqual(pts[0], { x: 2, y: 38 })     // min value -> bottom
  assert.deepEqual(pts[1], { x: 50, y: 2 })     // max value -> top
  assert.deepEqual(pts[2], { x: 98, y: 20 })    // midway value -> middle
  assert.deepEqual(Model.seriesPoints([{ t: 3, c: 7 }], 100, 40, 2), [{ x: 2, y: 20 }])
  assert.deepEqual(Model.seriesPoints([{ t: 3, c: 7 }, { t: 9, c: 7 }], 100, 40, 2), [{ x: 2, y: 20 }, { x: 98, y: 20 }])
  assert.deepEqual(Model.seriesPoints([], 100, 40, 2), [])
})

test("valueToY: inside the bounds maps like seriesPoints, outside is null", () => {
  const b = { min: 10, max: 14 }
  assert.equal(Model.valueToY(10, b, 40, 2), 38)
  assert.equal(Model.valueToY(14, b, 40, 2), 2)
  assert.equal(Model.valueToY(12, b, 40, 2), 20)
  assert.equal(Model.valueToY(9, b, 40, 2), null)
  assert.equal(Model.valueToY(null, b, 40, 2), null)
  assert.equal(Model.valueToY(12, null, 40, 2), null)
})

test("tapeItems: valid quotes only, compact form, down flag", () => {
  const list = [quote("AAPL", 306.87, 305.59), quote("NOPE", null, null, "Not Found"), quote("MSFT", 410.05, 412.10)]
  assert.deepEqual(Model.tapeItems(list, false), [
    { symbol: "AAPL", text: "AAPL 306.87 ▲0.42%", up: true, down: false },
    { symbol: "MSFT", text: "MSFT 410.05 ▼0.50%", up: false, down: true }
  ])
  assert.deepEqual(Model.tapeItems([quote("FLAT", 10, 10)], false), [{ symbol: "FLAT", text: "FLAT 10.00 •0.00%", up: false, down: false }])
  assert.deepEqual(Model.tapeItems(list, true).map(i => i.text), ["AAPL ▲0.42%", "MSFT ▼0.50%"])
  assert.deepEqual(Model.tapeItems([], false), [])
  assert.deepEqual(Model.tapeItems(null, false), [])
})

test("formatVolume", () => {
  assert.equal(Model.formatVolume(950), "950")
  assert.equal(Model.formatVolume(114897), "114.9K")
  assert.equal(Model.formatVolume(32743947), "32.7M")
  assert.equal(Model.formatVolume(1234567890), "1.23B")
  assert.equal(Model.formatVolume(0), "0")
  assert.equal(Model.formatVolume(null), "")
})

test("normalizeColor: accepts #rgb/#rrggbb/#aarrggbb, rejects junk", () => {
  assert.equal(Model.normalizeColor("#a9b665"), "#a9b665")
  assert.equal(Model.normalizeColor(" #A9B665 "), "#a9b665")
  assert.equal(Model.normalizeColor("#fff"), "#fff")
  assert.equal(Model.normalizeColor("#80a9b665"), "#80a9b665")
  assert.equal(Model.normalizeColor("green"), "")
  assert.equal(Model.normalizeColor("#12345"), "")
  assert.equal(Model.normalizeColor(null), "")
})

test("parseThemeColor: reads a key from Omarchy's colors.toml", () => {
  const toml = 'mode = "dark"\n\naccent = "#7daea3"\n\nred = "#ea6962"\ngreen = "#a9b665"\nbright_green = "#a9b665"\n'
  assert.equal(Model.parseThemeColor(toml, "green"), "#a9b665")
  assert.equal(Model.parseThemeColor(toml, "red"), "#ea6962")
  assert.equal(Model.parseThemeColor(toml, "bright_green"), "#a9b665")
  assert.equal(Model.parseThemeColor(toml, "purple"), "")
  assert.equal(Model.parseThemeColor("green = 'not-a-color'", "green"), "")
  assert.equal(Model.parseThemeColor("", "green"), "")
  assert.equal(Model.parseThemeColor(null, "green"), "")
})

// ---- Revision 3: display currency

test("normalizeCurrency / normalizeCurrencies", () => {
  assert.equal(Model.normalizeCurrency(" eur "), "EUR")
  assert.equal(Model.normalizeCurrency("USD"), "USD")
  assert.equal(Model.normalizeCurrency("euro"), "")
  assert.equal(Model.normalizeCurrency(""), "")
  assert.equal(Model.normalizeCurrency(null), "")
  assert.deepEqual(Model.normalizeCurrencies(null), ["USD", "EUR", "GBP", "JPY", "CHF"])
  assert.deepEqual(Model.normalizeCurrencies(["eur", "usd", "EUR", "x"]), ["EUR", "USD"])
  assert.deepEqual(Model.normalizeCurrencies("gbp, jpy"), ["GBP", "JPY"])
  assert.deepEqual(Model.normalizeCurrencies([]), ["USD", "EUR", "GBP", "JPY", "CHF"])
})

test("currencyCycle: '' (native) sits before the list and wraps both ways", () => {
  const list = ["USD", "EUR"]
  assert.equal(Model.currencyCycle("", list, 1), "USD")
  assert.equal(Model.currencyCycle("USD", list, 1), "EUR")
  assert.equal(Model.currencyCycle("EUR", list, 1), "")
  assert.equal(Model.currencyCycle("", list, -1), "EUR")
  assert.equal(Model.currencyCycle("USD", list, -1), "")
  assert.equal(Model.currencyCycle("XXX", list, 1), "USD")   // unknown current -> first
  assert.equal(Model.currencyCycle("", [], 1), "")
})

test("quoteCurrency: minor units (GBp, ZAc) map to the major code with a factor", () => {
  assert.deepEqual(Model.quoteCurrency("USD"), { code: "USD", factor: 1 })
  assert.deepEqual(Model.quoteCurrency("GBp"), { code: "GBP", factor: 0.01 })
  assert.deepEqual(Model.quoteCurrency("ZAc"), { code: "ZAR", factor: 0.01 })
  assert.deepEqual(Model.quoteCurrency(""), { code: "", factor: 1 })
})

test("ratePairs: one Yahoo FX symbol per distinct quote currency that differs from the display one", () => {
  const list = [quote("AAPL", 1, 1), quote("SAP.DE", 2, 2), quote("VOD.L", 3, 3), quote("BAD", null, null, "Not Found")]
  list[0].currency = "USD"; list[1].currency = "EUR"; list[2].currency = "GBp"; list[3].currency = "USD"
  assert.deepEqual(Model.ratePairs(list, "EUR"), ["USDEUR=X", "GBPEUR=X"])
  assert.deepEqual(Model.ratePairs(list, "USD"), ["EURUSD=X", "GBPUSD=X"])
  assert.deepEqual(Model.ratePairs(list, ""), [])
  assert.deepEqual(Model.ratePairs([], "EUR"), [])
})

const RATE_LINE = JSON.stringify({ chart: { result: [{ meta: { currency: "EUR", symbol: "USDEUR=X", regularMarketPrice: 0.92, chartPreviousClose: 0.91 } }], error: null } })

test("parseRateLines / rateFor", () => {
  const rates = Model.parseRateLines(RATE_LINE + "\n" + NOT_FOUND_LINE + "\n", ["USDEUR=X", "XXXEUR=X"])
  assert.deepEqual(rates, { "USDEUR=X": 0.92 })
  assert.equal(Model.rateFor("USD", "EUR", rates), 0.92)
  assert.equal(Model.rateFor("EUR", "EUR", rates), 1)
  assert.equal(Model.rateFor("USD", "", rates), 1)
  assert.equal(Model.rateFor("GBp", "EUR", { "GBPEUR=X": 1.2 }), 0.012)
  assert.equal(Model.rateFor("USD", "JPY", rates), null)
  assert.equal(Model.rateFor("", "EUR", rates), null)
})

test("convertQuote: scales money fields and series, keeps percentages, tags the display currency", () => {
  const q = quote("AAPL", 305.59, 305.93)
  q.currency = "USD"; q.dayLow = 302.94; q.dayHigh = 307.66; q.week52Low = 223.78; q.week52High = 344.57; q.open = 306.21
  q.series = [{ t: 1, c: 300 }, { t: 2, c: 310 }]
  const c = Model.convertQuote(q, "EUR", { "USDEUR=X": 0.5 })
  assert.equal(c.price, 152.795)
  assert.equal(c.prevClose, 152.965)
  assert.ok(Math.abs(c.change - (152.795 - 152.965)) < 1e-9)
  assert.equal(c.changePct, q.changePct)
  assert.equal(c.dayLow, 151.47)
  assert.equal(c.week52High, 172.285)
  assert.equal(c.open, 153.105)
  assert.deepEqual(c.series, [{ t: 1, c: 150 }, { t: 2, c: 155 }])
  assert.equal(c.currency, "EUR")
  assert.equal(c.nativeCurrency, "USD")
  assert.equal(c.converted, true)
  assert.equal(q.price, 305.59)                       // original untouched
  const same = Model.convertQuote(q, "USD", {})
  assert.equal(same.converted, false)
  assert.equal(same.price, 305.59)
  const missing = Model.convertQuote(q, "JPY", {})
  assert.equal(missing.converted, false)
  assert.equal(missing.price, 305.59)
  assert.equal(Model.convertQuote(quote("BAD", null, null, "Not Found"), "EUR", {}).error, "Not Found")
  assert.deepEqual(Model.convertSeries([{ t: 1, c: 2 }], 3), [{ t: 1, c: 6 }])
  assert.deepEqual(Model.convertSeries([{ t: 1, c: 2 }], null), [{ t: 1, c: 2 }])
  assert.equal(Model.convertAll([q], "EUR", { "USDEUR=X": 0.5 })[0].price, 152.795)
})

// ---- Level-1 metrics

const fullQuote = () => Object.assign(Model.emptyQuote("AAPL"), {
  name: "Apple Inc.", exchange: "NasdaqGS", currency: "USD",
  price: 105, prevClose: 100, change: 5, changePct: 5, open: 102,
  dayLow: 99, dayHigh: 109, week52Low: 80, week52High: 140, volume: 1234567, marketTime: 1700000000
})

test("rangePosition: clamps, handles flat and unknown ranges", () => {
  assert.equal(Model.rangePosition(5, 0, 10), 0.5)
  assert.equal(Model.rangePosition(-1, 0, 10), 0)
  assert.equal(Model.rangePosition(11, 0, 10), 1)
  assert.equal(Model.rangePosition(3, 3, 3), 0.5)
  assert.equal(Model.rangePosition(null, 0, 10), null)
  assert.equal(Model.rangePosition(5, 10, 0), null)
})

test("gap / day range / off-high percentages", () => {
  const q = fullQuote()
  assert.equal(Model.gapPct(q), 2)
  assert.equal(Model.dayRangePct(q), 10)
  assert.equal(Model.offHighPct(q), -25)
  assert.equal(Model.gapPct(Object.assign(q, { open: null })), null)
  assert.equal(Model.dayRangePct(Object.assign(fullQuote(), { prevClose: 0 })), null)
  assert.equal(Model.offHighPct(null), null)
})

test("formatSignedPct / formatSignedNumber", () => {
  assert.equal(Model.formatSignedPct(1.234), "+1.23%")
  assert.equal(Model.formatSignedPct(-0.4), "-0.40%")
  assert.equal(Model.formatSignedPct(null), "")
  assert.equal(Model.formatSignedNumber(-1.5, 100), "-1.50")
  assert.equal(Model.formatSignedNumber(0.01, 0.5), "+0.0100")
})

test("marketSummary counts advancers/decliners and averages valid quotes", () => {
  const up = fullQuote()
  const down = Object.assign(fullQuote(), { symbol: "B", change: -1, changePct: -3 })
  const bad = Model.emptyQuote("X", "Not Found")
  const s = Model.marketSummary([up, down, bad])
  assert.equal(s.up, 1)
  assert.equal(s.down, 1)
  assert.equal(s.flat, 0)
  assert.equal(s.avgPct, 1)
  assert.equal(Model.marketSummary([]).avgPct, null)
})

test("sortQuotes: by metric, desc/asc, invalid last, empty key keeps order", () => {
  const a = Object.assign(fullQuote(), { symbol: "A", changePct: 1 })
  const b = Object.assign(fullQuote(), { symbol: "B", changePct: 3 })
  const c = Object.assign(fullQuote(), { symbol: "C", changePct: -2 })
  const bad = Model.emptyQuote("Z", "Not Found")
  const syms = list => list.map(q => q.symbol)
  assert.deepEqual(syms(Model.sortQuotes([a, bad, b, c], "changePct", true)), ["B", "A", "C", "Z"])
  assert.deepEqual(syms(Model.sortQuotes([a, bad, b, c], "changePct", false)), ["C", "A", "B", "Z"])
  assert.deepEqual(syms(Model.sortQuotes([c, a, b], "symbol", false)), ["A", "B", "C"])
  assert.deepEqual(syms(Model.sortQuotes([c, a, b], "", true)), ["C", "A", "B"])
  assert.deepEqual(syms(Model.sortQuotes([c, a, b], "bogus", true)), ["C", "A", "B"])
})

// ---- Gist sync

test("parseWatchlist: JSON array, JSON object, and plain text with comments", () => {
  assert.deepEqual(Model.parseWatchlist('["aapl"," nvda","AAPL"]'), ["AAPL", "NVDA"])
  assert.deepEqual(Model.parseWatchlist('{"symbols":["2330.tw","^gspc"]}'), ["2330.TW", "^GSPC"])
  assert.deepEqual(Model.parseWatchlist("AAPL  # core\nnvda, msft\n# tsla\n\nBTC-USD"), ["AAPL", "NVDA", "MSFT", "BTC-USD"])
  assert.deepEqual(Model.parseWatchlist(""), [])
  assert.deepEqual(Model.parseWatchlist("null"), [])
  assert.deepEqual(Model.parseWatchlist('{"other":1}'), [])
})

test("serializeWatchlist round-trips through parseWatchlist", () => {
  const list = ["AAPL", "2330.TW", "^GSPC"]
  assert.deepEqual(Model.parseWatchlist(Model.serializeWatchlist(list)), list)
})

test("normalizeGistId accepts ids and URLs; normalizeGistFile defaults", () => {
  const id = "0123456789abcdef0123456789abcdef"
  assert.equal(Model.normalizeGistId(id), id)
  assert.equal(Model.normalizeGistId("https://gist.github.com/someone/" + id + "/"), id)
  assert.equal(Model.normalizeGistId("nope"), "")
  assert.equal(Model.normalizeGistFile(""), "stocks.json")
  assert.equal(Model.normalizeGistFile("a/b"), "stocks.json")
  assert.equal(Model.normalizeGistFile("list.txt"), "list.txt")
})

test("gist commands run through the sh wrapper with positional args", () => {
  const id = "0123456789abcdef0123456789abcdef"
  const pull = Model.gistPullCommand(id, "stocks.json")
  assert.equal(pull[0], "sh")
  assert.deepEqual(pull.slice(3), ["sh", id, '.files["stocks.json"].content'])
  const push = Model.gistPushCommand(id, "stocks.json", ["AAPL"])
  assert.equal(push[4], id)
  assert.deepEqual(JSON.parse(push[5]), { files: { "stocks.json": { content: Model.serializeWatchlist(["AAPL"]) } } })
  const create = JSON.parse(Model.gistCreateCommand("stocks.json", ["AAPL"])[4])
  assert.equal(create.public, false)
  assert.ok(create.files["stocks.json"].content.includes("AAPL"))
})

test("ghCommand wrapper reports exit code and merged output (real sh)", () => {
  const { execFileSync } = require("node:child_process")
  const run = cmd => Model.parseCommandResult(execFileSync(cmd[0], cmd.slice(1)).toString())
  assert.deepEqual(run(Model.ghCommand('printf "%s" "$1"', ["it's \"quoted\" $HOME"])), { code: 0, output: "it's \"quoted\" $HOME" })
  const failed = run(Model.ghCommand('echo "gh: Not Found (HTTP 404)" >&2; exit 1', []))
  assert.equal(failed.code, 1)
  assert.equal(Model.commandError(failed), "Not Found (HTTP 404)")
  assert.equal(Model.commandError({ code: 127, output: "" }), "gh CLI not found")
  assert.equal(Model.commandError({ code: 1, output: '{"message":"Not Found","status":"404"}gh: Not Found (HTTP 404)' }), "Not Found (HTTP 404)")
  assert.equal(Model.commandError({ code: 1, output: '{"message":"Bad credentials"}' }), "Bad credentials")
  assert.equal(Model.parseCommandResult("garbage").code, -1)
})

// ---- Agent

test("normalizeAgentCommand / normalizeAgentPrompts fall back to defaults", () => {
  assert.deepEqual(Model.normalizeAgentCommand(null), Model.DEFAULT_AGENT_COMMAND)
  assert.deepEqual(Model.normalizeAgentCommand("codex exec {prompt}"), ["codex", "exec", "{prompt}"])
  assert.deepEqual(Model.normalizeAgentPrompts([{ name: "x" }, 3]), Model.DEFAULT_AGENT_PROMPTS)
  assert.deepEqual(Model.normalizeAgentPrompts([{ name: " A ", prompt: " p " }]), [{ name: "A", prompt: "p" }])
})

test("fillPrompt substitutes quote fields, {quote} JSON, and keeps unknown placeholders", () => {
  const q = fullQuote()
  assert.equal(Model.fillPrompt("{symbol} {name} {price} {changePct} {volume} {nope}", q),
    "AAPL Apple Inc. 105.00 +5.00% 1.2M {nope}")
  const json = JSON.parse(Model.fillPrompt("{quote}", q))
  assert.equal(json.symbol, "AAPL")
  assert.equal(json.series, undefined)
})

test("agentArgv substitutes {prompt} or appends it", () => {
  assert.deepEqual(Model.agentArgv(["claude", "-p", "{prompt}"], "hi there"), ["claude", "-p", "hi there"])
  assert.deepEqual(Model.agentArgv(["gemini", "-p"], "x"), ["gemini", "-p", "x"])
  assert.deepEqual(Model.agentArgv(["tool", "--q={prompt}"], "x"), ["tool", "--q=x"])
})

test("agentFileName / formatElapsed", () => {
  assert.equal(Model.agentFileName("^GSPC"), "_GSPC.md")
  assert.equal(Model.agentFileName("EURUSD=X"), "EURUSD=X.md")
  assert.equal(Model.formatElapsed(83), "1:23")
  assert.equal(Model.formatElapsed(null), "0:00")
})

test("agentFileText / parseAgentFile round-trip; plain files pass through", () => {
  const text = Model.agentFileText({ prompt: "Quick take", at: 1700000000000 }, "# Hi\n\nbody")
  assert.deepEqual(Model.parseAgentFile(text), { prompt: "Quick take", at: 1700000000000, output: "# Hi\n\nbody" })
  assert.deepEqual(Model.parseAgentFile("just text"), { prompt: "", at: null, output: "just text" })
})
