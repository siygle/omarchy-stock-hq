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
