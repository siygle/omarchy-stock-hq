# Stocks Bar Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `io.github.al1gat0r.stocks`, an Omarchy Quattro shell plugin that shows a cycling stock-ticker pill in the bar with a click-to-open quotes panel, fed by Yahoo Finance with no API key.

**Architecture:** Three runtime files following the first-party `omarchy.weather` / `omarchy.clock` pattern: `BarWidget.qml` (pill, input, IPC, loads the panel), `Panel.qml` (owns all state: one `curl` `Process`, refresh/cycle/retry timers, popup UI), `Model.js` (pure functions — settings normalization, curl argv, Yahoo JSON parsing, formatting, cycling — unit-tested with `node --test`). Settings live inline on the widget's `shell.json` entry and are read with the inherited `setting()` helper.

**Tech Stack:** Quickshell QML (Qt 6, `qs.Ui`/`qs.Commons` shell imports), plain ES5-style JavaScript (shared by QML engine and Node), `curl`, `node --test`, `qmllint`, `omarchy plugin` CLI.

**Spec:** `docs/superpowers/specs/2026-08-18-stocks-bar-widget-design.md`

## Global Constraints

- Plugin id everywhere (manifest `id`, `moduleName`, IPC target): `io.github.al1gat0r.stocks`. Never use the `omarchy.*` namespace.
- Repo root is the plugin root: `~/omarchy-stocks/`. Installed copy: `~/.config/omarchy/plugins/io.github.al1gat0r.stocks/`. No symlinks anywhere inside the plugin folder.
- Manifest `schemaVersion: 1`; `kinds: ["bar-widget"]`; `entryPoints.barWidget: "BarWidget.qml"`.
- Only runtime dependency beyond the shell: `curl` (already on Omarchy). No `jq`, no shell scripts.
- Model.js must run in both the QML JS engine and Node: ES5-style (`var`, `function`), no `import`/`export`, end with the `if (typeof module !== "undefined") module.exports = {...}` guard exactly like `/usr/share/omarchy/shell/plugins/panels/weather/Model.js`.
- Never edit anything under `/usr/share/omarchy/` (read-only reference).
- Default settings: `symbols = ["AAPL","NVDA","SPCX","GOOGL"]`, `refreshMinutes = 5` (min 1), `cycleSeconds = 10` (0 = pinned), `compact = false`.
- Commit after every task with the trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Verification commands: `node --test test/`, `qmllint -I /usr/share/omarchy/shell <files>`, `omarchy plugin validate <repo>`.

---

## File structure

| File | Responsibility |
|------|----------------|
| `manifest.json` | plugin identity + bar-widget metadata |
| `Model.js` | pure logic: `normalizeSymbols`, `refreshMinutes`, `cycleSeconds`, `chartUrl`, `curlCommand`, `quoteUrl`, `shellQuote`, `parseChartResponse`, `parseQuoteLines`, `isValid`, `isDown`, `validCount`, `firstValidIndex`, `nextIndex`, `shouldRetry`, `formatPrice`, `formatChange`, `barLabel`, `verticalLabel`, `loadingLabel` |
| `test/model.test.js` | `node:test` suite for every Model.js function |
| `Panel.qml` | state owner + popup UI |
| `BarWidget.qml` | bar pill, mouse/wheel input, IPC, panel plumbing |
| `README.md`, `LICENSE`, `preview.png` | marketplace requirements |

---

### Task 1: Model.js — settings normalization

**Files:**
- Create: `Model.js`
- Create: `test/model.test.js`

**Interfaces:**
- Produces: `normalizeSymbols(value, fallback?) -> string[]`, `refreshMinutes(value, fallback?) -> int`, `cycleSeconds(value, fallback?) -> int`, `DEFAULT_SYMBOLS`.

- [ ] **Step 1: Write the failing tests**

`test/model.test.js`:

```js
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/omarchy-stocks && node --test test/`
Expected: FAIL — `Cannot find module '../Model.js'`.

- [ ] **Step 3: Write the minimal implementation**

`Model.js`:

