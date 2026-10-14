// Pure logic for the Stocks bar widget. No QML imports: this file is loaded
// by Panel.qml/BarWidget.qml through `import "Model.js" as Model` and by the
// node test-suite through require(), so it stays ES5-style and ends with a
// module.exports guard (same convention as omarchy.weather's Model.js).

var DEFAULT_SYMBOLS = ["AAPL", "NVDA", "SPCX", "GOOGL"]

// Free quote source: Yahoo Finance's chart endpoint already covers many Asian
// markets. Users may enter native Yahoo symbols (2330.TW, 0700.HK, 7203.T) or
// friendlier market-prefixed forms below.
var ASIA_MARKET_SUFFIXES = {
  "TW": ".TW", "TPE": ".TW",       // Taiwan Stock Exchange, e.g. TW:2330 -> 2330.TW
  "TWO": ".TWO", "TPEX": ".TWO",   // Taipei Exchange, e.g. TWO:6488 -> 6488.TWO
  "HK": ".HK", "HKG": ".HK",       // Hong Kong, e.g. HK:0700 -> 0700.HK
  "JP": ".T", "TYO": ".T",         // Tokyo, e.g. JP:7203 -> 7203.T
  "KS": ".KS", "KR": ".KS",        // Korea Stock Exchange, e.g. KR:005930 -> 005930.KS
  "KQ": ".KQ",                       // KOSDAQ
  "SS": ".SS", "SH": ".SS",        // Shanghai
  "SZ": ".SZ",                       // Shenzhen
  "SI": ".SI", "SG": ".SI",        // Singapore
  "BK": ".BK", "TH": ".BK",        // Thailand
  "JK": ".JK", "ID": ".JK",        // Indonesia
  "KL": ".KL", "MY": ".KL",        // Malaysia
  "AX": ".AX", "AU": ".AX"         // Australia
}

function trimString(value) {
  return String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
}

// Accepts a JSON array (the documented form) or a comma/space/semicolon
// separated string (what `omarchy bar set ... symbols AAPL,NVDA` stores when
// --json is forgotten). Anything else, or an empty result, means the defaults.
function normalizeSymbol(value) {
  var symbol = trimString(value).toUpperCase()
  if (symbol === "") return ""

  // TW:2330 / HK:0700 / JP:7203 etc. -> Yahoo suffixes.
  var prefixed = symbol.match(/^([A-Z]+)[:/](.+)$/)
  if (prefixed && ASIA_MARKET_SUFFIXES[prefixed[1]]) {
    var code = prefixed[2].replace(/\s+/g, "")
    if (code !== "") return code + ASIA_MARKET_SUFFIXES[prefixed[1]]
  }

  // Common Taiwan shorthand: tw2330 / tw-2330 / tw.2330 -> 2330.TW.
  var tw = symbol.match(/^TW[.\-_ ]?([0-9A-Z]+)$/)
  if (tw) return tw[1] + ".TW"

  return symbol
}

function listFromValue(value) {
  var list = []
  if (Array.isArray(value)) {
    list = value
  } else if (typeof value === "string") {
    list = value.split(/[\s,;]+/)
  } else if (value && typeof value === "object" && typeof value.length === "number") {
    for (var k = 0; k < value.length; k++) list.push(value[k])
  }
  return list
}

function normalizeSymbols(value, fallback) {
  var defaults = fallback || DEFAULT_SYMBOLS
  var list = listFromValue(value)
  var out = []
  for (var i = 0; i < list.length; i++) {
    var symbol = normalizeSymbol(list[i])
    if (symbol === "" || out.indexOf(symbol) !== -1) continue
    out.push(symbol)
  }
  return out.length ? out : defaults.slice()
}

var DEFAULT_WATCHLIST_NAME = "Main"

function normalizeWatchlists(value, fallbackSymbols) {
  var out = []
  var list = listFromValue(value)
  for (var i = 0; i < list.length; i++) {
    var item = list[i] || {}
    var name = trimString(item.name || item.label || ("List " + (i + 1)))
    var symbols = normalizeSymbols(item.symbols, [])
    if (symbols.length) out.push({ name: name || ("List " + (i + 1)), symbols: symbols })
  }
  if (out.length) return out
  return [{ name: DEFAULT_WATCHLIST_NAME, symbols: normalizeSymbols(fallbackSymbols, DEFAULT_SYMBOLS) }]
}

function activeWatchlistIndex(value, watchlists) {
  var list = watchlists || []
  if (!list.length) return 0
  var n = parseInt(String(value), 10)
  if (isNaN(n) || n < 0 || n >= list.length) return 0
  return n
}

