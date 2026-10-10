import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// State owner for the Stocks widget: fetches quotes and chart series, owns
// the gist sync and agent runner, and hosts the click-to-open panel with its
// two levels (QuoteTable.qml -> DetailView.qml). BarWidget.qml loads this and
// mirrors `tapeItems` / `label` into the bar (same split as omarchy.weather).
Panel {
  id: root
  moduleName: "io.github.siygle.stock-hq"
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
  readonly property bool compact: setting("compact", false) === true || String(setting("compact", false)) === "true"
  readonly property string activeRange: Model.chartRange(setting("chartRange", "1d"))
  readonly property string displayCurrency: Model.normalizeCurrency(setting("currency", ""))
  readonly property var currencies: Model.normalizeCurrencies(setting("currencies", null))
  readonly property string upColorSetting: Model.normalizeColor(setting("upColor", ""))
  readonly property string downColorSetting: Model.normalizeColor(setting("downColor", ""))
  readonly property string sortKey: Model.normalizeSortKey(setting("sortKey", ""))
  readonly property bool sortDesc: setting("sortDesc", true) !== false && String(setting("sortDesc", true)) !== "false"
  readonly property string gistId: Model.normalizeGistId(setting("gistId", ""))
  readonly property string gistFile: Model.normalizeGistFile(setting("gistFile", ""))
  readonly property var agentCommand: Model.normalizeAgentCommand(setting("agentCommand", null))
  readonly property var agentPrompts: Model.normalizeAgentPrompts(setting("agentPrompts", null))

  // ---- Quote state. `quotes` keeps the last good result across failures so
  //      stale-but-useful numbers stay visible; `fetchError` explains why.
  property var quotes: []
  property string fetchError: ""
  property var lastUpdated: null
  property int retries: 0

  // ---- Navigation: "list" (level 1 table) or "detail" (level 2, one symbol).
  property string view: "list"
  property string detailSymbol: ""
  // Keyboard cursor in the table (-1 = none), indexes `tableQuotes`.
  property int cursorIndex: -1
  // A text field owns the keyboard; the key catcher steps aside.
  property bool editing: false

  // ---- Chart-series cache for non-1d ranges, "SYM|range" -> { series, at }
  //      (the 1d series rides along with every quote fetch).
  property var chartCache: ({})
  property string chartRequestedKey: ""
  property bool chartLoading: false

  // ---- FX rates ("USDEUR=X" -> 0.92) for the display currency.
  property var rates: ({})
  property var ratesRequested: []
  property int ratesRetries: 0

  readonly property string userAgent: "Mozilla/5.0 (X11; Linux x86_64) omarchy-stocks/0.2.0"
  readonly property bool loading: quotes.length === 0 && fetchError === ""
  readonly property int validCount: Model.validCount(quotes)
  // Quotes as displayed: converted into the display currency when a rate is known.
  readonly property var shownQuotes: Model.convertAll(quotes, displayCurrency, rates)
  readonly property var tapeItems: Model.tapeItems(shownQuotes, compact)
  readonly property var tableQuotes: Model.sortQuotes(shownQuotes, sortKey, sortDesc)
  readonly property var summary: Model.marketSummary(shownQuotes)
  readonly property var detailQuote: {
    for (var i = 0; i < shownQuotes.length; i++) if (shownQuotes[i].symbol === detailSymbol) return shownQuotes[i]
    return null
  }

  // Fallback pill text while the tape has nothing to show: "AAPL …" while
  // loading, "AAPL !" when every symbol failed.
  readonly property string label: shownQuotes.length > 0
    ? Model.barLabel(shownQuotes[0], compact)
    : Model.loadingLabel(symbols.length ? symbols[0] : "")
  readonly property string verticalText: {
    var first = Model.firstValidIndex(shownQuotes)
    if (first >= 0) return Model.verticalLabel(shownQuotes[first])
    if (shownQuotes.length > 0) return Model.verticalLabel(shownQuotes[0])
    return (symbols.length ? symbols[0] : "") + "\n…"
  }

  // ---- Presentation helpers shared by every row.
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color mutedForeground: Qt.darker(barForeground, 1.5)
  readonly property color urgentForeground: bar ? bar.urgent : Color.urgent

  // Up/down tints: settings override > theme palette (colors.toml) > fallback.
  property string themeGreen: ""
  property string themeRed: ""
  readonly property color upColor: upColorSetting !== "" ? upColorSetting : (themeGreen !== "" ? themeGreen : "#5fbf6f")
  readonly property color downColor: downColorSetting !== "" ? downColorSetting : (themeRed !== "" ? themeRed : urgentForeground)

  function trendColor(quote) {
    if (Model.isDown(quote)) return downColor
    if (Model.isUp(quote)) return upColor
    return barForeground
  }

  function directionColor(series) {
    var d = Model.seriesDirection(series)
    if (d < 0) return downColor
    if (d > 0) return upColor
    return barForeground
  }

  FileView {
    id: themeColors
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.themeGreen = Model.parseThemeColor(text(), "green")
      root.themeRed = Model.parseThemeColor(text(), "red")
    }
    onLoadFailed: {
      root.themeGreen = ""
      root.themeRed = ""
    }
  }

  function open() {
    root.controller.show()
    refresh()
    ensureChartSeries(false)
  }

  function close() {
    root.controller.hide()
  }

  onOpenedChanged: if (!root.opened) {
    view = "list"
    cursorIndex = -1
    editing = false
  }

  // ---- Level navigation.
  function showDetail(symbol) {
    var quote = null
    for (var i = 0; i < quotes.length; i++) if (quotes[i].symbol === symbol) quote = quotes[i]
    if (!Model.isValid(quote)) return
    detailSymbol = symbol
    view = "detail"
    agent.loadCached(symbol)
    ensureChartSeries(false)
  }

  function showList() {
    view = "list"
    releaseInput()
  }

  function moveCursor(dy) {
    if (view !== "list" || !tableQuotes.length) return
    var next = cursorIndex < 0 ? (dy > 0 ? 0 : tableQuotes.length - 1) : cursorIndex + dy
    cursorIndex = Math.max(0, Math.min(tableQuotes.length - 1, next))
  }

  function activateCursor() {
    if (view === "list" && cursorIndex >= 0 && cursorIndex < tableQuotes.length)
      showDetail(tableQuotes[cursorIndex].symbol)
    else
      refresh()
  }

  function releaseInput() {
    editing = false
    keyCatcher.forceActiveFocus()
  }

  // ---- Settings writes go into this widget's shell.json entry, the way
  //      omarchy.clock persists a right-click format change.
  function updateSettings(patch) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    for (var p in patch) entry[p] = patch[p]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Header click: descending -> ascending -> watchlist order.
  function cycleSort(key) {
    if (sortKey !== key) updateSettings({ sortKey: key, sortDesc: key !== "symbol" })
    else if (sortDesc === (key !== "symbol")) updateSettings({ sortDesc: !sortDesc })
    else updateSettings({ sortKey: "", sortDesc: true })
    cursorIndex = -1
  }

  // ---- Watchlist edits from the panel; pushed to the gist when syncing.
  function setSymbols(list) {
    if (!list.length || list.join(",") === symbolsKey) return
    updateSettings({ symbols: list })
    gist.push(list)
  }

  function addSymbols(text) {
    var next = symbols.slice()
    var added = Model.parseWatchlist(text)
    for (var i = 0; i < added.length; i++) if (next.indexOf(added[i]) === -1) next.push(added[i])
    setSymbols(next)
  }

  function removeSymbol(symbol) {
    setSymbols(symbols.filter(function(s) { return s !== symbol }))
  }

  function syncNow() {
    if (gist.configured) gist.pull()
  }

  function openGist() {
    if (gistId !== "" && root.bar && typeof root.bar.run === "function")
      root.bar.run("xdg-open " + Model.shellQuote(Model.gistUrl(gistId)))
  }

  // ---- Agent runs on the detail symbol.
  function runAgent(name, template) {
    if (detailQuote) agent.run(detailQuote, name, template)
  }

  function openAgentFile(symbol) {
    if (root.bar && typeof root.bar.run === "function")
      root.bar.run("xdg-open " + Model.shellQuote(agent.cacheDir + "/" + Model.agentFileName(symbol)))
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
    syncNow()
  }

  function startFetch() {
    if (fetchProc.running) return
    fetchProc.command = Model.curlCommand(symbols, userAgent, "1d")
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
    ensureRates()
    // Fresh quotes deserve fresh charts, unless the cache is under a minute old.
    if (root.opened) ensureChartSeries(true)
  }

  // ---- FX rates for the display currency: one pair per distinct quote
  //      currency, refreshed with every quote refresh (a couple of URLs).
  function ensureRates() {
    var pairs = Model.ratePairs(quotes, displayCurrency)
    if (!pairs.length || ratesProc.running) return
    ratesRequested = pairs
    ratesProc.command = Model.curlCommand(pairs, userAgent, "1d")
    ratesProc.running = true
  }

  function handleRatesOutput(text) {
    var raw = String(text || "")
    var fresh = raw.replace(/\s+/g, "") === "" ? {} : Model.parseRateLines(raw, ratesRequested)
    var missing = false
    for (var i = 0; i < ratesRequested.length; i++) if (fresh[ratesRequested[i]] === undefined) missing = true
    if (missing && ratesRetries < 3) {
      ratesRetries++
      ratesRetryTimer.restart()
    } else {
      ratesRetries = 0
    }
    var merged = {}
    for (var k in rates) merged[k] = rates[k]
    for (var f in fresh) merged[f] = fresh[f]
    rates = merged
  }

  function selectCurrency(step) {
    var next = Model.currencyCycle(displayCurrency, currencies, step)
    if (next !== displayCurrency) updateSettings({ currency: next })
  }

  function currencyLabel(quote) {
    if (!quote) return ""
    if (quote.converted) return quote.nativeCurrency + " → " + quote.currency
    return quote.currency
  }

  function scheduleRetry() {
    if (retries >= 3) return
    retries++
    retryTimer.restart()
  }

  // ---- Chart series for the non-1d ranges, fetched for the detail symbol
  //      only. `force` (a quote refresh) refetches unless under a minute old.
  function chartKey(symbol, range) {
    return symbol + "|" + range
  }

  function ensureChartSeries(force) {
    if (view !== "detail" || detailSymbol === "" || activeRange === "1d") return
    var cached = chartCache[chartKey(detailSymbol, activeRange)]
    if (cached && (!force || Date.now() - cached.at < 60000)) return
    startChartFetch()
  }

  function startChartFetch() {
    if (chartProc.running) return
    chartRequestedKey = chartKey(detailSymbol, activeRange)
    chartLoading = true
    chartProc.command = Model.curlCommand([detailSymbol], userAgent, activeRange)
    chartProc.running = true
  }

  function handleChartOutput(text) {
    chartLoading = false
    var raw = String(text || "")
    var parts = chartRequestedKey.split("|")
    if (raw.replace(/\s+/g, "") !== "") {
      var parsed = Model.parseSeriesLines(raw, [parts[0]])
      var next = {}
      for (var k in chartCache) next[k] = chartCache[k]
      next[chartRequestedKey] = { series: parsed[parts[0]] || [], at: Date.now() }
      chartCache = next
    }
    // Symbol or range moved on while we were fetching: go again.
    if (chartRequestedKey !== chartKey(detailSymbol, activeRange)) Qt.callLater(function() { root.ensureChartSeries(false) })
  }

  // 1d series ride along with the (already converted) quote; other ranges
  // come from the raw chart cache and are converted here.
  function seriesFor(quote) {
    if (!quote) return []
    if (activeRange === "1d") return quote.series || []
    var cached = chartCache[chartKey(quote.symbol, activeRange)]
    return Model.convertSeries(cached ? cached.series : [], Model.rateFor(quote.nativeCurrency || quote.currency, displayCurrency, rates))
  }

  function selectRange(range) {
    var next = Model.chartRange(range)
    if (next !== activeRange) updateSettings({ chartRange: next })
  }

  function openQuotePage(symbol) {
    if (root.bar && typeof root.bar.run === "function")
      root.bar.run("xdg-open " + Model.shellQuote(Model.quoteUrl(symbol)))
  }

  function rangeLabel(range) {
    return { "1d": "1D", "5d": "5D", "1mo": "1M", "6mo": "6M", "1y": "1Y" }[range] || range
  }

  function formatStamp(ts, range) {
    if (ts === null || ts === undefined) return ""
    var d = new Date(ts * 1000)
    return Qt.formatDateTime(d, range === "1d" ? "HH:mm" : (range === "5d" ? "ddd HH:mm" : "d MMM"))
  }

  // Settings edits that change the symbol list invalidate everything shown.
  // Keyed on the joined string so re-injected-but-identical settings (any
  // shell.json save) do not trigger a refetch.
  onSymbolsKeyChanged: {
    quotes = []
    chartCache = {}
    fetchError = ""
    lastUpdated = null
    retries = 0
    cursorIndex = -1
    fetchProc.running = false
    chartProc.running = false
    if (view === "detail" && symbols.indexOf(detailSymbol) === -1) view = "list"
    Qt.callLater(root.startFetch)
    if (root.opened) Qt.callLater(function() { root.ensureChartSeries(true) })
  }

  onActiveRangeChanged: if (root.opened) ensureChartSeries(false)
  onDisplayCurrencyChanged: ensureRates()
  onTableQuotesChanged: if (cursorIndex >= tableQuotes.length) cursorIndex = tableQuotes.length - 1

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

  Process {
    id: chartProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleChartOutput(text)
    }
  }

  Process {
    id: ratesProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleRatesOutput(text)
    }
  }

  Timer {
    id: retryTimer
    interval: 2500
    onTriggered: root.startFetch()
  }

  Timer {
    id: ratesRetryTimer
    interval: 2500
    onTriggered: root.ensureRates()
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }


  GistSync {
    id: gist
    gistId: root.gistId
    gistFile: root.gistFile
    symbols: root.symbols
    onRemoteChanged: function(list) { root.updateSettings({ symbols: list }) }
    onCreated: function(id) { root.updateSettings({ gistId: id }) }
  }

  AgentRunner {
    id: agent
    command: root.agentCommand
  }

  readonly property alias gistSync: gist
  readonly property alias agentRunner: agent

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(950))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editing
      // Esc steps back from a symbol to the table before it closes the panel.
      onCloseRequested: root.view === "detail" ? root.showList() : root.close()
      onActivateRequested: root.activateCursor()
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else if (dx < 0 && root.view === "detail") root.showList()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: 0

        QuoteTable {
          width: parent.width
          visible: root.view === "list"
          stocks: root
        }

        DetailView {
          width: parent.width
          visible: root.view === "detail"
          stocks: root
        }
      }
    }
  }
}