```js
// Pure logic for the Stocks bar widget. No QML imports: this file is loaded
// by Panel.qml/BarWidget.qml through `import "Model.js" as Model` and by the
// node test-suite through require(), so it stays ES5-style and ends with a
// module.exports guard (same convention as omarchy.weather's Model.js).

var DEFAULT_SYMBOLS = ["AAPL", "NVDA", "SPCX", "GOOGL"]

function trimString(value) {
  return String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
}

// Accepts a JSON array (the documented form) or a comma/space/semicolon
// separated string (what `omarchy bar set ... symbols AAPL,NVDA` stores when
// --json is forgotten). Anything else, or an empty result, means the defaults.
function normalizeSymbols(value, fallback) {
  var defaults = fallback || DEFAULT_SYMBOLS
  var list = []
  if (Array.isArray(value)) {
    list = value
  } else if (typeof value === "string") {
    list = value.split(/[\s,;]+/)
  } else if (value && typeof value === "object" && typeof value.length === "number") {
    for (var k = 0; k < value.length; k++) list.push(value[k])
  }

  var out = []
  for (var i = 0; i < list.length; i++) {
    var symbol = trimString(list[i]).toUpperCase()
    if (symbol === "" || out.indexOf(symbol) !== -1) continue
    out.push(symbol)
  }
  return out.length ? out : defaults.slice()
}

function refreshMinutes(value, fallback) {
  var d = fallback === undefined || fallback === null ? 5 : fallback
  var n = parseInt(String(value), 10)
  if (isNaN(n)) return d
  return n < 1 ? 1 : n
}

function cycleSeconds(value, fallback) {
  var d = fallback === undefined || fallback === null ? 10 : fallback
  var n = parseInt(String(value), 10)
  if (isNaN(n) || n < 0) return d
  return n
}

if (typeof module !== "undefined") {
  module.exports = {
    DEFAULT_SYMBOLS: DEFAULT_SYMBOLS,
    normalizeSymbols: normalizeSymbols,
    refreshMinutes: refreshMinutes,
    cycleSeconds: cycleSeconds
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `node --test test/`
Expected: all 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Model.js test/model.test.js
git commit -m "feat(model): settings normalization for symbols/refresh/cycle

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Model.js — curl command and Yahoo response parsing

**Files:**
- Modify: `Model.js` (append functions + export entries)
- Modify: `test/model.test.js` (append tests)

**Interfaces:**
- Consumes: `normalizeSymbols` (Task 1).
- Produces: `chartUrl(symbol) -> string`, `curlCommand(symbols, userAgent) -> string[]`, `quoteUrl(symbol) -> string`, `shellQuote(text) -> string`, `emptyQuote(symbol, error) -> Quote`, `parseChartResponse(line) -> Quote`, `parseQuoteLines(text, symbols) -> Quote[]`.
- `Quote` = `{ symbol, name, currency, exchange, price, prevClose, change, changePct, dayLow, dayHigh, week52Low, week52High, marketTime, error }` — numbers or `null`; `error` is `""` on success.

- [ ] **Step 1: Write the failing tests**

Append to `test/model.test.js`:

```js
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `node --test test/`
Expected: new tests FAIL with `Model.chartUrl is not a function` (and similar).

- [ ] **Step 3: Write the minimal implementation**

Insert into `Model.js` before the `module.exports` guard:

```js
var CHART_URL = "https://query1.finance.yahoo.com/v8/finance/chart/"
var QUOTE_PAGE_URL = "https://finance.yahoo.com/quote/"

function chartUrl(symbol) {
  return CHART_URL + encodeURIComponent(String(symbol)) + "?range=1d&interval=1d"
}

// One curl invocation for every symbol so the shell owns a single child
// process per refresh. `-w "\n"` terminates each response, so stdout is one
// JSON document per line in request order. Deliberately no `-f`: a 404 for an
// unknown symbol then still yields Yahoo's error JSON on its own line instead
// of an empty line, which keeps the other symbols' lines aligned.
function curlCommand(symbols, userAgent) {
  var cmd = ["curl", "-sS", "--max-time", "10", "-A", String(userAgent || "omarchy-stocks"), "-w", "\n"]
  for (var i = 0; i < symbols.length; i++) cmd.push(chartUrl(symbols[i]))
  return cmd
}

function quoteUrl(symbol) {
  return QUOTE_PAGE_URL + encodeURIComponent(String(symbol))
}

function shellQuote(text) {
  return "'" + String(text).replace(/'/g, "'\\''") + "'"
}

function toNumber(value) {
  if (value === undefined || value === null || value === "") return null
  var n = Number(value)
  return isNaN(n) ? null : n
}

function emptyQuote(symbol, error) {
  return {
    symbol: String(symbol || ""),
    name: "",
    currency: "",
    exchange: "",
    price: null,
    prevClose: null,
    change: null,
    changePct: null,
    dayLow: null,
    dayHigh: null,
    week52Low: null,
    week52High: null,
    marketTime: null,
    error: String(error || "")
  }
}

// One line of curl output -> Quote. Never throws.
function parseChartResponse(line) {
  var raw = trimString(line)
  if (raw === "") return emptyQuote("", "No data")

  var data
  try {
    data = JSON.parse(raw)
  } catch (e) {
    return emptyQuote("", "Bad response")
  }

  var chart = data && data.chart
  if (!chart) return emptyQuote("", "Bad response")

  var result = chart.result && chart.result[0]
  if (!result || !result.meta) {
    var code = chart.error && (chart.error.code || chart.error.description)
    return emptyQuote("", code ? String(code) : "No data")
  }

  var meta = result.meta
  var price = toNumber(meta.regularMarketPrice)
  var prev = toNumber(meta.chartPreviousClose)
  if (prev === null) prev = toNumber(meta.previousClose)
  var change = price !== null && prev !== null ? price - prev : null
  var changePct = change !== null && prev ? (change / prev) * 100 : null

  var quote = emptyQuote(meta.symbol, price === null ? "No data" : "")
  quote.name = trimString(meta.shortName || meta.longName || meta.symbol)
  quote.currency = String(meta.currency || "")
  quote.exchange = String(meta.fullExchangeName || meta.exchangeName || "")
  quote.price = price
  quote.prevClose = prev
  quote.change = change
  quote.changePct = changePct
  quote.dayLow = toNumber(meta.regularMarketDayLow)
  quote.dayHigh = toNumber(meta.regularMarketDayHigh)
  quote.week52Low = toNumber(meta.fiftyTwoWeekLow)
  quote.week52High = toNumber(meta.fiftyTwoWeekHigh)
  quote.marketTime = toNumber(meta.regularMarketTime)
  return quote
}

// Whole curl stdout -> one Quote per requested symbol, in request order.
// Successful lines are matched by symbol; error lines carry no symbol, so
// they are attributed by position when curl produced exactly one line per
// symbol. Anything unmatched becomes a "No data" quote.
function parseQuoteLines(text, symbols) {
  var lines = String(text || "").split("\n")
  if (lines.length && lines[lines.length - 1] === "") lines.pop()

  var positional = lines.length === symbols.length
  var bySymbol = {}
  var byIndex = []
  for (var i = 0; i < lines.length; i++) {
    var parsed = parseChartResponse(lines[i])
    byIndex.push(parsed)
    if (!parsed.error && parsed.symbol) bySymbol[parsed.symbol.toUpperCase()] = parsed
  }

  var out = []
  for (var j = 0; j < symbols.length; j++) {
    var symbol = String(symbols[j]).toUpperCase()
    var quote = bySymbol[symbol]
    if (!quote && positional && byIndex[j] && byIndex[j].error) quote = byIndex[j]
    if (!quote) quote = emptyQuote(symbol, "No data")
    quote.symbol = symbol
    out.push(quote)
  }
  return out
}
```