function cloneWatchlists(watchlists) {
  var list = watchlists || []
  var out = []
  for (var i = 0; i < list.length; i++) out.push({ name: String(list[i].name || ("List " + (i + 1))), symbols: normalizeSymbols(list[i].symbols, []) })
  return out
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

var CHART_URL = "https://query1.finance.yahoo.com/v8/finance/chart/"
var QUOTE_PAGE_URL = "https://finance.yahoo.com/quote/"

// Panel chart ranges and the Yahoo bar interval that keeps each one at a
// sensible point count (79 / 131 / 21 / 125 / 53 points respectively).
var CHART_RANGES = ["1d", "5d", "1mo", "6mo", "1y"]
var CHART_INTERVALS = { "1d": "5m", "5d": "15m", "1mo": "1d", "6mo": "1d", "1y": "1wk" }

function chartRange(value, fallback) {
  var d = fallback === undefined || fallback === null ? "1d" : fallback
  var r = trimString(value).toLowerCase()
  return CHART_RANGES.indexOf(r) === -1 ? d : r
}

function chartInterval(range) {
  return CHART_INTERVALS[range] || "1d"
}

// The quote fetch always uses range=1d (previousClose there is the prior
// session's close); other ranges are only used for chart series.
function chartUrl(symbol, range) {
  var r = chartRange(range)
  return CHART_URL + encodeURIComponent(String(symbol)) + "?range=" + r + "&interval=" + chartInterval(r)
}

function tickerWidth(value, fallback) {
  var d = fallback === undefined || fallback === null ? 180 : fallback
  var n = parseInt(String(value), 10)
  if (isNaN(n)) return d
  return n < 80 ? 80 : n
}

function scrollSpeed(value, fallback) {
  var d = fallback === undefined || fallback === null ? 20 : fallback
  var n = parseFloat(String(value))
  if (isNaN(n) || n < 0) return d
  return n
}

// One curl invocation for every symbol so the shell owns a single child
// process per refresh. `-w "\n"` terminates each response, so stdout is one
// JSON document per line in request order. Deliberately no `-f`: a 404 for an
// unknown symbol then still yields Yahoo's error JSON on its own line instead
// of an empty line, which keeps the other symbols' lines aligned.
// Watchlist symbols are user data: they must not show up in any process
// command line (ps/proc are world-readable). The URLs reach curl as a config
// file on stdin (`-K -`); argv only carries fixed flags, the user agent and
// the payload byte length. Returns { command, stdin }.
function curlCommand(symbols, userAgent, range) {
  var config = ""
  for (var i = 0; i < symbols.length; i++) config += "url = " + JSON.stringify(chartUrl(symbols[i], range)) + "\n"
  return stdinCommand("head -c \"$1\" | curl -sS --max-time 10 -A \"$2\" -w '\\n' -K -",
    [String(utf8Length(config)), String(userAgent || "omarchy-stock-hq")], config)
}

// UTF-8 byte length (QML's JS engine has no TextEncoder/Buffer).
function utf8Length(text) {
  var s = String(text), n = 0
  for (var i = 0; i < s.length; i++) {
    var c = s.charCodeAt(i)
    if (c < 0x80) n += 1
    else if (c < 0x800) n += 2
    else if (c >= 0xD800 && c <= 0xDBFF) { n += 4; i++ }
    else n += 3
  }
  return n
}

// A command whose sensitive payload is written to the Process stdin instead of
// argv. StdinProcess closes stdin after the write; reading exactly `$1` bytes
// (`head -c "$1"`) also keeps the payload intact without relying on that EOF.
function stdinCommand(script, args, payload) {
  return { command: ["sh", "-c", script, "sh"].concat(args || []), stdin: String(payload) }
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
    open: null,
    volume: null,
    series: [],
    candles: [],
    error: String(error || "")
  }
}

function quoteBlock(result) {
  return result && result.indicators && result.indicators.quote ? result.indicators.quote[0] : null
}

// timestamp[] + indicators.quote[0].close[] -> [{t, c}], nulls skipped
// (Yahoo leaves the in-progress bar and market holidays as null).
function parseSeries(result) {
  var stamps = result && result.timestamp ? result.timestamp : []
  var block = quoteBlock(result)
  var closes = block && block.close ? block.close : []
  var out = []
  for (var i = 0; i < stamps.length && i < closes.length; i++) {
    var t = toNumber(stamps[i])
    var c = toNumber(closes[i])
    if (t === null || c === null) continue
    out.push({ t: t, c: c })
  }
  return out
}

// Full OHLCV candles for technical analysis. Keeps rows where at least close is
// known; high/low/open/volume may be null on sparse provider responses.
function parseCandles(result) {
  var stamps = result && result.timestamp ? result.timestamp : []
  var block = quoteBlock(result)
  var opens = block && block.open ? block.open : []
  var highs = block && block.high ? block.high : []
  var lows = block && block.low ? block.low : []
  var closes = block && block.close ? block.close : []
  var volumes = block && block.volume ? block.volume : []
  var out = []
  for (var i = 0; i < stamps.length && i < closes.length; i++) {
    var t = toNumber(stamps[i])
    var c = toNumber(closes[i])
    if (t === null || c === null) continue
    out.push({
      t: t,
      o: toNumber(opens[i]),
      h: toNumber(highs[i]),
      l: toNumber(lows[i]),
      c: c,
      v: toNumber(volumes[i])
    })
  }
  return out
}

function firstOpen(result) {
  var quoteBlock = result && result.indicators && result.indicators.quote ? result.indicators.quote[0] : null
  var opens = quoteBlock && quoteBlock.open ? quoteBlock.open : []
  for (var i = 0; i < opens.length; i++) {
    var o = toNumber(opens[i])
    if (o !== null) return o
  }
  return null
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
  // previousClose is the prior session's close whenever Yahoo sends it
  // (intraday ranges); chartPreviousClose is the close before the *range*,
  // which only coincides with it for range=1d.
  var prev = toNumber(meta.previousClose)
  if (prev === null) prev = toNumber(meta.chartPreviousClose)
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
  quote.open = firstOpen(result)
  quote.volume = toNumber(meta.regularMarketVolume)
  quote.series = parseSeries(result)
  quote.candles = parseCandles(result)
  return quote
}

