import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Level 2: one symbol with the range chart, full stats and the local agent
// (preset or custom prompt, run in the background, answer rendered here).
Column {
  id: detail

  property var stocks: null

  spacing: Style.space(8)

  readonly property var quote: stocks.detailQuote
  readonly property bool valid: Model.isValid(quote)
  readonly property var series: valid ? stocks.seriesFor(quote) : []
  readonly property var bounds: Model.seriesBounds(series)
  readonly property real statLabelWidth: Style.space(92)
  readonly property real statValueWidth: (width - Style.space(16)) / 2 - statLabelWidth

  readonly property var runner: stocks.agentRunner
  readonly property var result: quote ? runner.resultFor(quote.symbol) : null
  readonly property bool runningHere: runner.running && quote !== null && runner.runningSymbol === quote.symbol
  readonly property bool busyElsewhere: runner.running && !runningHere

  function statusText() {
    if (busyElsewhere) return "Agent busy with " + runner.runningSymbol
    var r = result
    if (!r) return "Pick a prompt to analyse " + (quote ? quote.symbol : "") + " with the local agent"
    var name = r.prompt || "Analysis"
    var when = r.at ? Qt.formatDateTime(new Date(r.at), "d MMM HH:mm") : ""
    if (r.status === "running") return "Running " + name + "… " + runner.elapsedFor(quote.symbol)
    if (r.status === "error") return name + " failed (exit " + r.exitCode + ")"
    if (r.status === "cancelled") return name + " cancelled"
    if (r.status === "saved") return name + " · saved " + when
    return name + " · " + when
  }

  // ---- Top bar: back, range chips.
  Item {
    width: parent.width
    height: backChip.height

    Chip {
      id: backChip
      anchors.left: parent.left
      anchors.leftMargin: Style.space(4)
      stocks: detail.stocks
      text: "‹ All"
      onClicked: detail.stocks.showList()
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(4)

      Repeater {
        model: Model.CHART_RANGES

        Chip {
          required property string modelData
          stocks: detail.stocks
          text: detail.stocks.rangeLabel(modelData)
          selected: modelData === detail.stocks.activeRange
          onClicked: detail.stocks.selectRange(modelData)
        }
      }
    }

    Text {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: detail.stocks.lastUpdated ? "Updated " + Qt.formatTime(detail.stocks.lastUpdated, "HH:mm") : ""
      color: detail.stocks.mutedForeground
      font.family: detail.stocks.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  PanelSeparator { foreground: detail.stocks.barForeground }

  // ---- Name and price.
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
        color: detail.stocks.barForeground
        font.family: detail.stocks.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
      Text {
        width: parent.width
        text: detail.quote
          ? [detail.quote.symbol, detail.quote.exchange, detail.stocks.currencyLabel(detail.quote)].filter(function(p) { return !!p }).join(" · ")
          : ""
        elide: Text.ElideRight
        color: detail.stocks.mutedForeground
        font.family: detail.stocks.fontFamily
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
        color: detail.stocks.barForeground
        font.family: detail.stocks.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
      }
      Text {
        anchors.right: parent.right
        text: detail.quote ? Model.formatChange(detail.quote) : ""
        color: detail.stocks.trendColor(detail.quote)
        font.family: detail.stocks.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }

  // ---- Chart.
  Item {
    width: parent.width
    height: Style.space(180)

    SeriesCanvas {
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      series: detail.series
      lineColor: detail.stocks.directionColor(detail.series)
      lineWidth: 1.75
      pad: 4
      fill: true
      referenceValue: detail.stocks.activeRange === "1d" && detail.quote ? detail.quote.prevClose : null
    }

    Text {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      text: detail.bounds ? Model.formatPrice(detail.bounds.max) : ""
      color: detail.stocks.mutedForeground
      font.family: detail.stocks.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      text: detail.bounds ? Model.formatPrice(detail.bounds.min) : ""
      color: detail.stocks.mutedForeground
      font.family: detail.stocks.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      anchors.centerIn: parent
      visible: detail.series.length < 2
      text: detail.stocks.chartLoading ? "Loading chart…" : "No chart data"
      color: detail.stocks.mutedForeground
      font.family: detail.stocks.fontFamily
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
      text: detail.series.length ? detail.stocks.formatStamp(detail.series[0].t, detail.stocks.activeRange) : ""
      color: detail.stocks.mutedForeground
      font.family: detail.stocks.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      text: detail.series.length ? detail.stocks.formatStamp(detail.series[detail.series.length - 1].t, detail.stocks.activeRange) : ""
      color: detail.stocks.mutedForeground
      font.family: detail.stocks.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // ---- Stats.
  Grid {
    id: stats
    anchors.left: parent.left
    anchors.leftMargin: Style.space(8)
    columns: 4
    columnSpacing: 0
    rowSpacing: Style.space(4)

    readonly property var entries: {
      var q = detail.quote
      if (!q) return []
      var w52 = Model.rangePosition(q.price, q.week52Low, q.week52High)
      var dayRange = Model.dayRangePct(q)
      return [
        ["Prev close", Model.formatPrice(q.prevClose)],
        ["Open", Model.formatPrice(q.open)],
        ["Day range", q.dayLow !== null && q.dayHigh !== null ? Model.formatPrice(q.dayLow) + " – " + Model.formatPrice(q.dayHigh) : ""],
        ["52w range", q.week52Low !== null && q.week52High !== null ? Model.formatPrice(q.week52Low) + " – " + Model.formatPrice(q.week52High) : ""],
        ["Gap", Model.formatSignedPct(Model.gapPct(q))],
        ["Day span", dayRange !== null ? dayRange.toFixed(2) + "%" : ""],
        ["Off 52w high", Model.formatSignedPct(Model.offHighPct(q))],
        ["52w position", w52 !== null ? Math.round(w52 * 100) + "%" : ""],
        ["Volume", Model.formatVolume(q.volume)],
        ["Last trade", q.marketTime !== null ? Qt.formatDateTime(new Date(q.marketTime * 1000), "ddd HH:mm") : ""]
      ]
    }

    Repeater {
      model: stats.entries.length * 2

      Text {
        required property int index
        readonly property bool isLabel: index % 2 === 0
        readonly property var entry: stats.entries[Math.floor(index / 2)]
        width: isLabel ? detail.statLabelWidth : detail.statValueWidth
        text: entry ? (isLabel ? entry[0] : (entry[1] || "—")) : ""
        elide: Text.ElideRight
        color: isLabel ? detail.stocks.mutedForeground : detail.stocks.barForeground
        font.family: detail.stocks.fontFamily
        font.pixelSize: isLabel ? Style.font.caption : Style.font.bodySmall
      }
    }
  }

  Text {
    leftPadding: Style.space(8)
    text: "Open on Yahoo Finance ↗"
    color: linkMouse.containsMouse ? detail.stocks.barForeground : detail.stocks.mutedForeground
    font.family: detail.stocks.fontFamily
    font.pixelSize: Style.font.caption
    font.underline: linkMouse.containsMouse

    MouseArea {
      id: linkMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: if (detail.quote) detail.stocks.openQuotePage(detail.quote.symbol)
    }
  }

  PanelSeparator { foreground: detail.stocks.barForeground }

  // ---- Agent: presets, custom prompt, status, rendered answer.
  Flow {
    x: Style.space(8)
    width: parent.width - Style.space(16)
    spacing: Style.space(4)

    Text {
      rightPadding: Style.space(6)
      text: "Agent"
      color: detail.stocks.barForeground
      font.family: detail.stocks.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }

    Repeater {
      model: detail.stocks.agentPrompts

      Chip {
        required property var modelData
        stocks: detail.stocks
        text: modelData.name
        active: !detail.runner.running
        selected: detail.result !== null && detail.result.prompt === modelData.name
        onClicked: detail.stocks.runAgent(modelData.name, modelData.prompt)
      }
    }
  }

  Item {
    width: parent.width
    height: promptField.implicitHeight

    TextField {
      id: promptField
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      enabled: !detail.runner.running
      placeholderText: "Custom prompt — {symbol} {name} {price} {changePct} {quote} … ⏎ to run"
      foreground: detail.stocks.barForeground
      font.family: detail.stocks.fontFamily
      font.pixelSize: Style.font.bodySmall
      verticalPadding: Style.spacing.controlPaddingY
      onActiveFocusChanged: detail.stocks.editing = activeFocus
      onAccepted: {
        if (text.replace(/\s+/g, "") === "") return
        detail.stocks.runAgent("Custom", text)
        detail.stocks.releaseInput()
      }
      Keys.onEscapePressed: detail.stocks.releaseInput()
    }
  }

  Item {
    width: parent.width
    height: Math.max(statusLine.implicitHeight, statusActions.height)

    Text {
      id: statusLine
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: statusActions.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: detail.statusText()
      elide: Text.ElideRight
      color: detail.result && detail.result.status === "error" ? detail.stocks.urgentForeground : detail.stocks.mutedForeground
      font.family: detail.stocks.fontFamily
      font.pixelSize: Style.font.caption
    }

    Row {
      id: statusActions
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Chip {
        visible: detail.runningHere
        stocks: detail.stocks
        text: "Cancel"
        onClicked: detail.runner.cancel()
      }
      Chip {
        visible: detail.result !== null && (detail.result.status === "done" || detail.result.status === "saved")
        stocks: detail.stocks
        text: "Open file ↗"
        onClicked: detail.stocks.openAgentFile(detail.quote.symbol)
      }
    }
  }

  Flickable {
    id: answer
    x: Style.space(8)
    width: parent.width - Style.space(16)
    height: Math.min(answerText.implicitHeight, Style.space(280))
    visible: detail.result !== null && String(detail.result.output || "") !== ""
    contentWidth: width
    contentHeight: answerText.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Text {
      id: answerText
      width: answer.width
      text: detail.result ? String(detail.result.output || "") : ""
      textFormat: Text.MarkdownText
      wrapMode: Text.Wrap
      color: detail.stocks.barForeground
      linkColor: Color.accent
      font.family: detail.stocks.fontFamily
      font.pixelSize: Style.font.bodySmall
      onLinkActivated: function(link) {
        if (detail.stocks.bar && typeof detail.stocks.bar.run === "function")
          detail.stocks.bar.run("xdg-open " + Model.shellQuote(link))
      }
    }
  }

  // Keep the newest streamed lines in view while a run is in progress.
  Connections {
    target: answerText
    function onImplicitHeightChanged() {
      if (detail.runningHere) answer.contentY = Math.max(0, answerText.implicitHeight - answer.height)
    }
  }

  Item { width: 1; height: Style.space(2) }
}