Add to the `module.exports` object: `chartUrl, curlCommand, quoteUrl, shellQuote, emptyQuote, parseChartResponse, parseQuoteLines`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `node --test test/`
Expected: all pass (16 tests).

- [ ] **Step 5: Confirm the curl contract against the live endpoint (evidence, not assumption)**

Run:
```bash
node -e '
const M = require("./Model.js");
const { execFileSync } = require("child_process");
const cmd = M.curlCommand(["AAPL", "NOPE_XYZ", "SPCX"], "Mozilla/5.0 (X11; Linux x86_64) omarchy-stocks/0.1.0");
const out = execFileSync(cmd[0], cmd.slice(1), { encoding: "utf8" });
console.log(M.parseQuoteLines(out, ["AAPL", "NOPE_XYZ", "SPCX"]).map(q => [q.symbol, q.price, q.error]));
'
```
Expected: `[ [ 'AAPL', <number>, '' ], [ 'NOPE_XYZ', null, 'Not Found' ], [ 'SPCX', <number>, '' ] ]`.

- [ ] **Step 6: Commit**

```bash
git add Model.js test/model.test.js
git commit -m "feat(model): curl command and Yahoo chart response parsing

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Model.js — formatting and cycling helpers

**Files:**
- Modify: `Model.js` (append functions + export entries)
- Modify: `test/model.test.js` (append tests)

**Interfaces:**
- Consumes: `Quote` shape, `emptyQuote` (Task 2).
- Produces: `isValid(quote) -> bool`, `isDown(quote) -> bool`, `validCount(quotes) -> int`, `firstValidIndex(quotes) -> int`, `nextIndex(current, quotes, step) -> int`, `shouldRetry(quotes) -> bool`, `formatPrice(price) -> string`, `formatChange(quote) -> string`, `barLabel(quote, compact) -> string`, `verticalLabel(quote) -> string`, `loadingLabel(symbol) -> string`.

- [ ] **Step 1: Write the failing tests**

Append to `test/model.test.js`:

```js
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `node --test test/`
Expected: new tests FAIL with `Model.isValid is not a function` (and similar).

- [ ] **Step 3: Write the minimal implementation**

Insert into `Model.js` before the `module.exports` guard:

```js
function isValid(quote) {
  return !!quote && !quote.error && quote.price !== null && quote.price !== undefined
}

function isDown(quote) {
  return isValid(quote) && quote.change !== null && quote.change !== undefined && quote.change < 0
}

function validCount(quotes) {
  var list = quotes || []
  var n = 0
  for (var i = 0; i < list.length; i++) if (isValid(list[i])) n++
  return n
}

function firstValidIndex(quotes) {
  var list = quotes || []
  for (var i = 0; i < list.length; i++) if (isValid(list[i])) return i
  return -1
}

// Next valid quote index in `step` direction (+1 forward, -1 back), wrapping
// around and skipping failed symbols. -1 when nothing is valid.
function nextIndex(current, quotes, step) {
  var list = quotes || []
  var n = list.length
  if (!n) return -1
  var dir = step < 0 ? -1 : 1
  var hasCurrent = typeof current === "number" && current >= 0 && current < n
  var start = hasCurrent ? current : (dir > 0 ? -1 : 0)
  for (var k = 1; k <= n; k++) {
    var idx = (((start + dir * k) % n) + n) % n
    if (isValid(list[idx])) return idx
  }
  return -1
}

// "Not Found" is permanent (typo or delisted); everything else may be a
// transient network/rate-limit failure worth a quick retry.
function shouldRetry(quotes) {
  var list = quotes || []
  if (!list.length) return true
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].error && list[i].error !== "Not Found") return true
  }
  return false
}

function priceDecimals(price) {
  return Math.abs(price) < 1 ? 4 : 2
}

function withThousands(fixed) {
  var parts = fixed.split(".")
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  return parts.join(".")
}

function formatPrice(price) {
  var n = toNumber(price)
  if (n === null) return ""
  return withThousands(n.toFixed(priceDecimals(n)))
}

function arrowFor(change) {
  if (change < 0) return "▼"
  if (change > 0) return "▲"
  return "•"
}

function formatPercent(changePct) {
  var n = toNumber(changePct)
  return n === null ? "" : Math.abs(n).toFixed(2) + "%"
}

// "▲ +1.28 (0.42%)" for the panel's change column; "" when unknown.
function formatChange(quote) {
  if (!quote) return ""
  var change = toNumber(quote.change)
  if (change === null) return ""
  var decimals = quote.price !== null && quote.price !== undefined ? priceDecimals(quote.price) : 2
  var signed = (change < 0 ? "-" : "+") + Math.abs(change).toFixed(decimals)
  var pct = formatPercent(quote.changePct)
  return arrowFor(change) + " " + signed + (pct ? " (" + pct + ")" : "")
}

// Bar pill text: "AAPL 305.59 ▲0.42%", or "AAPL ▲0.42%" when compact.
function barLabel(quote, compact) {
  if (!quote) return ""
  var symbol = String(quote.symbol || "")
  if (!isValid(quote)) return symbol + " !"
  var parts = [symbol]
  if (!compact) parts.push(formatPrice(quote.price))
  var change = toNumber(quote.change)
  var pct = formatPercent(quote.changePct)
  if (change !== null && pct) parts.push(arrowFor(change) + pct)
  return parts.join(" ")
}

// Vertical bars are only ~28px wide: symbol on one line, direction on the next.
function verticalLabel(quote) {
  if (!quote) return ""
  var symbol = String(quote.symbol || "")
  if (!isValid(quote)) return symbol + "\n!"
  var change = toNumber(quote.change)
  return symbol + "\n" + (change === null ? "•" : arrowFor(change))
}

function loadingLabel(symbol) {
  var s = trimString(symbol)
  return (s ? s + " " : "") + "…"
}
```