// Chart-range fetch -> { SYM: series }. Reuses parseQuoteLines for the
// symbol/position matching; only the series is kept.
function parseSeriesLines(text, symbols) {
  var quotes = parseQuoteLines(text, symbols)
  var out = {}
  for (var i = 0; i < quotes.length; i++) out[quotes[i].symbol] = quotes[i].series || []
  return out
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

function isValid(quote) {
  return !!quote && !quote.error && quote.price !== null && quote.price !== undefined
}

function isDown(quote) {
  return isValid(quote) && quote.change !== null && quote.change !== undefined && quote.change < 0
}

function isUp(quote) {
  return isValid(quote) && quote.change !== null && quote.change !== undefined && quote.change > 0
}

function validCount(quotes) {
  var list = quotes || []
  var n = 0
  for (var i = 0; i < list.length; i++) if (isValid(list[i])) n++
  return n
}

function quoteRowsForSymbols(quotes, symbols, missingError) {
  var rows = quotes || []
  var syms = normalizeSymbols(symbols, [])
  if (!syms.length) return rows
  var bySymbol = {}
  for (var i = 0; i < rows.length; i++) {
    if (rows[i] && rows[i].symbol) bySymbol[String(rows[i].symbol).toUpperCase()] = rows[i]
  }
  var out = []
  for (var j = 0; j < syms.length; j++) out.push(bySymbol[syms[j]] || emptyQuote(syms[j], missingError || "No cached data"))
  return out
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

// ---- Chart geometry (pure so Canvas painting stays trivial and testable).

function seriesBounds(series) {
  var list = series || []
  if (!list.length) return null
  var min = list[0].c
  var max = list[0].c
  for (var i = 1; i < list.length; i++) {
    if (list[i].c < min) min = list[i].c
    if (list[i].c > max) max = list[i].c
  }
  return { min: min, max: max }
}

function seriesDirection(series) {
  var list = series || []
  if (list.length < 2) return 0
  return list[list.length - 1].c - list[0].c
}

function scaleY(value, bounds, height, padding) {
  var span = bounds.max - bounds.min
  var inner = height - padding * 2
  if (span <= 0) return padding + inner / 2
  return padding + ((bounds.max - value) / span) * inner
}

// x is proportional to time (so weekend gaps in a 5d series read correctly),
// y is scaled between the series' min (bottom) and max (top).
function seriesPoints(series, width, height, padding) {
  var list = series || []
  var bounds = seriesBounds(list)
  if (!bounds) return []
  var pad = padding || 0
  var t0 = list[0].t
  var t1 = list[list.length - 1].t
  var span = t1 - t0
  var innerW = width - pad * 2
  var out = []
  for (var i = 0; i < list.length; i++) {
    var x = span > 0 ? pad + ((list[i].t - t0) / span) * innerW : pad
    out.push({ x: x, y: scaleY(list[i].c, bounds, height, pad) })
  }
  return out
}

// y for a reference value (e.g. previous close) or null when it would fall
// outside the plotted bounds.
function valueToY(value, bounds, height, padding) {
  var v = toNumber(value)
  if (v === null || !bounds) return null
  if (v < bounds.min || v > bounds.max) return null
  return scaleY(v, bounds, height, padding || 0)
}

// ---- Technical analysis MVP.

function closeValues(series) {
  var list = series || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var c = toNumber(list[i].c)
    if (c !== null) out.push(c)
  }
  return out
}

function smaValue(values, period) {
  var list = values || []
  var p = parseInt(String(period), 10)
  if (isNaN(p) || p <= 0 || list.length < p) return null
  var sum = 0
  for (var i = list.length - p; i < list.length; i++) sum += list[i]
  return sum / p
}

function smaSeries(series, period) {
  var list = series || []
  var p = parseInt(String(period), 10)
  if (isNaN(p) || p <= 0) return []
  var out = []
  var sum = 0
  for (var i = 0; i < list.length; i++) {
    sum += list[i].c
    if (i >= p) sum -= list[i - p].c
    if (i >= p - 1) out.push({ t: list[i].t, c: sum / p })
  }
  return out
}

function rsiValue(values, period) {
  var list = values || []
  var p = parseInt(String(period), 10) || 14
  if (list.length <= p) return null
  var gains = 0
  var losses = 0
  for (var i = list.length - p; i < list.length; i++) {
    var diff = list[i] - list[i - 1]
    if (diff >= 0) gains += diff
    else losses += -diff
  }
  if (losses === 0) return gains === 0 ? 50 : 100
  var rs = gains / losses
  return 100 - (100 / (1 + rs))
}

function averageVolume(candles, period) {
  var list = candles || []
  var p = parseInt(String(period), 10) || 20
  var sum = 0
  var count = 0
  for (var i = Math.max(0, list.length - p); i < list.length; i++) {
    var v = toNumber(list[i].v)
    if (v !== null) { sum += v; count++ }
  }
  return count ? sum / count : null
}

function supportResistance(series, lookback) {
  var list = series || []
  var n = parseInt(String(lookback), 10) || 30
  if (list.length < 3) return { support: null, resistance: null }
  var start = Math.max(0, list.length - n)
  var support = list[start].c
  var resistance = list[start].c
  for (var i = start + 1; i < list.length; i++) {
    if (list[i].c < support) support = list[i].c
    if (list[i].c > resistance) resistance = list[i].c
  }
  return { support: support, resistance: resistance }
}

function technicalSummary(quote, series, candles) {
  var s = series && series.length ? series : (quote && quote.series ? quote.series : [])
  var c = candles && candles.length ? candles : (quote && quote.candles ? quote.candles : [])
  if (!s || s.length < 2) return { available: false, lines: ["Not enough chart data for technical analysis yet."], sma20: null, sma50: null, rsi14: null, support: null, resistance: null }

  var values = closeValues(s)
  var last = values.length ? values[values.length - 1] : null
  var first = values.length ? values[0] : null
  var sma20 = smaValue(values, 20)
  var sma50 = smaValue(values, 50)
  var rsi14 = rsiValue(values, 14)
  var sr = supportResistance(s, 30)
  var avgVol = averageVolume(c, 20)
  var lastVol = c.length ? toNumber(c[c.length - 1].v) : null
  var movePct = first ? ((last - first) / first) * 100 : null

  var lines = []
  var name = quote && quote.symbol ? quote.symbol : "This symbol"
  if (movePct !== null) {
    var direction = movePct > 1 ? "uptrend" : (movePct < -1 ? "downtrend" : "sideways range")
    var article = direction === "uptrend" ? "an" : "a"
    lines.push(name + " is in " + article + " " + direction + " over the selected chart, moving " + (movePct >= 0 ? "+" : "") + movePct.toFixed(2) + "%.")
  }
  if (sma20 !== null) lines.push("Price is " + (last >= sma20 ? "above" : "below") + " SMA20 (" + formatPrice(sma20) + "), suggesting " + (last >= sma20 ? "positive" : "weak") + " short-term momentum.")
  if (sma50 !== null) lines.push("SMA50 is " + formatPrice(sma50) + "; price is " + (last >= sma50 ? "above" : "below") + " it.")
  if (rsi14 !== null) {
    var rsiState = rsi14 >= 70 ? "overbought" : (rsi14 <= 30 ? "oversold" : (rsi14 >= 55 ? "positive" : (rsi14 <= 45 ? "soft" : "neutral")))
    lines.push("RSI14 is " + rsi14.toFixed(0) + " (" + rsiState + ").")
  }
  if (sr.support !== null && sr.resistance !== null) lines.push("Recent support is near " + formatPrice(sr.support) + "; resistance is near " + formatPrice(sr.resistance) + ".")
  if (avgVol !== null && lastVol !== null) {
    var volPct = avgVol ? ((lastVol - avgVol) / avgVol) * 100 : 0
    lines.push("Latest volume is " + Math.abs(volPct).toFixed(0) + "% " + (volPct >= 0 ? "above" : "below") + " its recent average.")
  }

  return { available: true, lines: lines, sma20: sma20, sma50: sma50, rsi14: rsi14, support: sr.support, resistance: sr.resistance }
}

// ---- Ticker tape.

function tapeItems(quotes, compact) {
  var list = quotes || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (!isValid(list[i])) continue
    out.push({
      symbol: String(list[i].symbol || ""),
      text: barLabel(list[i], compact),
      up: isUp(list[i]),
      down: isDown(list[i])
    })
  }
  return out
}

