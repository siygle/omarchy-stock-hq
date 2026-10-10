import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// State owner for the Stocks widget: fetches quotes and chart series, and
// renders the click-to-open panel. BarWidget.qml loads this and mirrors
// `tapeItems` / `label` into the bar (same split as omarchy.weather).
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

  // ---- Settings. UI preferences stay inline on this widget's shell.json entry;
  //      watchlists live in a JSON definition file so symbols are not stored in
  //      shell.json text fields.
  property var watchlists: Model.normalizeWatchlists(null, null)
  property int activeWatchlist: 0
  property var activeList: ({ name: "Main", symbols: Model.DEFAULT_SYMBOLS })
  property var symbols: Model.DEFAULT_SYMBOLS
  property string symbolsKey: "0:" + Model.DEFAULT_SYMBOLS.join(",")
  property int refreshMinutes: 5
  property bool compact: false
  property string activeRange: "1d"
  property string displayCurrency: ""
  property var currencies: Model.normalizeCurrencies(null)
  property string upColorSetting: ""
  property string downColorSetting: ""
  property bool watchlistsFileLoaded: false
  property var watchlistsFileLists: []
  property int watchlistsFileActive: 0

  // ---- Persistent quote cache. Settings stay in shell.json; fetched market
  //      data lives in XDG state so it survives shell restarts without making
  //      user config noisy.
  readonly property string homeDir: Quickshell.env("HOME")
  property string watchlistsDir: homeDir + "/.local/share/omarchy-stock-hq"
  property string watchlistsPath: watchlistsDir + "/watchlists.json"
  readonly property string cacheDir: homeDir + "/.local/state/omarchy-stock-hq"
  readonly property string cachePath: cacheDir + "/cache.json"
  property bool cacheLoaded: false

  // ---- Quote state. `quotes` keeps the last good result across failures so
  //      stale-but-useful numbers stay visible; `fetchError` explains why.
  property var quotes: []
  property string fetchError: ""
  property var lastUpdated: null
  property int retries: 0
  property int selectedIndex: 0

  // ---- Inline watchlist/symbol editor state.
  property bool editorOpen: false
  property int editingIndex: -1
  property string symbolDraft: ""

  // ---- Settings panel state.
  property bool settingsOpen: false
  property string refreshMinutesDraft: "5"
  property string selectedImportPath: ""
  property string selectedExportPath: ""
  property string fileDialogMessage: ""

  // ---- Chart-series cache for the active range when it is not 1d (the 1d
  //      series rides along with every quote fetch).
  property var chartSeries: ({})
  property string chartSeriesRange: ""
  property string chartRequestedRange: ""
  property bool chartLoading: false
  property double chartFetchedAt: 0

  // ---- FX rates ("USDEUR=X" -> 0.92) for the display currency.
  property var rates: ({})
  property var ratesRequested: []
  property int ratesRetries: 0

  readonly property string userAgent: "Mozilla/5.0 (X11; Linux x86_64) omarchy-stock-hq/0.1.0"
  readonly property bool loading: quotes.length === 0 && fetchError === ""
  readonly property var quoteRows: Model.quoteRowsForSymbols(quotes, symbols, "No cached data")
  readonly property int validCount: Model.validCount(quoteRows)
  // Quotes as displayed: converted into the display currency when a rate is known.
  readonly property var shownQuotes: Model.convertAll(quoteRows, displayCurrency, rates)
  readonly property var tapeItems: Model.tapeItems(shownQuotes, compact)
  readonly property var selectedQuote: selectedIndex >= 0 && selectedIndex < shownQuotes.length ? shownQuotes[selectedIndex] : null
  readonly property bool hasSelection: Model.isValid(selectedQuote)

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
    scheduleCacheSave()
    ensureRates()
    // Fresh quotes deserve fresh charts, unless the cache is under a minute old.
    if (root.opened && Date.now() - chartFetchedAt > 60000) ensureChartSeries(true)
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
    scheduleCacheSave()
  }

  function updateSettings(patch) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    for (var p in patch) entry[p] = patch[p]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function selectCurrency(step) {
    var next = Model.currencyCycle(displayCurrency, currencies, step)
    if (next === displayCurrency) return
    updateSettings({ currency: next })
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

  // ---- Chart series for the non-1d ranges.
  function ensureChartSeries(force) {
    if (activeRange === "1d") return
    if (!force && chartSeriesRange === activeRange) return
    startChartFetch()
  }

  function startChartFetch() {
    if (chartProc.running) return
    chartRequestedRange = activeRange
    chartLoading = true
    chartProc.command = Model.curlCommand(symbols, userAgent, activeRange)
    chartProc.running = true
  }

  function handleChartOutput(text) {
    chartLoading = false
    var raw = String(text || "")
    if (raw.replace(/\s+/g, "") === "") return
    chartSeries = Model.parseSeriesLines(raw, symbols)
    chartSeriesRange = chartRequestedRange
    chartFetchedAt = Date.now()
    scheduleCacheSave()
    // The range moved on while we were fetching: go again for the new one.
    if (chartRequestedRange !== activeRange) Qt.callLater(root.startChartFetch)
  }

  // 1d series ride along with the (already converted) quote; other ranges
  // come from the raw chart cache and are converted here.
  function seriesFor(quote) {
    if (!quote) return []
    if (activeRange === "1d") return quote.series || []
    var raw = chartSeries[quote.symbol] || []
    return Model.convertSeries(raw, Model.rateFor(quote.nativeCurrency || quote.currency, displayCurrency, rates))
  }

  function candlesFor(quote) {
    if (!quote || activeRange !== "1d") return []
    return quote.candles || []
  }

  function analysisFor(quote, series) {
    return Model.technicalSummary(quote, series, candlesFor(quote))
  }

  // Range chips persist their choice into this widget's shell.json entry, the
  // way omarchy.clock persists a right-click format change.
  function selectRange(range) {
    var next = Model.chartRange(range)
    if (next === activeRange) return
    updateSettings({ chartRange: next })
  }

  function selectWatchlist(index) {
    if (index === activeWatchlist || index < 0 || index >= watchlists.length) return
    persistWatchlists(watchlists, index)
  }

  function watchlistsPayload(nextLists, nextActive) {
    return {
      version: 1,
      activeWatchlist: Model.activeWatchlistIndex(nextActive, nextLists),
      watchlists: Model.cloneWatchlists(nextLists)
    }
  }

  function parseWatchlistsJson(raw, allowFallback) {
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = null }
    var lists = []
    var active = 0

    if (parsed instanceof Array) {
      // Bare array: either [{ name, symbols }, ...] or ["AAPL", "NVDA"].
      lists = Model.normalizeWatchlists(parsed, null)
      if (!lists.length) lists = [{ name: "Main", symbols: Model.normalizeSymbols(parsed, []) }]
    } else if (parsed && typeof parsed === "object") {
      if (parsed.watchlists) lists = Model.normalizeWatchlists(parsed.watchlists, null)
      else if (parsed.symbols) lists = [{ name: String(parsed.name || "Main"), symbols: Model.normalizeSymbols(parsed.symbols, []) }]
      active = Model.activeWatchlistIndex(parsed.activeWatchlist, lists)
    }

    if (!lists.length) {
      if (!allowFallback) return null
      lists = Model.normalizeWatchlists(null, null)
      active = 0
    }
    return { watchlists: lists, activeWatchlist: Model.activeWatchlistIndex(active, lists) }
  }

  function applyWatchlistsDefinition(definition) {
    watchlistsFileLists = definition.watchlists
    watchlistsFileActive = definition.activeWatchlist
    watchlistsFileLoaded = true
    applySettings()
  }

  function loadWatchlists(raw) {
    applyWatchlistsDefinition(parseWatchlistsJson(raw, true))
  }

  function persistWatchlists(nextLists, nextActive) {
    var payload = watchlistsPayload(nextLists, nextActive)
    watchlistsFileLists = payload.watchlists
    watchlistsFileActive = payload.activeWatchlist
    watchlistsFileLoaded = true
    watchlistsFile.setText(JSON.stringify(payload, null, 2) + "\n")
    applySettings()
  }

  function beginAddSymbol() {
    editorOpen = true
    editingIndex = -1
    symbolDraft = ""
    Qt.callLater(function() { if (symbolField) symbolField.forceActiveFocus() })
  }

  function beginEditSymbol(index) {
    if (index < 0 || index >= symbols.length) return
    editorOpen = true
    editingIndex = index
    symbolDraft = symbols[index]
    Qt.callLater(function() { if (symbolField) { symbolField.forceActiveFocus(); symbolField.selectAll() } })
  }

  function saveSymbolDraft() {
    var symbol = Model.normalizeSymbol(symbolDraft)
    if (symbol === "") return
    var lists = Model.cloneWatchlists(watchlists)
    var list = lists[activeWatchlist]
    if (!list) return
    var existing = list.symbols.indexOf(symbol)
    if (editingIndex >= 0) {
      if (existing >= 0 && existing !== editingIndex) list.symbols.splice(editingIndex, 1)
      else list.symbols[editingIndex] = symbol
    } else if (existing < 0) {
      list.symbols.push(symbol)
    }
    editorOpen = false
    persistWatchlists(lists, activeWatchlist)
  }

  function deleteSymbol(index) {
    var lists = Model.cloneWatchlists(watchlists)
    var list = lists[activeWatchlist]
    if (!list || index < 0 || index >= list.symbols.length) return
    list.symbols.splice(index, 1)
    if (!list.symbols.length) list.symbols.push(Model.DEFAULT_SYMBOLS[0])
    persistWatchlists(lists, activeWatchlist)
  }

  function beginAddWatchlist() {
    var lists = Model.cloneWatchlists(watchlists)
    lists.push({ name: "List " + (lists.length + 1), symbols: ["2330.TW", "0050.TW", "0700.HK", "7203.T"] })
    persistWatchlists(lists, lists.length - 1)
  }

  function renameActiveWatchlist(name) {
    var clean = String(name || "").trim()
    if (clean === "") return
    var lists = Model.cloneWatchlists(watchlists)
    if (!lists[activeWatchlist]) return
    lists[activeWatchlist].name = clean
    persistWatchlists(lists, activeWatchlist)
  }

  function deleteActiveWatchlist() {
    if (watchlists.length <= 1) return
    var lists = Model.cloneWatchlists(watchlists)
    lists.splice(activeWatchlist, 1)
    persistWatchlists(lists, Math.max(0, activeWatchlist - 1))
  }

  function selectQuote(index) {
    if (index >= 0 && index < quotes.length && Model.isValid(quotes[index])) selectedIndex = index
  }

  function openQuotePage(symbol) {
    if (root.bar && typeof root.bar.run === "function")
      root.bar.run("xdg-open " + Model.shellQuote(Model.quoteUrl(symbol)))
  }

  function toggleSettings() {
    settingsOpen = !settingsOpen
    refreshMinutesDraft = String(refreshMinutes)
  }

  function saveRefreshMinutesDraft() {
    var minutes = Model.refreshMinutes(refreshMinutesDraft, refreshMinutes)
    updateSettings({ refreshMinutes: minutes })
    refreshMinutesDraft = String(minutes)
  }

  function filePathFromUrl(value) {
    var raw = String(value || "").trim()
    if (raw.indexOf("file://") === 0) return decodeURIComponent(raw.substring(7))
    return raw
  }

  function openWatchlistsFile() {
    if (root.bar && typeof root.bar.run === "function")
      root.bar.run("xdg-open " + Model.shellQuote(watchlistsPath))
  }

  function defaultExportFilename() {
    var now = new Date()
    var y = now.getFullYear()
    var m = now.getMonth() + 1
    var d = now.getDate()
    return "omarchy-stock-hq-" + y + "-" + (m < 10 ? "0" + m : m) + "-" + (d < 10 ? "0" + d : d) + ".json"
  }

  function requestExportWatchlists() {
    if (exportSelectProc.running) return
    fileDialogMessage = "Choose an export folder…"
    selectedExportPath = ""
    exportSelectProc.running = true
  }

  function handleSelectedExportPath(path) {
    var target = filePathFromUrl(path)
    if (target === "") return
    if (!/\.json$/i.test(target)) {
      if (target.charAt(target.length - 1) !== "/") target += "/"
      target += defaultExportFilename()
    }
    selectedExportPath = target
    exportFile.path = target
    exportFile.setText(JSON.stringify(watchlistsPayload(watchlists, activeWatchlist), null, 2) + "\n")
    fileDialogMessage = "Exported " + target
  }

  function requestImportWatchlists() {
    if (importReadProc.running) return
    fileDialogMessage = "Choose a stock-list JSON file…"
    selectedImportPath = ""
    importSelectProc.running = true
  }

  function handleSelectedImportPath(path) {
    var source = filePathFromUrl(path)
    if (source === "") return
    selectedImportPath = source
    importReadProc.command = ["cat", source]
    importReadProc.running = true
  }

  function importWatchlistsText(text) {
    var definition = parseWatchlistsJson(text, false)
    if (!definition) {
      fileDialogMessage = "Import failed: JSON must contain watchlists or symbols"
      return
    }
    var beforeKey = symbolsKey
    applyWatchlistsDefinition(definition)
    watchlistsFile.setText(JSON.stringify(watchlistsPayload(definition.watchlists, definition.activeWatchlist), null, 2) + "\n")
    fileDialogMessage = "Imported " + selectedImportPath
    if (symbolsKey === beforeKey) root.refresh()
  }

  function rangeLabel(range) {
    return { "1d": "1D", "5d": "5D", "1mo": "1M", "6mo": "6M", "1y": "1Y" }[range] || range
  }

  function formatStamp(ts, range) {
    if (ts === null || ts === undefined) return ""
    var d = new Date(ts * 1000)
    return Qt.formatDateTime(d, range === "1d" ? "HH:mm" : (range === "5d" ? "ddd HH:mm" : "d MMM"))
  }

  // ---- Cache persistence.
  function loadCache(raw) {
    if (cacheLoaded) return
    cacheLoaded = true
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = null }
    if (!parsed || parsed.version !== 1) return

    // Hydrate by symbol, not by exact watchlist key. This keeps existing cached
    // rows useful after the user adds/removes/reorders symbols, and it also
    // shows newly added symbols immediately as uncached rows if Yahoo is slow
    // or rate-limited during startup.
    if (quotes.length === 0 && parsed.quotes instanceof Array) {
      var bySymbol = {}
      for (var i = 0; i < parsed.quotes.length; i++) {
        var cached = parsed.quotes[i]
        if (cached && cached.symbol) bySymbol[String(cached.symbol).toUpperCase()] = cached
      }
      var restored = []
      for (var j = 0; j < symbols.length; j++) {
        var symbol = String(symbols[j]).toUpperCase()
        restored.push(bySymbol[symbol] || Model.emptyQuote(symbol, "No cached data"))
      }
      if (restored.length) quotes = restored
    }

    if (parsed.rates && typeof parsed.rates === "object") rates = parsed.rates
    if (parsed.chartSeries && typeof parsed.chartSeries === "object") chartSeries = parsed.chartSeries
    if (typeof parsed.chartSeriesRange === "string") chartSeriesRange = parsed.chartSeriesRange
    if (typeof parsed.chartFetchedAt === "number") chartFetchedAt = parsed.chartFetchedAt
    if (typeof parsed.lastUpdated === "number") lastUpdated = new Date(parsed.lastUpdated)
  }

  function cachePayload() {
    return {
      version: 1,
      symbolsKey: symbolsKey,
      activeWatchlist: activeWatchlist,
      displayCurrency: displayCurrency,
      savedAt: Date.now(),
      lastUpdated: lastUpdated ? lastUpdated.getTime() : null,
      quotes: quotes,
      rates: rates,
      chartSeries: chartSeries,
      chartSeriesRange: chartSeriesRange,
      chartFetchedAt: chartFetchedAt
    }
  }

  function scheduleCacheSave() {
    // If a network response beats the async cache read, mark loaded so the
    // older disk payload cannot overwrite fresher quotes when it arrives.
    cacheLoaded = true
    cacheSaveTimer.restart()
  }

  function flushCache() {
    cacheFile.setText(JSON.stringify(cachePayload(), null, 2) + "\n")
  }

  function applySettings() {
    var s = settings || {}
    watchlistsPath = String(s.watchlistsPath || (watchlistsDir + "/watchlists.json"))
    watchlists = watchlistsFileLoaded && watchlistsFileLists.length
      ? Model.cloneWatchlists(watchlistsFileLists)
      : Model.normalizeWatchlists(s.watchlists, s.symbols)
    activeWatchlist = watchlistsFileLoaded
      ? Model.activeWatchlistIndex(watchlistsFileActive, watchlists)
      : Model.activeWatchlistIndex(s.activeWatchlist, watchlists)
    activeList = watchlists[activeWatchlist] || { name: "Main", symbols: Model.DEFAULT_SYMBOLS }
    symbols = activeList.symbols
    symbolsKey = activeWatchlist + ":" + symbols.join(",")
    refreshMinutes = Model.refreshMinutes(s.refreshMinutes, 5)
    if (!settingsOpen) refreshMinutesDraft = String(refreshMinutes)
    compact = s.compact === true || String(s.compact) === "true"
    activeRange = Model.chartRange(s.chartRange || "1d")
    displayCurrency = Model.normalizeCurrency(s.currency || "")
    currencies = Model.normalizeCurrencies(s.currencies || null)
    upColorSetting = Model.normalizeColor(s.upColor || "")
    downColorSetting = Model.normalizeColor(s.downColor || "")
  }

  onSettingsChanged: applySettings()
  onWatchlistsPathChanged: if (watchlistsFile) watchlistsFile.reload()

  // Settings edits that change the symbol list invalidate everything shown.
  // Keyed on the joined string so re-injected-but-identical settings (any
  // shell.json save) do not trigger a refetch.
  onSymbolsKeyChanged: {
    selectedIndex = 0
    quotes = []
    chartSeries = {}
    chartSeriesRange = ""
    fetchError = ""
    lastUpdated = null
    retries = 0
    cacheLoaded = false
    fetchProc.running = false
    chartProc.running = false
    Qt.callLater(function() { cacheFile.reload(); root.startFetch() })
    if (root.opened) Qt.callLater(function() { root.ensureChartSeries(true) })
  }

  onActiveRangeChanged: if (root.opened) ensureChartSeries(false)
  onDisplayCurrencyChanged: ensureRates()

  // Keep the detail block on a valid symbol when the list shrinks or a symbol fails.
  onQuotesChanged: {
    if (!Model.isValid(selectedQuote)) {
      var first = Model.firstValidIndex(quotes)
      selectedIndex = first >= 0 ? first : 0
    }
  }

  // Deferred so the first fetch sees the settings BarWidget injects right
  // after this component loads (Loader.onLoaded runs before callLater fires).
  Component.onCompleted: {
    applySettings()
    cacheDirProc.running = true
    Qt.callLater(function() { watchlistsFile.reload(); cacheFile.reload(); root.startFetch() })
  }

  FileView {
    id: watchlistsFile
    path: root.watchlistsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadWatchlists(text())
    onLoadFailed: root.loadWatchlists("")
  }

  FileView {
    id: exportFile
    path: root.watchlistsPath
    atomicWrites: true
    printErrors: false
  }

  Process {
    id: exportSelectProc
    command: ["omarchy-file-select", "--title", "Choose Stock HQ export folder", "--directory"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.selectedExportPath = String(text || "").trim()
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.fileDialogMessage = String(text).trim()
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && root.selectedExportPath !== "") root.handleSelectedExportPath(root.selectedExportPath)
      else if (root.fileDialogMessage === "Choose an export folder…") root.fileDialogMessage = "Export cancelled"
    }
  }

  Process {
    id: importSelectProc
    command: ["omarchy-file-select", "--title", "Import Stock HQ JSON", "--extensions", "json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.selectedImportPath = String(text || "").trim()
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.fileDialogMessage = String(text).trim()
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && root.selectedImportPath !== "") root.handleSelectedImportPath(root.selectedImportPath)
      else if (root.fileDialogMessage === "Choose a stock-list JSON file…") root.fileDialogMessage = "Import cancelled"
    }
  }

  Process {
    id: importReadProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.importWatchlistsText(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.fileDialogMessage = String(text).trim()
    }
  }

  FileView {
    id: cacheFile
    path: root.cachePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadCache(text())
    onLoadFailed: root.loadCache("")
  }

  Timer {
    id: cacheSaveTimer
    interval: 300
    repeat: false
    onTriggered: root.flushCache()
  }

  Process {
    id: cacheDirProc
    command: ["mkdir", "-p", root.cacheDir, root.watchlistsDir]
  }

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

  // Sparkline / chart line. Pure geometry comes from Model so the paint
  // handler only strokes the path.
  component SeriesCanvas: Canvas {
    id: canvas
    property var series: []
    property color lineColor: "white"
    property real lineWidth: 1.5
    property real pad: 2
    property bool fill: false
    property var referenceValue: null
    property var overlaySeries: []
    property color overlayColor: root.mutedForeground
    property var supportValue: null
    property var resistanceValue: null

    onSeriesChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onReferenceValueChanged: requestPaint()
    onOverlaySeriesChanged: requestPaint()
    onSupportValueChanged: requestPaint()
    onResistanceValueChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var pts = Model.seriesPoints(canvas.series, canvas.width, canvas.height, canvas.pad)
      if (pts.length < 2) return

      if (canvas.fill) {
        var gradient = ctx.createLinearGradient(0, 0, 0, canvas.height)
        gradient.addColorStop(0, Qt.rgba(canvas.lineColor.r, canvas.lineColor.g, canvas.lineColor.b, 0.28))
        gradient.addColorStop(1, Qt.rgba(canvas.lineColor.r, canvas.lineColor.g, canvas.lineColor.b, 0.0))
        ctx.fillStyle = gradient
        ctx.beginPath()
        ctx.moveTo(pts[0].x, canvas.height)
        for (var f = 0; f < pts.length; f++) ctx.lineTo(pts[f].x, pts[f].y)
        ctx.lineTo(pts[pts.length - 1].x, canvas.height)
        ctx.closePath()
        ctx.fill()
      }

      var refY = Model.valueToY(canvas.referenceValue, Model.seriesBounds(canvas.series), canvas.height, canvas.pad)
      if (refY !== null) {
        ctx.strokeStyle = Qt.rgba(canvas.lineColor.r, canvas.lineColor.g, canvas.lineColor.b, 0.35)
        ctx.lineWidth = 1
        ctx.setLineDash([3, 3])
        ctx.beginPath()
        ctx.moveTo(pts[0].x, refY)
        ctx.lineTo(pts[pts.length - 1].x, refY)
        ctx.stroke()
        ctx.setLineDash([])
      }

      function drawHorizontal(value, color) {
        var y = Model.valueToY(value, Model.seriesBounds(canvas.series), canvas.height, canvas.pad)
        if (y === null) return
        ctx.strokeStyle = color
        ctx.lineWidth = 1
        ctx.setLineDash([4, 4])
        ctx.beginPath()
        ctx.moveTo(pts[0].x, y)
        ctx.lineTo(pts[pts.length - 1].x, y)
        ctx.stroke()
        ctx.setLineDash([])
      }

      drawHorizontal(canvas.supportValue, Qt.rgba(root.upColor.r, root.upColor.g, root.upColor.b, 0.45))
      drawHorizontal(canvas.resistanceValue, Qt.rgba(root.downColor.r, root.downColor.g, root.downColor.b, 0.45))

      ctx.strokeStyle = canvas.lineColor
      ctx.lineWidth = canvas.lineWidth
      ctx.lineJoin = "round"
      ctx.lineCap = "round"
      ctx.beginPath()
      ctx.moveTo(pts[0].x, pts[0].y)
      for (var i = 1; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y)
      ctx.stroke()

      var overlay = canvas.overlaySeries || []
      if (overlay.length >= 2) {
        var bounds = Model.seriesBounds(canvas.series)
        var t0 = canvas.series[0].t
        var t1 = canvas.series[canvas.series.length - 1].t
        var span = t1 - t0
        var innerW = canvas.width - canvas.pad * 2
        ctx.strokeStyle = Qt.rgba(canvas.overlayColor.r, canvas.overlayColor.g, canvas.overlayColor.b, 0.9)
        ctx.lineWidth = 1.1
        ctx.setLineDash([2, 2])
        ctx.beginPath()
        var started = false
        for (var o = 0; o < overlay.length; o++) {
          var y = Model.valueToY(overlay[o].c, bounds, canvas.height, canvas.pad)
          if (y === null) continue
          var x = span > 0 ? canvas.pad + ((overlay[o].t - t0) / span) * innerW : canvas.pad
          if (!started) { ctx.moveTo(x, y); started = true }
          else ctx.lineTo(x, y)
        }
        if (started) ctx.stroke()
        ctx.setLineDash([])
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(500))
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

        // ---- Header: title, watchlists, range chips, freshness.
        Item {
          width: parent.width
          height: Math.max(headerTitle.implicitHeight, chips.implicitHeight)

          Text {
            id: headerTitle
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: "Stocks · " + root.activeList.name
            color: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Row {
            id: chips
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Repeater {
              model: Model.CHART_RANGES

              Rectangle {
                id: chip
                required property string modelData
                readonly property bool selected: modelData === root.activeRange
                width: chipText.implicitWidth + Style.space(12)
                height: chipText.implicitHeight + Style.space(6)
                radius: Style.cornerRadius
                color: chip.selected
                  ? Style.selectedFillFor(root.barForeground, Color.accent)
                  : (chipMouse.containsMouse ? Style.hoverFillFor(root.barForeground, Color.accent) : "transparent")

                Text {
                  id: chipText
                  anchors.centerIn: parent
                  text: root.rangeLabel(chip.modelData)
                  color: chip.selected ? root.barForeground : root.mutedForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: chip.selected
                }

                MouseArea {
                  id: chipMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectRange(chip.modelData)
                }
              }
            }

          }

          Text {
            id: updatedText
            anchors.right: headerSettings.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: root.lastUpdated
              ? "Updated " + Qt.formatTime(root.lastUpdated, "HH:mm")
              : (root.loading ? "Loading…" : "")
            color: root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Rectangle {
            id: headerSettings
            anchors.right: headerRefresh.left
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            width: settingsText.implicitWidth + Style.space(10)
            height: settingsText.implicitHeight + Style.space(6)
            radius: Style.cornerRadius
            color: settingsMouse.containsMouse ? Style.hoverFillFor(root.barForeground, Color.accent) : "transparent"

            Text {
              id: settingsText
              anchors.centerIn: parent
              text: "⚙"
              color: settingsMouse.containsMouse ? root.barForeground : root.mutedForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            MouseArea {
              id: settingsMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleSettings()
            }
          }

          Rectangle {
            id: headerRefresh
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            width: refreshText.implicitWidth + Style.space(10)
            height: refreshText.implicitHeight + Style.space(6)
            radius: Style.cornerRadius
            color: refreshMouse.containsMouse ? Style.hoverFillFor(root.barForeground, Color.accent) : "transparent"

            Text {
              id: refreshText
              anchors.centerIn: parent
              text: "⟳"
              color: refreshMouse.containsMouse ? root.barForeground : root.mutedForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            MouseArea {
              id: refreshMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.refresh()
            }
          }
        }

        // ---- Settings panel: refresh interval, display currency, and JSON import/export.
        Rectangle {
          visible: root.settingsOpen
          width: parent.width - Style.space(16)
          x: Style.space(8)
          height: visible ? settingsColumn.implicitHeight + Style.space(16) : 0
          radius: Style.cornerRadius
          color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06)
          border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.16)
          border.width: 1

          Column {
            id: settingsColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            spacing: Style.space(8)

            Text {
              text: "Settings"
              color: root.barForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Row {
              spacing: Style.space(6)
              height: Style.space(24)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Refresh interval"
                color: root.mutedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              TextField {
                width: Style.space(44)
                height: parent.height
                text: root.refreshMinutesDraft
                foreground: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                verticalPadding: Style.space(2)
                onTextChanged: root.refreshMinutesDraft = text
                onAccepted: root.saveRefreshMinutesDraft()
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "minutes"
                color: root.mutedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Rectangle {
                width: saveIntervalText.implicitWidth + Style.space(12)
                height: parent.height
                radius: Style.cornerRadius
                color: saveIntervalMouse.containsMouse ? Style.hoverFillFor(root.barForeground, Color.accent) : "transparent"
                Text {
                  id: saveIntervalText
                  anchors.centerIn: parent
                  text: "Save"
                  color: root.barForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                MouseArea {
                  id: saveIntervalMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.saveRefreshMinutesDraft()
                }
              }
            }

            Row {
              spacing: Style.space(6)
              height: Style.space(24)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Display currency"
                color: root.mutedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Rectangle {
                readonly property bool active: root.displayCurrency !== ""
                width: currencySettingsText.implicitWidth + Style.space(12)
                height: parent.height
                radius: Style.cornerRadius
                color: active
                  ? Style.selectedFillFor(root.barForeground, Color.accent)
                  : (currencySettingsMouse.containsMouse ? Style.hoverFillFor(root.barForeground, Color.accent) : "transparent")

                Text {
                  id: currencySettingsText
                  anchors.centerIn: parent
                  text: (root.displayCurrency !== "" ? root.displayCurrency : "Native") + " ⇄"
                  color: parent.active ? root.barForeground : root.mutedForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: parent.active
                }

                MouseArea {
                  id: currencySettingsMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function(mouse) { root.selectCurrency(mouse.button === Qt.RightButton ? -1 : 1) }
                }
              }
            }

            Row {
              spacing: Style.space(6)
              height: Style.space(24)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Stock list JSON"
                color: root.mutedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Rectangle {
                width: exportText.implicitWidth + Style.space(12)
                height: parent.height
                radius: Style.cornerRadius
                color: exportMouse.containsMouse ? Style.hoverFillFor(root.barForeground, Color.accent) : "transparent"
                Text {
                  id: exportText
                  anchors.centerIn: parent
                  text: "Export"
                  color: root.barForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                MouseArea {
                  id: exportMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.requestExportWatchlists()
                }
              }

              Rectangle {
                width: importText.implicitWidth + Style.space(12)
                height: parent.height
                radius: Style.cornerRadius
                color: importMouse.containsMouse ? Style.hoverFillFor(root.barForeground, Color.accent) : "transparent"
                Text {
                  id: importText
                  anchors.centerIn: parent
                  text: "Import"
                  color: root.barForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                MouseArea {
                  id: importMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.requestImportWatchlists()
                }
              }

              Rectangle {
                width: folderText.implicitWidth + Style.space(12)
                height: parent.height
                radius: Style.cornerRadius
                color: folderMouse.containsMouse ? Style.hoverFillFor(root.barForeground, Color.accent) : "transparent"
                Text {
                  id: folderText
                  anchors.centerIn: parent
                  text: "Open JSON"
                  color: root.barForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                MouseArea {
                  id: folderMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openWatchlistsFile()
                }
              }
            }

            Text {
              width: parent.width
              text: root.fileDialogMessage !== "" ? root.fileDialogMessage : root.watchlistsPath
              elide: Text.ElideMiddle
              color: root.mutedForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // ---- Watchlist switcher and inline list editor.
        Row {
          width: parent.width - Style.space(16)
          x: Style.space(8)
          spacing: Style.space(4)

          Repeater {
            model: root.watchlists

            Rectangle {
              id: listChip
              required property var modelData
              required property int index
              readonly property bool selected: index === root.activeWatchlist
              width: listText.implicitWidth + Style.space(12)
              height: listText.implicitHeight + Style.space(6)
              radius: Style.cornerRadius
              color: listChip.selected
                ? Style.selectedFillFor(root.barForeground, Color.accent)
                : (listMouse.containsMouse ? Style.hoverFillFor(root.barForeground, Color.accent) : "transparent")

              Text {
                id: listText
                anchors.centerIn: parent
                text: listChip.modelData.name
                color: listChip.selected ? root.barForeground : root.mutedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: listChip.selected
              }

              MouseArea {
                id: listMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectWatchlist(listChip.index)
              }
            }
          }

          Rectangle {
            width: addListText.implicitWidth + Style.space(12)
            height: addListText.implicitHeight + Style.space(6)
            radius: Style.cornerRadius
            color: addListMouse.containsMouse ? Style.hoverFillFor(root.barForeground, Color.accent) : "transparent"
            Text {
              id: addListText
              anchors.centerIn: parent
              text: "+ Watchlist"
              color: root.mutedForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            MouseArea {
              id: addListMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.beginAddWatchlist()
            }
          }

          TextField {
            id: listNameField
            width: Style.space(110)
            text: root.activeList.name
            foreground: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            verticalPadding: Style.space(2)
            placeholderText: "List name"
            onAccepted: root.renameActiveWatchlist(text)
            onEditingFinished: root.renameActiveWatchlist(text)
          }

          Rectangle {
            visible: root.watchlists.length > 1
            width: delListText.implicitWidth + Style.space(10)
            height: delListText.implicitHeight + Style.space(6)
            radius: Style.cornerRadius
            color: delListMouse.containsMouse ? Style.hoverFillFor(root.barForeground, Color.accent) : "transparent"
            Text {
              id: delListText
              anchors.centerIn: parent
              text: "Delete list"
              color: root.urgentForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            MouseArea {
              id: delListMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.deleteActiveWatchlist()
            }
          }
        }

        PanelSeparator { foreground: root.barForeground }

        Row {
          width: parent.width - Style.space(16)
          x: Style.space(8)
          spacing: Style.space(6)

          readonly property real controlHeight: Style.space(24)

          TextField {
            id: symbolField
            width: Style.space(170)
            height: parent.controlHeight
            text: root.symbolDraft
            visible: root.editorOpen
            foreground: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            placeholderText: "Symbol, e.g. TW:2330"
            verticalPadding: Style.space(2)
            onTextChanged: root.symbolDraft = text
            onAccepted: root.saveSymbolDraft()
          }

          Rectangle {
            width: symbolActionText.implicitWidth + Style.space(12)
            height: parent.controlHeight
            radius: Style.cornerRadius
            color: symbolActionMouse.containsMouse ? Style.hoverFillFor(root.barForeground, Color.accent) : "transparent"
            Text {
              id: symbolActionText
              anchors.centerIn: parent
              text: root.editorOpen ? (root.editingIndex >= 0 ? "Save" : "Add") : "+ Symbol"
              color: root.barForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            MouseArea {
              id: symbolActionMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.editorOpen ? root.saveSymbolDraft() : root.beginAddSymbol()
            }
          }

          Rectangle {
            visible: root.editorOpen
            width: cancelText.implicitWidth + Style.space(12)
            height: parent.controlHeight
            radius: Style.cornerRadius
            color: cancelMouse.containsMouse ? Style.hoverFillFor(root.barForeground, Color.accent) : "transparent"
            Text {
              id: cancelText
              anchors.centerIn: parent
              text: "Cancel"
              color: root.mutedForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            MouseArea {
              id: cancelMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.editorOpen = false
            }
          }
        }

        // ---- One row per symbol: SYM · name · sparkline · price · change.
        Column {
          width: parent.width
          spacing: 0

          Repeater {
            model: root.shownQuotes

            Rectangle {
              id: row
              required property var modelData
              required property int index
              readonly property bool valid: Model.isValid(modelData)
              readonly property bool selected: index === root.selectedIndex && root.hasSelection
              readonly property var series: root.activeRange === "1d"
                ? (modelData.series || [])
                : Model.convertSeries(root.chartSeries[modelData.symbol] || [],
                    Model.rateFor(modelData.nativeCurrency || modelData.currency, root.displayCurrency, root.rates))

              width: parent.width
              height: symbolText.implicitHeight + Style.space(14)
              radius: Style.cornerRadius
              color: row.selected
                ? Style.selectedFillFor(root.barForeground, Color.accent)
                : (rowMouse.containsMouse && row.valid ? Style.hoverFillFor(root.barForeground, Color.accent) : "transparent")

              Text {
                id: symbolText
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(64)
                text: row.modelData.symbol
                elide: Text.ElideRight
                color: row.valid ? root.barForeground : root.mutedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                anchors.left: symbolText.right
                anchors.right: spark.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: row.valid ? row.modelData.name : (row.modelData.error || "No data")
                elide: Text.ElideRight
                color: root.mutedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.italic: !row.valid
              }

              SeriesCanvas {
                id: spark
                anchors.right: priceText.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(72)
                height: Style.space(20)
                visible: row.valid
                series: row.series
                lineColor: root.directionColor(row.series)
                lineWidth: 1.25
                pad: 1.5
              }

              Text {
                id: priceText
                anchors.right: changeText.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(76)
                horizontalAlignment: Text.AlignRight
                text: row.valid ? Model.formatPrice(row.modelData.price) : ""
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                id: changeText
                anchors.right: editText.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(112)
                horizontalAlignment: Text.AlignRight
                text: row.valid ? Model.formatChange(row.modelData) : ""
                color: root.trendColor(row.modelData)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                id: editText
                anchors.right: deleteText.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: "Edit"
                color: editMouse.containsMouse ? root.barForeground : root.mutedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                MouseArea {
                  id: editMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.beginEditSymbol(row.index)
                }
              }

              Text {
                id: deleteText
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: "×"
                color: deleteMouse.containsMouse ? root.urgentForeground : root.mutedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                MouseArea {
                  id: deleteMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.deleteSymbol(row.index)
                }
              }

              MouseArea {
                id: rowMouse
                anchors.left: parent.left
                anchors.right: changeText.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                hoverEnabled: true
                cursorShape: row.valid ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.selectQuote(row.index)
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

        PanelSeparator {
          visible: root.hasSelection
          foreground: root.barForeground
        }

        // ---- Detail block for the selected symbol.
        Column {
          id: detail
          visible: root.hasSelection
          width: parent.width
          spacing: Style.space(8)

          readonly property var quote: root.selectedQuote
          readonly property var series: root.hasSelection ? root.seriesFor(root.selectedQuote) : []
          readonly property var analysis: root.analysisFor(quote, series)
          readonly property var sma20Series: Model.smaSeries(series, 20)
          readonly property var bounds: Model.seriesBounds(series)
          readonly property real statLabelWidth: Style.space(84)
          readonly property real statValueWidth: (width - Style.space(16)) / 2 - statLabelWidth

          Item {
            width: parent.width
            height: Math.max(nameColumn.implicitHeight, priceColumn.implicitHeight)

            Column {
              id: nameColumn
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.right: priceColumn.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: detail.quote ? (detail.quote.name || detail.quote.symbol) : ""
                elide: Text.ElideRight
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }
              Text {
                width: parent.width
                text: detail.quote
                  ? [detail.quote.symbol, detail.quote.exchange, root.currencyLabel(detail.quote)].filter(function(p) { return !!p }).join(" · ")
                  : ""
                elide: Text.ElideRight
                color: root.mutedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Column {
              id: priceColumn
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              Text {
                anchors.right: parent.right
                text: detail.quote ? Model.formatPrice(detail.quote.price) : ""
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                font.bold: true
              }
              Text {
                anchors.right: parent.right
                text: detail.quote ? Model.formatChange(detail.quote) : ""
                color: root.trendColor(detail.quote)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          Item {
            width: parent.width
            height: Style.space(112)

            SeriesCanvas {
              id: bigChart
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              series: detail.series
              lineColor: root.directionColor(detail.series)
              lineWidth: 1.75
              pad: 4
              fill: true
              referenceValue: root.activeRange === "1d" && detail.quote ? detail.quote.prevClose : null
              overlaySeries: detail.sma20Series
              overlayColor: root.mutedForeground
              supportValue: detail.analysis.support
              resistanceValue: detail.analysis.resistance
            }

            Text {
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              text: detail.bounds ? Model.formatPrice(detail.bounds.max) : ""
              color: root.mutedForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              anchors.bottom: parent.bottom
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              text: detail.bounds ? Model.formatPrice(detail.bounds.min) : ""
              color: root.mutedForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              anchors.centerIn: parent
              visible: detail.series.length < 2
              text: root.chartLoading ? "Loading chart…" : "No chart data"
              color: root.mutedForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.italic: true
            }
          }

          Item {
            width: parent.width
            height: firstStamp.implicitHeight
            visible: detail.series.length >= 2

            Text {
              id: firstStamp
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              text: detail.series.length ? root.formatStamp(detail.series[0].t, root.activeRange) : ""
              color: root.mutedForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              text: detail.series.length ? root.formatStamp(detail.series[detail.series.length - 1].t, root.activeRange) : ""
              color: root.mutedForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Text {
              leftPadding: Style.space(8)
              text: "Technical analysis"
              color: root.barForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Repeater {
              model: detail.analysis.lines

              Text {
                required property string modelData
                width: parent.width
                leftPadding: Style.space(8)
                rightPadding: Style.space(8)
                text: "• " + modelData
                wrapMode: Text.WordWrap
                color: root.mutedForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              visible: detail.sma20Series.length >= 2
              leftPadding: Style.space(8)
              text: "Dashed line: SMA20 · Green/red dashed levels: recent support/resistance"
              color: root.mutedForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.italic: true
            }
          }

          Grid {
            id: stats
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            columns: 4
            columnSpacing: 0
            rowSpacing: Style.space(4)

            readonly property var entries: detail.quote ? [
              ["Prev close", Model.formatPrice(detail.quote.prevClose)],
              ["Open", Model.formatPrice(detail.quote.open)],
              ["Day range", detail.quote.dayLow !== null && detail.quote.dayHigh !== null
                ? Model.formatPrice(detail.quote.dayLow) + " – " + Model.formatPrice(detail.quote.dayHigh) : ""],
              ["52w range", detail.quote.week52Low !== null && detail.quote.week52High !== null
                ? Model.formatPrice(detail.quote.week52Low) + " – " + Model.formatPrice(detail.quote.week52High) : ""],
              ["Volume", Model.formatVolume(detail.quote.volume)],
              ["Last trade", detail.quote.marketTime !== null ? Qt.formatDateTime(new Date(detail.quote.marketTime * 1000), "ddd HH:mm") : ""]
            ] : []

            Repeater {
              model: stats.entries.length * 2

              Text {
                required property int index
                readonly property bool isLabel: index % 2 === 0
                readonly property var entry: stats.entries[Math.floor(index / 2)]
                width: isLabel ? detail.statLabelWidth : detail.statValueWidth
                text: entry ? (isLabel ? entry[0] : (entry[1] || "—")) : ""
                elide: Text.ElideRight
                color: isLabel ? root.mutedForeground : root.barForeground
                font.family: root.fontFamily
                font.pixelSize: isLabel ? Style.font.caption : Style.font.bodySmall
              }
            }
          }

          Text {
            id: yahooLink
            leftPadding: Style.space(8)
            text: "Open on Yahoo Finance ↗"
            color: linkMouse.containsMouse ? root.barForeground : root.mutedForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.underline: linkMouse.containsMouse

            MouseArea {
              id: linkMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (detail.quote) root.openQuotePage(detail.quote.symbol)
            }
          }
        }

        PanelSeparator { foreground: root.barForeground }

        // ---- Footer: the failure reason when there is one, hints otherwise.
        Text {
          width: parent.width
          leftPadding: Style.space(8)
          rightPadding: Style.space(8)
          text: root.fetchError !== ""
            ? "Could not update: " + root.fetchError
            : "Click a row for details · Middle-click the tape to refresh · Right-click to pause"
          wrapMode: Text.WordWrap
          color: root.fetchError !== "" ? root.urgentForeground : root.mutedForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