Add to the `module.exports` object: `isValid, isDown, validCount, firstValidIndex, nextIndex, shouldRetry, formatPrice, formatChange, barLabel, verticalLabel, loadingLabel`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `node --test test/`
Expected: all pass (23 tests).

- [ ] **Step 5: Commit**

```bash
git add Model.js test/model.test.js
git commit -m "feat(model): price/change formatting and symbol cycling helpers

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: manifest.json + Panel.qml (state owner and popup)

**Files:**
- Create: `manifest.json`
- Create: `Panel.qml`

**Interfaces:**
- Consumes: every Model.js function from Tasks 1–3.
- Produces (read by BarWidget.qml in Task 5): properties `label: string`, `verticalText: string`, `currentIsDown: bool`, `opened: bool` (from base), `popoutSwitchClosing: bool` (from base), writable `bar`, `settings`, `anchorItem`, `hostWidget`; functions `open()`, `close()`, `toggle()`, `closeForPopoutSwitch()` (base), `refresh()`, `stepSymbol(direction)`.

- [ ] **Step 1: Write `manifest.json`**

```json
{
  "schemaVersion": 1,
  "id": "io.github.al1gat0r.stocks",
  "name": "Stocks",
  "version": "0.1.0",
  "author": "al1gat0r",
  "license": "MIT",
  "description": "Stock ticker pill with a quotes panel for the Omarchy bar (Yahoo Finance, no API key).",
  "kinds": ["bar-widget"],
  "entryPoints": {
    "barWidget": "BarWidget.qml"
  },
  "barWidget": {
    "displayName": "Stocks",
    "description": "Cycling stock ticker with a quotes panel",
    "category": "Info",
    "allowMultiple": false,
    "defaultSection": "center"
  }
}
```

- [ ] **Step 2: Write `Panel.qml`**

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// State owner for the Stocks widget: fetches quotes, cycles the bar label,
// and renders the click-to-open panel. BarWidget.qml loads this and mirrors
// `label` / `currentIsDown` into the pill (same split as omarchy.weather).
Panel {
  id: root
  moduleName: "io.github.al1gat0r.stocks"
  // The bar entry (BarWidget.qml) owns the IPC target; see its IpcHandler.
  manageIpc: false

  property var anchorItem: null
  // The bar identifies a panel by the widget mounted in its slot, not by this
  // nested item, so popout switching and the open-panel indicator use it.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Settings (inline on this widget's shell.json entry).
  readonly property var symbols: Model.normalizeSymbols(setting("symbols", null))
  readonly property string symbolsKey: symbols.join(",")
  readonly property int refreshMinutes: Model.refreshMinutes(setting("refreshMinutes", 5))
  readonly property int cycleSeconds: Model.cycleSeconds(setting("cycleSeconds", 10))
  readonly property bool compact: setting("compact", false) === true || String(setting("compact", false)) === "true"

  // ---- Fetch state. `quotes` keeps the last good result across failures so
  //      stale-but-useful numbers stay visible; `fetchError` explains why.
  property var quotes: []
  property string fetchError: ""
  property var lastUpdated: null
  property int cycleIndex: 0
  property int retries: 0

  readonly property string userAgent: "Mozilla/5.0 (X11; Linux x86_64) omarchy-stocks/0.1.0"
  readonly property bool loading: quotes.length === 0 && fetchError === ""
  readonly property int validCount: Model.validCount(quotes)
  readonly property var currentQuote: cycleIndex >= 0 && cycleIndex < quotes.length ? quotes[cycleIndex] : null
  readonly property string label: quotes.length > 0
    ? Model.barLabel(currentQuote, compact)
    : Model.loadingLabel(symbols.length ? symbols[0] : "")
  readonly property string verticalText: quotes.length > 0
    ? Model.verticalLabel(currentQuote)
    : (symbols.length ? symbols[0] + "\n…" : "…")
  readonly property bool currentIsDown: Model.isDown(currentQuote)

  // ---- Presentation helpers shared by every row.
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color mutedForeground: Qt.darker(barForeground, 1.5)
  readonly property color urgentForeground: bar ? bar.urgent : Color.urgent

  function open() {
    root.controller.show()
    refresh()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // A user-driven refresh gets a fresh retry budget.
  function refresh() {
    retries = 0
    startFetch()
  }

  function startFetch() {
    if (fetchProc.running) return
    fetchProc.command = Model.curlCommand(symbols, userAgent)
    fetchProc.running = true
  }

  function handleFetchOutput(text) {
    var raw = String(text || "")
    if (raw.replace(/\s+/g, "") === "") {
      // curl produced nothing (offline, DNS down): keep showing what we had.
      fetchError = "No response from Yahoo Finance"
      scheduleRetry()
      return
    }

    var parsed = Model.parseQuoteLines(raw, symbols)
    if (Model.validCount(parsed) === 0) {
      fetchError = parsed.length ? parsed[0].error : "No data"
      // Nothing better to show yet: surface the per-symbol errors as rows.
      if (quotes.length === 0) quotes = parsed
      if (Model.shouldRetry(parsed)) scheduleRetry()
      return
    }

    quotes = parsed
    lastUpdated = new Date()
    fetchError = ""
    retries = 0
  }

  function scheduleRetry() {
    if (retries >= 3) return
    retries++
    retryTimer.restart()
  }

  // Right-click / wheel / IPC: move to the next (or previous) valid symbol and
  // restart the cycle so the chosen one stays up for a full period.
  function stepSymbol(direction) {
    var next = Model.nextIndex(cycleIndex, quotes, direction)
    if (next >= 0) cycleIndex = next
    if (cycleTimer.running) cycleTimer.restart()
  }

  function openQuotePage(symbol) {
    if (root.bar && typeof root.bar.run === "function")
      root.bar.run("xdg-open " + Model.shellQuote(Model.quoteUrl(symbol)))
  }

  // Settings edits that change the symbol list invalidate everything shown.
  // Keyed on the joined string so re-injected-but-identical settings (any
  // shell.json save) do not trigger a refetch.
  onSymbolsKeyChanged: {
    cycleIndex = 0
    quotes = []
    fetchError = ""
    lastUpdated = null
    retries = 0
    fetchProc.running = false
    Qt.callLater(root.startFetch)
  }

  // Keep the pill on a valid symbol when the list shrinks or a symbol fails.
  onQuotesChanged: {
    if (!Model.isValid(currentQuote)) {
      var first = Model.firstValidIndex(quotes)
      cycleIndex = first >= 0 ? first : 0
    }
  }

  // Deferred so the first fetch sees the settings BarWidget injects right
  // after this component loads (Loader.onLoaded runs before callLater fires).
  Component.onCompleted: Qt.callLater(root.startFetch)

  Process {
    id: fetchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleFetchOutput(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // curl's own message ("Could not resolve host…") beats a generic one,
        // but only while we are in an error state.
        var message = String(text || "").split("\n")[0].replace(/^curl:\s*\(\d+\)\s*/, "").trim()
        if (message !== "" && root.fetchError !== "" && root.validCount === 0) root.fetchError = message
      }
    }
  }

  Timer {
    id: retryTimer
    interval: 2500
    onTriggered: root.startFetch()
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: cycleTimer
    interval: Math.max(1000, root.cycleSeconds * 1000)
    running: root.cycleSeconds > 0 && root.validCount > 1
    repeat: true
    onTriggered: root.cycleIndex = Model.nextIndex(root.cycleIndex, root.quotes, 1)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onReturnRequested: root.refresh()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        // ---- Header: title left, freshness right.
        Item {
          width: parent.width
          height: headerTitle.implicitHeight

          Text {
            id: headerTitle
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            text: "Stocks"
            color: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.baseline: headerTitle.baseline
            text: root.lastUpdated
              ? "Updated " + Qt.formatTime(root.lastUpdated, "HH:mm")
              : (root.loading ? "Loading…" : "")
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        PanelSeparator { foreground: root.barForeground }

        // ---- One row per symbol: SYM · name · price · change.
        Column {
          width: parent.width
          spacing: 0

          Repeater {
            model: root.quotes

            Rectangle {
              id: row
              required property var modelData
              required property int index
              readonly property bool valid: Model.isValid(modelData)
              readonly property bool down: Model.isDown(modelData)
              readonly property bool current: index === root.cycleIndex

              width: parent.width
              height: symbolText.implicitHeight + Style.space(12)
              radius: Style.cornerRadius
              color: rowMouse.containsMouse
                ? Style.hoverFillFor(root.barForeground, Color.accent)
                : (row.current ? Style.normalFillFor(root.barForeground, Color.accent) : "transparent")

              Text {
                id: symbolText
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(72)
                text: row.modelData.symbol
                elide: Text.ElideRight
                color: row.valid ? root.barForeground : root.mutedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                anchors.left: symbolText.right
                anchors.right: priceText.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: row.valid ? row.modelData.name : (row.modelData.error || "No data")
                elide: Text.ElideRight
                color: root.mutedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.italic: !row.valid
              }

              Text {
                id: priceText
                anchors.right: changeText.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(80)
                horizontalAlignment: Text.AlignRight
                text: row.valid ? Model.formatPrice(row.modelData.price) : ""
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                id: changeText
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(120)
                horizontalAlignment: Text.AlignRight
                text: row.valid ? Model.formatChange(row.modelData) : ""
                color: row.down ? root.urgentForeground : root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: row.valid ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (row.valid) root.openQuotePage(row.modelData.symbol)
              }
            }
          }
        }

        Text {
          visible: root.loading
          leftPadding: Style.space(8)
          text: "Fetching quotes…"
          color: root.mutedForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.italic: true
        }

        PanelSeparator { foreground: root.barForeground }

        // ---- Footer: the failure reason when there is one, hints otherwise.
        Text {
          width: parent.width
          leftPadding: Style.space(8)
          rightPadding: Style.space(8)
          text: root.fetchError !== ""
            ? "Could not update: " + root.fetchError
            : "Click a row for details · Middle-click the pill to refresh"
          wrapMode: Text.WordWrap
          color: root.fetchError !== "" ? root.urgentForeground : root.mutedForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
```