// ---- Colors. Omarchy themes expose their palette in
//      ~/.local/state/omarchy/current/theme/colors.toml (`green = "#a9b665"`);
//      the shell's Color singleton only carries foreground/accent/urgent/muted,
//      so up/down tints are read from that file, with settings overrides.

function normalizeColor(value) {
  var s = trimString(value).toLowerCase()
  return /^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/.test(s) ? s : ""
}

function parseThemeColor(tomlText, key) {
  var lines = String(tomlText || "").split("\n")
  var pattern = new RegExp("^\\s*" + key + "\\s*=\\s*[\"']([^\"']*)[\"']")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(pattern)
    if (m) return normalizeColor(m[1])
  }
  return ""
}

function formatVolume(value) {
  var n = toNumber(value)
  if (n === null) return ""
  var abs = Math.abs(n)
  if (abs >= 1e9) return (n / 1e9).toFixed(2) + "B"
  if (abs >= 1e6) return (n / 1e6).toFixed(1) + "M"
  if (abs >= 1e3) return (n / 1e3).toFixed(1) + "K"
  return String(Math.round(n))
}

// ---- Display currency. Yahoo serves FX pairs through the same chart
//      endpoint ("USDEUR=X" -> 1 USD in EUR), so every quote can be shown in
//      one chosen currency without another data source.

var DEFAULT_CURRENCIES = ["USD", "EUR", "GBP", "JPY", "CHF"]

function normalizeCurrency(value) {
  var s = trimString(value).toUpperCase()
  return /^[A-Z]{3}$/.test(s) ? s : ""
}

function normalizeCurrencies(value, fallback) {
  var defaults = fallback || DEFAULT_CURRENCIES
  var list = []
  if (Array.isArray(value)) list = value
  else if (typeof value === "string") list = value.split(/[\s,;]+/)
  else if (value && typeof value === "object" && typeof value.length === "number") {
    for (var k = 0; k < value.length; k++) list.push(value[k])
  }
  var out = []
  for (var i = 0; i < list.length; i++) {
    var code = normalizeCurrency(list[i])
    if (code === "" || out.indexOf(code) !== -1) continue
    out.push(code)
  }
  return out.length ? out : defaults.slice()
}

// Cycle "" (native, each quote in its own currency) -> list[0] -> ... -> "".
function currencyCycle(current, list, step) {
  var ring = [""].concat(list || [])
  var idx = ring.indexOf(normalizeCurrency(current))
  if (idx === -1) idx = 0
  var dir = step < 0 ? -1 : 1
  return ring[(((idx + dir) % ring.length) + ring.length) % ring.length]
}

// Yahoo reports some markets in minor units: London in pence ("GBp"/"GBX"),
// Johannesburg in cents ("ZAc"), Tel Aviv in agorot ("ILA"). Map those to the
// major code plus a factor.
var MINOR_UNITS = { "GBp": "GBP", "GBX": "GBP", "ZAc": "ZAR", "ILA": "ILS" }

function quoteCurrency(currency) {
  var raw = trimString(currency)
  if (raw === "") return { code: "", factor: 1 }
  if (MINOR_UNITS[raw]) return { code: MINOR_UNITS[raw], factor: 0.01 }
  return { code: raw.toUpperCase(), factor: 1 }
}

function ratePairs(quotes, display) {
  var target = normalizeCurrency(display)
  if (target === "") return []
  var list = quotes || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (!isValid(list[i])) continue
    var from = quoteCurrency(list[i].currency).code
    if (from === "" || from === target) continue
    var pair = from + target + "=X"
    if (out.indexOf(pair) === -1) out.push(pair)
  }
  return out
}

function parseRateLines(text, pairs) {
  var quotes = parseQuoteLines(text, pairs)
  var out = {}
  for (var i = 0; i < quotes.length; i++) {
    if (isValid(quotes[i])) out[quotes[i].symbol] = quotes[i].price
  }
  return out
}

// Multiplier turning a price in `currency` into `display`; 1 when no
// conversion applies, null when the needed rate is not (yet) known.
function rateFor(currency, display, rates) {
  var target = normalizeCurrency(display)
  var from = quoteCurrency(currency)
  if (target === "") return 1
  if (from.code === "") return null
  if (from.code === target) return from.factor
  var rate = rates ? toNumber(rates[from.code + target + "=X"]) : null
  return rate === null ? null : rate * from.factor
}

function convertSeries(series, rate) {
  var list = series || []
  var r = toNumber(rate)
  if (r === null || r === 1) return list
  var out = []
  for (var i = 0; i < list.length; i++) out.push({ t: list[i].t, c: list[i].c * r })
  return out
}

function convertCandles(candles, rate) {
  var list = candles || []
  var r = toNumber(rate)
  if (r === null || r === 1) return list
  var out = []
  for (var i = 0; i < list.length; i++) out.push({
    t: list[i].t,
    o: scaled(list[i].o, r),
    h: scaled(list[i].h, r),
    l: scaled(list[i].l, r),
    c: scaled(list[i].c, r),
    v: list[i].v
  })
  return out
}

function scaled(value, rate) {
  var n = toNumber(value)
  return n === null ? null : n * rate
}