- [ ] **Step 3: Lint**

Run: `qmllint -I /usr/share/omarchy/shell Panel.qml`
Expected: no errors (warnings about unqualified access are acceptable only if the first-party weather panel produces the same class of warning — compare with `qmllint -I /usr/share/omarchy/shell /usr/share/omarchy/shell/plugins/panels/weather/Panel.qml`). Fix any real error (unknown property, missing import) before continuing.

- [ ] **Step 4: Commit**

```bash
git add manifest.json Panel.qml
git commit -m "feat: manifest and quotes panel (fetch, cycle, popup)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: BarWidget.qml + validation

**Files:**
- Create: `BarWidget.qml`

**Interfaces:**
- Consumes: Panel.qml's `label`, `verticalText`, `currentIsDown`, `opened`, `popoutSwitchClosing`, `open()`, `close()`, `toggle()`, `closeForPopoutSwitch()`, `refresh()`, `stepSymbol(direction)`; writable `bar`, `settings`, `anchorItem`, `hostWidget`.
- Produces: the shell's bar-widget contract (`opened`, `open()`, `close()`, `closeForPopoutSwitch()`, `popoutSwitchClosing`) plus IPC target `io.github.al1gat0r.stocks` with `open/close/show/hide/toggle/refresh/next/prev`.

- [ ] **Step 1: Write `BarWidget.qml`**

```qml
import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar entry for the Stocks widget: a text pill that mirrors the panel's
// cycling label. Panel plumbing follows omarchy.weather / omarchy.clock so
// `omarchy-shell shell summon|hide|toggle io.github.al1gat0r.stocks` route
// here through the bar's open/close/opened contract.
BarWidget {
  id: root
  moduleName: "io.github.al1gat0r.stocks"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function nextSymbol() {
    if (panelLoader.item && panelLoader.item.stepSymbol) panelLoader.item.stepSymbol(1)
  }

  function prevSymbol() {
    if (panelLoader.item && panelLoader.item.stepSymbol) panelLoader.item.stepSymbol(-1)
  }

  // Shape contract for shell.summon/hide/toggle routing (the bar requires
  // open/close/opened on the bar-widget root).
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity (Bar.requestPopout prefers closeForPopoutSwitch over close).
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property string pillText: panelLoader.item
    ? (root.vertical ? panelLoader.item.verticalText : panelLoader.item.label)
    : ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.al1gat0r.stocks"

    function refresh(): void { root.broadcast("refresh") }
    function next(): void { root.broadcast("nextSymbol") }
    function prev(): void { root.broadcast("prevSymbol") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.pillText
    // Theme "urgent" color while the shown symbol is down; plain otherwise.
    active: panelLoader.item ? panelLoader.item.currentIsDown === true : false
    // The panel is the detail view, so no tooltip (as with omarchy.weather).
    tooltipText: ""

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else if (b === Qt.RightButton) root.nextSymbol()
      else root.togglePanel()
    }

    onWheelMoved: function(delta) {
      if (delta > 0) root.prevSymbol()
      else if (delta < 0) root.nextSymbol()
    }
  }
}
```

- [ ] **Step 2: Lint both QML files**

Run: `qmllint -I /usr/share/omarchy/shell BarWidget.qml Panel.qml`
Expected: no errors.

- [ ] **Step 3: Validate the plugin folder**

Run: `omarchy plugin validate ~/omarchy-stocks`
Expected: success message (manifest parses; id/kind/entry point OK; no symlinks; QML lints).

- [ ] **Step 4: Commit**

```bash
git add BarWidget.qml
git commit -m "feat: bar pill widget with panel plumbing, input and IPC

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Install into the running shell and verify live

**Files:**
- Create: `preview.png` (screenshot)
- Modify: `~/.config/omarchy/shell.json` (via `omarchy` commands only — never by hand here)

**Interfaces:**
- Consumes: the whole plugin.

- [ ] **Step 1: Install from the local repo (git clone into the plugins dir)**

Run:
```bash
omarchy plugin add ~/omarchy-stocks --enable --yes
omarchy plugin list --json | jq '.[] | select(.id == "io.github.al1gat0r.stocks")'
```
Expected: the plugin appears with `enabled: true` (or equivalent) and a layout entry exists: `jq '.bar.layout.center' ~/.config/omarchy/shell.json` includes `{"id": "io.github.al1gat0r.stocks"}`.

If `add` refuses a bare path, use `file://~/omarchy-stocks`.

- [ ] **Step 2: Watch the log while it loads**

Run: `qs log -p /usr/share/omarchy/shell --tail 60 2>&1 | grep -i -E "stocks|error|warning" | tail -30`
Expected: no `TypeError`, `ReferenceError`, or "Cannot assign" lines mentioning `io.github.al1gat0r.stocks`. Fix and re-sync (`rsync -a --delete --exclude .git ./ ~/.config/omarchy/plugins/io.github.al1gat0r.stocks/`) until clean.

- [ ] **Step 3: Exercise the panel lifecycle over IPC**