// Copy of `quote` with money fields and series in `display`. Percentages are
// currency-independent. Falls back to the untouched quote (converted: false)
// when the rate is unknown or no conversion applies.
function convertQuote(quote, display, rates) {
  if (!quote) return quote
  var out = {}
  for (var key in quote) out[key] = quote[key]
  out.nativeCurrency = quote.currency
  out.converted = false
  if (!isValid(quote)) return out
  var target = normalizeCurrency(display)
  var from = quoteCurrency(quote.currency)
  if (target === "" || from.code === target || from.code === "") return out
  var rate = rateFor(quote.currency, display, rates)
  if (rate === null) return out
  out.price = scaled(quote.price, rate)
  out.prevClose = scaled(quote.prevClose, rate)
  out.change = out.price !== null && out.prevClose !== null ? out.price - out.prevClose : null
  out.dayLow = scaled(quote.dayLow, rate)
  out.dayHigh = scaled(quote.dayHigh, rate)
  out.week52Low = scaled(quote.week52Low, rate)
  out.week52High = scaled(quote.week52High, rate)
  out.open = scaled(quote.open, rate)
  out.series = convertSeries(quote.series, rate)
  out.candles = convertCandles(quote.candles, rate)
  out.currency = target
  out.converted = true
  return out
}

function convertAll(quotes, display, rates) {
  var list = quotes || []
  var out = []
  for (var i = 0; i < list.length; i++) out.push(convertQuote(list[i], display, rates))
  return out
}

// ---- Level-1 metrics. Everything derives from fields the chart endpoint's
//      meta already carries, so the dense table costs no extra requests.

// 0..1 position of `value` between low and high (clamped); null when unknown.
function rangePosition(value, low, high) {
  var v = toNumber(value)
  var lo = toNumber(low)
  var hi = toNumber(high)
  if (v === null || lo === null || hi === null || hi < lo) return null
  if (hi === lo) return 0.5
  var p = (v - lo) / (hi - lo)
  return p < 0 ? 0 : (p > 1 ? 1 : p)
}

function pctOf(delta, base) {
  var b = toNumber(base)
  if (delta === null || b === null || b === 0) return null
  return (delta / b) * 100
}

// Opening gap versus the previous close, in percent.
function gapPct(quote) {
  if (!quote) return null
  var o = toNumber(quote.open)
  var p = toNumber(quote.prevClose)
  return o === null || p === null ? null : pctOf(o - p, p)
}

// Day's high-low span relative to the previous close, in percent.
function dayRangePct(quote) {
  if (!quote) return null
  var hi = toNumber(quote.dayHigh)
  var lo = toNumber(quote.dayLow)
  return hi === null || lo === null ? null : pctOf(hi - lo, quote.prevClose)
}

// Distance below the 52-week high, in percent (<= 0).
function offHighPct(quote) {
  if (!quote) return null
  var price = toNumber(quote.price)
  var hi = toNumber(quote.week52High)
  return price === null || hi === null ? null : pctOf(price - hi, hi)
}

// "+1.23%" / "-0.40%" for table cells; "" when unknown.
function formatSignedPct(value) {
  var n = toNumber(value)
  if (n === null) return ""
  return (n < 0 ? "-" : "+") + Math.abs(n).toFixed(2) + "%"
}

function formatSignedNumber(value, price) {
  var n = toNumber(value)
  if (n === null) return ""
  var decimals = toNumber(price) !== null ? priceDecimals(toNumber(price)) : 2
  return (n < 0 ? "-" : "+") + Math.abs(n).toFixed(decimals)
}

// Advancers / decliners / average change across the valid quotes.
function marketSummary(quotes) {
  var list = quotes || []
  var up = 0
  var down = 0
  var sum = 0
  var counted = 0
  for (var i = 0; i < list.length; i++) {
    if (!isValid(list[i])) continue
    if (isUp(list[i])) up++
    else if (isDown(list[i])) down++
    var pct = toNumber(list[i].changePct)
    if (pct !== null) {
      sum += pct
      counted++
    }
  }
  return { up: up, down: down, flat: validCount(list) - up - down, avgPct: counted ? sum / counted : null }
}

var SORT_KEYS = ["symbol", "price", "change", "changePct", "dayPos", "gap", "range", "week52Pos", "offHigh", "volume"]

function normalizeSortKey(value) {
  var s = trimString(value)
  return SORT_KEYS.indexOf(s) === -1 ? "" : s
}

function metric(quote, key) {
  if (!quote) return null
  switch (key) {
  case "symbol": return String(quote.symbol || "")
  case "price": return toNumber(quote.price)
  case "change": return toNumber(quote.change)
  case "changePct": return toNumber(quote.changePct)
  case "dayPos": return rangePosition(quote.price, quote.dayLow, quote.dayHigh)
  case "gap": return gapPct(quote)
  case "range": return dayRangePct(quote)
  case "week52Pos": return rangePosition(quote.price, quote.week52Low, quote.week52High)
  case "offHigh": return offHighPct(quote)
  case "volume": return toNumber(quote.volume)
  }
  return null
}

// Stable sort by `key`; invalid quotes and unknown values always go last.
// An empty key keeps the watchlist order.
function sortQuotes(quotes, key, desc) {
  var list = (quotes || []).slice()
  var k = normalizeSortKey(key)
  if (k === "") return list
  var decorated = []
  for (var i = 0; i < list.length; i++) {
    var v = isValid(list[i]) ? metric(list[i], k) : null
    decorated.push({ q: list[i], v: v, i: i })
  }
  decorated.sort(function(a, b) {
    var an = a.v === null || a.v === ""
    var bn = b.v === null || b.v === ""
    if (an !== bn) return an ? 1 : -1
    if (!an && a.v !== b.v) {
      var cmp = typeof a.v === "string" ? (a.v < b.v ? -1 : 1) : a.v - b.v
      return desc ? -cmp : cmp
    }
    return a.i - b.i
  })
  var out = []
  for (var j = 0; j < decorated.length; j++) out.push(decorated[j].q)
  return out
}

// ---- Watchlist sync through a GitHub gist (via the signed-in `gh` CLI).