Run:
```bash
omarchy-shell shell summon io.github.al1gat0r.stocks '{}'; sleep 2
grim -o "$(hyprctl monitors -j | jq -r '.[0].name')" /tmp/omarchy-stocks-dev/stocks-open.png
omarchy-shell shell hide io.github.al1gat0r.stocks
omarchy-shell io.github.al1gat0r.stocks refresh
omarchy-shell io.github.al1gat0r.stocks next
```
Expected: `summon` returns `ok`; the screenshot shows the pill (e.g. `AAPL 305.59 ▼0.11%`) and the open panel with one row per symbol; `hide` closes it; `refresh`/`next` return without error. Inspect the screenshot with the Read tool.

- [ ] **Step 4: Settings round-trip without restart**

Run:
```bash
omarchy bar set io.github.al1gat0r.stocks symbols '["SPY","QQQ","NOPE_XYZ"]' --json; sleep 4
omarchy-shell shell summon io.github.al1gat0r.stocks '{}'; sleep 1
grim -o "$(hyprctl monitors -j | jq -r '.[0].name')" /tmp/omarchy-stocks-dev/stocks-settings.png
omarchy-shell shell hide io.github.al1gat0r.stocks
omarchy bar set io.github.al1gat0r.stocks compact true --json
omarchy bar set io.github.al1gat0r.stocks symbols '["AAPL","NVDA","SPCX","GOOGL"]' --json
omarchy bar set io.github.al1gat0r.stocks compact false --json
```
Expected: the screenshot shows SPY/QQQ rows with prices and a muted `NOPE_XYZ  Not Found` row; the pill never shows NOPE_XYZ; the compact toggle drops the price from the pill; the last two commands restore the defaults.

- [ ] **Step 5: Save the preview screenshot into the repo**

Crop is optional; a full-screen shot with the panel open is acceptable. Run:
```bash
cp /tmp/omarchy-stocks-dev/stocks-open.png preview.png
```

- [ ] **Step 6: Commit**

```bash
git add preview.png
git commit -m "docs: add preview screenshot

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: README.md and LICENSE

**Files:**
- Create: `README.md`
- Create: `LICENSE`

- [ ] **Step 1: Write `LICENSE`** (MIT, year 2026, holder `al1gat0r`)

```
MIT License

Copyright (c) 2026 al1gat0r

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Write `README.md`**

````markdown
# Stocks for Omarchy

A stock ticker for the Omarchy Quattro bar. The pill cycles through your
symbols (`AAPL 305.59 ▲0.42%`) and turns the theme's urgent color when the
shown stock is down; click it for a panel with every symbol's price and change.
Quotes come from Yahoo Finance — no API key.

![preview](preview.png)

## Install

```sh
omarchy plugin add https://github.com/al1gat0r/omarchy-stocks.git --enable
```

The widget lands in the bar's center section. Move it with:

```sh
omarchy bar move io.github.al1gat0r.stocks --section right
```

## Usage

| action | effect |
|--------|--------|
| left click | open / close the quotes panel (Esc closes, Tab switches panels) |
| middle click | refresh now |
| right click / scroll | show the next / previous symbol |
| click a row in the panel | open the symbol on finance.yahoo.com |

IPC (for keybindings): `omarchy-shell io.github.al1gat0r.stocks toggle|refresh|next|prev`

## Configure

Settings live on the widget's entry in `~/.config/omarchy/shell.json` and apply
instantly:

```sh
omarchy bar set io.github.al1gat0r.stocks symbols '["AAPL","MSFT","BTC-USD","^GSPC"]' --json
omarchy bar set io.github.al1gat0r.stocks refreshMinutes 2
omarchy bar set io.github.al1gat0r.stocks cycleSeconds 15     # 0 pins the first symbol
omarchy bar set io.github.al1gat0r.stocks compact true --json # "AAPL ▲0.42%" without the price
```

| key | default | meaning |
|-----|---------|---------|
| `symbols` | `["AAPL","NVDA","SPCX","GOOGL"]` | any Yahoo Finance symbols (stocks, ETFs, `BTC-USD`, `EURUSD=X`, `^GSPC`); a comma-separated string also works |
| `refreshMinutes` | `5` | quote refresh interval (minimum 1) |
| `cycleSeconds` | `10` | seconds each symbol stays in the pill; `0` = never rotate |
| `compact` | `false` | drop the price from the pill |