var DEFAULT_GIST_FILE = "stocks.json"

function normalizeGistId(value) {
  var s = trimString(value)
  // Accept a full gist URL too: https://gist.github.com/<user>/<id>
  var m = s.match(/([0-9a-f]{20,})\/?$/i)
  return m ? m[1] : ""
}

function normalizeGistFile(value) {
  var s = trimString(value)
  return s === "" || /[\/\\]/.test(s) ? DEFAULT_GIST_FILE : s
}

function gistUrl(id) {
  return "https://gist.github.com/" + String(id || "")
}

// Gist content -> symbol list (possibly empty). Accepts a JSON array, a JSON
// object with `symbols`, or plain text (one symbol per line or comma/space
// separated, `#` starts a comment) so editing on the web is forgiving.
function parseWatchlist(text) {
  var raw = trimString(text)
  if (raw === "" || raw === "null") return []
  var list = null
  try {
    var data = JSON.parse(raw)
    if (Array.isArray(data)) list = data
    else if (data && Array.isArray(data.symbols)) list = data.symbols
    else if (data !== null && typeof data === "object") list = []
  } catch (e) {
    list = null
  }
  if (list === null) {
    list = []
    var lines = raw.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].replace(/#.*$/, "")
      var parts = line.split(/[\s,;]+/)
      for (var j = 0; j < parts.length; j++) list.push(parts[j])
    }
  }
  var out = []
  for (var k = 0; k < list.length; k++) {
    if (typeof list[k] !== "string" && typeof list[k] !== "number") continue
    var symbol = normalizeSymbol(list[k])
    if (symbol === "" || out.indexOf(symbol) !== -1) continue
    out.push(symbol)
  }
  return out
}

// A watchlists definition (watchlists.json, an imported file, or the gist)
// -> { watchlists, activeWatchlist }, or null when it holds no symbols.
// Accepts { watchlists: [...] }, { symbols: [...] }, a bare array of lists or
// of symbols, and plain text (one symbol per line, `#` comments), which
// becomes a single "Main" list.
function parseWatchlistsDefinition(text) {
  var parsed = null
  try { parsed = JSON.parse(String(text || "")) } catch (e) { parsed = null }
  var lists = []
  var active = 0
  var arr = arrayLike(parsed)
  if (arr) {
    var named = false
    for (var i = 0; i < arr.length; i++) if (arr[i] && typeof arr[i] === "object") named = true
    lists = named ? normalizeWatchlists(arr, []).filter(function(l) { return l.symbols.length }) : []
    if (!named) {
      var plain = normalizeSymbols(arr, [])
      if (plain.length) lists = [{ name: DEFAULT_WATCHLIST_NAME, symbols: plain }]
    }
  } else if (parsed && typeof parsed === "object") {
    if (parsed.watchlists) {
      var given = listFromValue(parsed.watchlists)
      if (given.length) lists = normalizeWatchlists(given, [])
    } else if (parsed.symbols) {
      var syms = normalizeSymbols(parsed.symbols, [])
      if (syms.length) lists = [{ name: String(parsed.name || DEFAULT_WATCHLIST_NAME), symbols: syms }]
    }
    active = parsed.activeWatchlist
  } else if (parsed === null) {
    var fromText = parseWatchlist(text)
    if (fromText.length) lists = [{ name: DEFAULT_WATCHLIST_NAME, symbols: fromText }]
  }
  lists = lists.filter(function(l) { return l.symbols && l.symbols.length })
  if (!lists.length) return null
  return { watchlists: lists, activeWatchlist: activeWatchlistIndex(active, lists) }
}

// Same shape as watchlists.json; the active list is per-machine UI state and
// stays out of what is synced.
function serializeWatchlists(watchlists) {
  return JSON.stringify({ version: 1, watchlists: cloneWatchlists(watchlists) }, null, 2) + "\n"
}

// Order-sensitive identity of a definition, for change detection.
function watchlistsKey(watchlists) {
  return JSON.stringify(cloneWatchlists(watchlists))
}

function gistBody(file, watchlists) {
  var files = {}
  files[normalizeGistFile(file)] = { content: serializeWatchlists(watchlists) }
  return JSON.stringify({ files: files })
}

// Every gh call runs through one sh wrapper that folds stderr into the output
// and prints the exit code on the first line, so a single stdout collector
// sees both the result and the reason it failed (no stdout/stderr ordering
// races). Values reach the script only as positional args.
function ghCommand(script, args) {
  return ["sh", "-c", "out=$({ " + script + "; } 2>&1); code=$?; printf '%s\\n%s' \"$code\" \"$out\"", "sh"].concat(args || [])
}

// Wrapper stdout -> { code, output }; a missing/garbled status line is code -1.
function parseCommandResult(text) {
  var raw = String(text || "")
  var nl = raw.indexOf("\n")
  var head = nl === -1 ? raw : raw.slice(0, nl)
  var code = /^\d+$/.test(trimString(head)) ? parseInt(head, 10) : -1
  return { code: code, output: nl === -1 ? "" : raw.slice(nl + 1) }
}

// Readable reason for a failed gh call. gh prints the API's JSON error body on
// stdout (no trailing newline) and then "gh: Not Found (HTTP 404)" on stderr,
// so prefer that "gh: " line, then the JSON message, then the first line.
function commandError(result) {
  if (result.code === 127) return "gh CLI not found"
  var output = String(result.output || "")
  var at = output.lastIndexOf("gh: ")
  if (at !== -1) return trimString(output.slice(at + 4).split("\n")[0])
  var m = output.match(/"message"\s*:\s*"([^"]*)"/)
  if (m) return m[1]
  var lines = output.split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (trimString(lines[i]) !== "") return trimString(lines[i])
  }
  return "gh exited with " + result.code
}

function gistPullCommand(id, file) {
  return ghCommand("gh api \"gists/$1\" --jq \"$2\"",
    [normalizeGistId(id), ".files[" + JSON.stringify(normalizeGistFile(file)) + "].content"])
}