Unknown symbols show as `Not Found` in the panel and are skipped by the pill.

## Develop

```sh
git clone https://github.com/al1gat0r/omarchy-stocks.git
cd omarchy-stocks
node --test test/                                          # Model.js unit tests
qmllint -I /usr/share/omarchy/shell BarWidget.qml Panel.qml
omarchy plugin validate "$PWD"
omarchy plugin add "$PWD" --enable                         # installs a clone into ~/.config/omarchy/plugins/
rsync -a --delete --exclude .git ./ ~/.config/omarchy/plugins/io.github.al1gat0r.stocks/   # hot-reload your edits
qs log -p /usr/share/omarchy/shell --tail 100              # shell log
```

## Remove

```sh
omarchy plugin remove io.github.al1gat0r.stocks
```

## License

MIT
````

- [ ] **Step 3: Re-validate and commit**

Run: `omarchy plugin validate ~/omarchy-stocks && node --test test/`
Expected: validation passes; all tests pass.

```bash
git add README.md LICENSE
git commit -m "docs: README and MIT license

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Sync the installed copy to the final commit**

Run:
```bash
omarchy plugin update io.github.al1gat0r.stocks --yes || rsync -a --delete --exclude .git ./ ~/.config/omarchy/plugins/io.github.al1gat0r.stocks/
omarchy plugin list --json | jq '.[] | select(.id == "io.github.al1gat0r.stocks") | {id, version, enabled}'
```
Expected: installed version `0.1.0`, enabled.

---

## Self-review

- **Spec coverage:** settings (T1), data source + parsing (T2), formatting/cycling (T3), Panel state machine + UI + error table (T4), BarWidget contract/input/IPC/urgent color (T5), install/verify/settings round-trip/preview (T6), README/LICENSE (T7). Vertical-bar label is covered by `verticalLabel` (T3) and `pillText` (T5).
- **Placeholders:** none; every step has concrete code or commands.
- **Type consistency:** `stepSymbol(direction)` (Panel) ↔ `nextSymbol()/prevSymbol()` (BarWidget) ↔ `Model.nextIndex(current, quotes, step)`; `label`/`verticalText`/`currentIsDown` names identical in T4 and T5; `Model.emptyQuote` exported in T2 and used by T3's tests.

---

## Revision 2 — ticker tape + charts (supersedes Tasks 5–7 where they overlap)

Approved mid-execution after Task 5. Tasks 1–5 stand (their code is reused);
Task 6/7 are re-run after the tasks below. Implementation code for these tasks
lives in the corresponding commits on `feat/stocks-widget` (the executor is the
plan author, working inline); each task still lists files, interfaces, tests
and verification.

### Task 8: Model.js — ranges, series, tape, chart geometry (TDD)
- Modify `Model.js`, `test/model.test.js`.
- Add the functions listed under "Model.js additions" in the spec's Revision 2.
- `chartUrl("AAPL")` now yields `?range=1d&interval=5m` (update the Task 2 test).
- Tests: range validation; interval mapping; url per range; tickerWidth/scrollSpeed clamps; series parsing skips nulls and reads open/volume; `parseSeriesLines`; bounds/direction/points on a 3-point series (exact x/y); `valueToY` inside/outside; `tapeItems` skips invalid + compact form + down flag; `formatVolume` thresholds.
- Verify: `node --test test/model.test.js` all green. Commit.

### Task 9: Panel.qml v2 — range chips, sparklines, detail block, chart fetch
- Rewrite the UI section of `Panel.qml`; keep the fetch/retry state machine.
- New state: `selectedIndex`, `activeRange`, `chartSeries` (map), `chartLoading`; `chartProc` (second `Process`); `seriesFor(symbol)`; `selectRange(range)` persists via `bar.shell.updateEntryInline`.
- Exposes to BarWidget: `label`, `verticalText`, `tapeItems` (array), `opened`, `open/close/toggle/closeForPopoutSwitch`, `refresh()`.
- Verify: `qmllint -I /usr/share/omarchy/shell Panel.qml` exit 0. Commit.

### Task 10: BarWidget.qml v2 — scrolling tape
- Replace the pill with the tape viewport inside `WidgetButton` (label hidden unless vertical/fallback); `tickerWidth`, `scrollSpeed`, `compact` read via `setting()`; hover/right-click pause; IPC `pause`.
- Verify: renamed-copy lint of the file minus the IpcHandler block exits 0; `omarchy plugin validate` exit 0. Commit.

### Task 11: Live install + verification (re-run of Task 6 with v2 checks)
- Sync the installed clone (`git -C ~/.config/omarchy/plugins/io.github.al1gat0r.stocks pull`), `omarchy-shell shell rescanPlugins`, `omarchy plugin enable io.github.al1gat0r.stocks`.
- Screenshot the tape and the open panel; exercise `omarchy-shell shell summon/hide`, `omarchy-shell io.github.al1gat0r.stocks refresh|pause`, range chip click via `omarchy bar set … chartRange 1mo`, symbols round-trip incl. a bad symbol; check `qs log` for plugin errors. Save `preview.png`. Commit.

### Task 12: README/LICENSE (re-run of Task 7 with v2 settings table: `symbols`, `refreshMinutes`, `compact`, `tickerWidth`, `scrollSpeed`, `chartRange`) and merge to `main`.