// The JSON body (watchlist names and symbols) is written to the Process
// stdin, never argv: the outer sh reads exactly $2 bytes and pipes them to
// `gh api --input -`. argv carries only the gist id and the byte length.
// Returns { command, stdin }.
function gistPushCommand(id, file, watchlists) {
  var body = gistBody(file, watchlists)
  return { command: ghCommand("head -c \"$2\" | gh api -X PATCH \"gists/$1\" --input - --jq .id",
    [normalizeGistId(id), String(utf8Length(body))]), stdin: body }
}

function gistCreateCommand(file, watchlists) {
  var body = JSON.parse(gistBody(file, watchlists))
  body.public = false
  body.description = "omarchy-stocks watchlist"
  var text = JSON.stringify(body)
  return { command: ghCommand("head -c \"$1\" | gh api -X POST gists --input - --jq .id",
    [String(utf8Length(text))]), stdin: text }
}

// ---- Local agent runs.

var DEFAULT_AGENT_COMMAND = ["claude", "-p", "--allowedTools=WebSearch,WebFetch"]

var DEFAULT_AGENT_PROMPTS = [
  { name: "Quick take", prompt: "You are an equity research assistant. Give a concise take on {name} ({symbol}, {exchange}). Latest quote data: {quote}. Cover what moved it recently, key price levels, main risks, and finish with a one-line verdict. Markdown, under 250 words." },
  { name: "Technical", prompt: "Do a technical analysis of {symbol} ({name}). Price {price} {currency}, day range {dayLow}-{dayHigh}, 52-week range {week52Low}-{week52High}, volume {volume}. Look up recent daily price action and discuss trend, support/resistance, momentum and volume. Markdown with short sections." },
  { name: "News & catalysts", prompt: "Search the news from the last two weeks about {name} ({symbol}) and list upcoming catalysts (earnings date, product events, macro). Markdown bullets with dates and sources." }
]

// Settings can reach QML as array-like QVariantLists, not real JS arrays
// (the same reason normalizeSymbols accepts anything with a length).
function arrayLike(value) {
  if (Array.isArray(value)) return value
  var out = []
  if (value && typeof value === "object" && typeof value.length === "number") {
    for (var i = 0; i < value.length; i++) out.push(value[i])
    return out
  }
  return null
}

function normalizeAgentCommand(value) {
  var list = []
  if (arrayLike(value)) list = arrayLike(value)
  else if (typeof value === "string") list = trimString(value).split(/\s+/)
  var out = []
  for (var i = 0; i < list.length; i++) {
    var s = String(list[i] === null || list[i] === undefined ? "" : list[i])
    if (s !== "") out.push(s)
  }
  return out.length ? out : DEFAULT_AGENT_COMMAND.slice()
}

function normalizeAgentPrompts(value) {
  var list = arrayLike(value) || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!p || typeof p !== "object") continue
    var name = trimString(p.name)
    var prompt = trimString(p.prompt)
    if (name === "" || prompt === "") continue
    out.push({ name: name, prompt: prompt })
  }
  return out.length ? out : DEFAULT_AGENT_PROMPTS.slice()
}

function quoteSummary(quote) {
  if (!quote) return {}
  var out = {}
  var keys = ["symbol", "name", "exchange", "currency", "price", "prevClose", "change", "changePct", "open",
    "dayLow", "dayHigh", "week52Low", "week52High", "volume", "marketTime"]
  for (var i = 0; i < keys.length; i++) {
    var v = quote[keys[i]]
    if (v === null || v === undefined || v === "") continue
    out[keys[i]] = typeof v === "number" ? Number(v.toFixed(4)) : v
  }
  var notes = arrayLike(quote.technical)
  if (notes && notes.length) out.technical = notes.slice()
  return out
}

// Replaces {symbol} {name} {price} ... and {quote} (compact JSON of the quote).
// Unknown placeholders are left as typed.
function fillPrompt(template, quote) {
  var q = quote || {}
  return String(template || "").replace(/\{([A-Za-z0-9]+)\}/g, function(match, key) {
    if (key === "quote") return JSON.stringify(quoteSummary(q))
    if (key === "changePct") return formatSignedPct(q.changePct)
    if (key === "change") return formatSignedNumber(q.change, q.price)
    if (key === "volume") return formatVolume(q.volume)
    if (!(key in q)) return match
    var v = q[key]
    if (v === null || v === undefined) return ""
    if (typeof v === "number") return formatPrice(v)
    return String(v)
  })
}

// What the agent actually receives: the filled template, prefixed with the
// symbol on screen and its latest quote so a bare custom prompt ("is this a
// good entry?") still knows what "this" is. Templates that already embed
// {quote} carry the data themselves and are sent as-is.
function agentPrompt(template, quote) {
  var filled = fillPrompt(template, quote)
  if (!quote || String(template || "").indexOf("{quote}") !== -1) return filled
  var label = String(quote.symbol || "") + (quote.name ? " (" + quote.name + (quote.exchange ? ", " + quote.exchange : "") + ")" : "")
  return "Context: the user is looking at " + label + " in their stock watchlist; \"this stock\" refers to it. " +
    "Latest quote: " + JSON.stringify(quoteSummary(quote)) + "\n\n" + filled
}

// Command template -> { argv, stdin }. The prompt carries the symbol and its
// quote, so it goes to the CLI's stdin (`claude -p`, `codex exec` read it from
// there) rather than argv. A standalone `{prompt}` argument is accepted and
// dropped for older settings. Only a `{prompt}` embedded in a larger argument
// (`--q={prompt}`) is still substituted into argv, since that CLI has no
// other way to receive it.
function agentArgv(command, prompt) {
  var base = normalizeAgentCommand(command)
  var out = []
  var embedded = false
  for (var i = 0; i < base.length; i++) {
    if (base[i] === "{prompt}") continue
    if (base[i].indexOf("{prompt}") !== -1) {
      out.push(base[i].split("{prompt}").join(String(prompt)))
      embedded = true
    } else {
      out.push(base[i])
    }
  }
  return { argv: out, stdin: embedded ? "" : String(prompt) }
}

// The agent runs in `dir` (its cache folder) with the prompt on stdin. `exec`
// keeps the CLI as the process Quickshell started, so cancelling stops it.
// Returns { command, stdin }.
function agentCommand(command, prompt, dir) {
  var a = agentArgv(command, prompt)
  return { command: ["sh", "-c", "mkdir -p \"$1\" && cd \"$1\" && shift && exec \"$@\" 2>&1", "sh", String(dir)].concat(a.argv),
    stdin: a.stdin }
}

// File-system safe name for a symbol's cached analysis ("^GSPC" -> "_GSPC").
function agentFileName(symbol) {
  return String(symbol || "").replace(/[^A-Za-z0-9.=-]/g, "_") + ".md"
}

// Cached analysis file: one HTML-comment header line carrying the run's
// metadata, then the agent's raw output.
function agentFileText(meta, output) {
  var m = meta || {}
  return "<!-- omarchy-stocks " + JSON.stringify({ prompt: String(m.prompt || ""), at: toNumber(m.at) }) + " -->\n" + String(output || "")
}

function parseAgentFile(text) {
  var raw = String(text || "")
  var m = raw.match(/^<!-- omarchy-stocks (\{.*\}) -->\n?/)
  if (!m) return { prompt: "", at: null, output: raw }
  var meta = {}
  try { meta = JSON.parse(m[1]) || {} } catch (e) { meta = {} }
  return { prompt: String(meta.prompt || ""), at: toNumber(meta.at), output: raw.slice(m[0].length) }
}

function formatElapsed(seconds) {
  var s = Math.max(0, Math.floor(toNumber(seconds) || 0))
  var m = Math.floor(s / 60)
  var r = s % 60
  return m + ":" + (r < 10 ? "0" : "") + r
}

if (typeof module !== "undefined") {
  module.exports = {
    rangePosition: rangePosition,
    gapPct: gapPct,
    dayRangePct: dayRangePct,
    offHighPct: offHighPct,
    formatSignedPct: formatSignedPct,
    formatSignedNumber: formatSignedNumber,
    marketSummary: marketSummary,
    SORT_KEYS: SORT_KEYS,
    normalizeSortKey: normalizeSortKey,
    metric: metric,
    sortQuotes: sortQuotes,
    DEFAULT_GIST_FILE: DEFAULT_GIST_FILE,
    normalizeGistId: normalizeGistId,
    normalizeGistFile: normalizeGistFile,
    gistUrl: gistUrl,
    parseWatchlist: parseWatchlist,
    parseWatchlistsDefinition: parseWatchlistsDefinition,
    serializeWatchlists: serializeWatchlists,
    watchlistsKey: watchlistsKey,
    gistBody: gistBody,
    ghCommand: ghCommand,
    parseCommandResult: parseCommandResult,
    commandError: commandError,
    gistPullCommand: gistPullCommand,
    gistPushCommand: gistPushCommand,
    gistCreateCommand: gistCreateCommand,
    DEFAULT_AGENT_COMMAND: DEFAULT_AGENT_COMMAND,
    DEFAULT_AGENT_PROMPTS: DEFAULT_AGENT_PROMPTS,
    normalizeAgentCommand: normalizeAgentCommand,
    normalizeAgentPrompts: normalizeAgentPrompts,
    quoteSummary: quoteSummary,
    fillPrompt: fillPrompt,
    agentPrompt: agentPrompt,
    agentArgv: agentArgv,
    agentCommand: agentCommand,
    agentFileName: agentFileName,
    agentFileText: agentFileText,
    parseAgentFile: parseAgentFile,
    formatElapsed: formatElapsed,
    DEFAULT_SYMBOLS: DEFAULT_SYMBOLS,
    ASIA_MARKET_SUFFIXES: ASIA_MARKET_SUFFIXES,
    normalizeSymbol: normalizeSymbol,
    normalizeSymbols: normalizeSymbols,
    normalizeWatchlists: normalizeWatchlists,
    activeWatchlistIndex: activeWatchlistIndex,
    cloneWatchlists: cloneWatchlists,
    refreshMinutes: refreshMinutes,
    cycleSeconds: cycleSeconds,
    chartUrl: chartUrl,
    curlCommand: curlCommand,
    stdinCommand: stdinCommand,
    utf8Length: utf8Length,
    quoteUrl: quoteUrl,
    shellQuote: shellQuote,
    emptyQuote: emptyQuote,
    parseChartResponse: parseChartResponse,
    parseQuoteLines: parseQuoteLines,
    parseCandles: parseCandles,
    isValid: isValid,
    isDown: isDown,
    isUp: isUp,
    validCount: validCount,
    quoteRowsForSymbols: quoteRowsForSymbols,
    firstValidIndex: firstValidIndex,
    nextIndex: nextIndex,
    shouldRetry: shouldRetry,
    formatPrice: formatPrice,
    formatChange: formatChange,
    barLabel: barLabel,
    verticalLabel: verticalLabel,
    loadingLabel: loadingLabel,
    CHART_RANGES: CHART_RANGES,
    chartRange: chartRange,
    chartInterval: chartInterval,
    tickerWidth: tickerWidth,
    scrollSpeed: scrollSpeed,
    parseSeriesLines: parseSeriesLines,
    seriesBounds: seriesBounds,
    seriesDirection: seriesDirection,
    seriesPoints: seriesPoints,
    valueToY: valueToY,
    closeValues: closeValues,
    smaValue: smaValue,
    smaSeries: smaSeries,
    rsiValue: rsiValue,
    averageVolume: averageVolume,
    supportResistance: supportResistance,
    technicalSummary: technicalSummary,
    tapeItems: tapeItems,
    normalizeColor: normalizeColor,
    parseThemeColor: parseThemeColor,
    formatVolume: formatVolume,
    DEFAULT_CURRENCIES: DEFAULT_CURRENCIES,
    normalizeCurrency: normalizeCurrency,
    normalizeCurrencies: normalizeCurrencies,
    currencyCycle: currencyCycle,
    quoteCurrency: quoteCurrency,
    ratePairs: ratePairs,
    parseRateLines: parseRateLines,
    rateFor: rateFor,
    convertSeries: convertSeries,
    convertCandles: convertCandles,
    convertQuote: convertQuote,
    convertAll: convertAll
  }
}
