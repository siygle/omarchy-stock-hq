import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Level 1: one dense row per symbol with every number the chart endpoint
// gives us, sortable by column. Clicking a row opens DetailView (level 2).
Column {
  id: table

  property var stocks: null

  spacing: Style.space(6)

  readonly property real gap: Style.space(6)
  readonly property var w: ({
    symbol: Style.space(64), name: Style.space(96), price: Style.space(72), change: Style.space(62),
    changePct: Style.space(62), dayPos: Style.space(84), gap: Style.space(54), range: Style.space(50),
    week52Pos: Style.space(72), offHigh: Style.space(58), volume: Style.space(54), spark: Style.space(64),
    time: Style.space(40), remove: Style.space(14)
  })
  // Column order, header label, sort key ("" = not sortable), alignment.
  readonly property var columns: [
    { id: "symbol", label: "Symbol", sort: "symbol", right: false },
    { id: "name", label: "Name", sort: "", right: false },
    { id: "price", label: "Last", sort: "price", right: true },
    { id: "change", label: "Chg", sort: "change", right: true },
    { id: "changePct", label: "Chg%", sort: "changePct", right: true },
    { id: "dayPos", center: true, label: "Day range", sort: "dayPos", right: false },
    { id: "gap", label: "Gap", sort: "gap", right: true },
    { id: "range", label: "Range", sort: "range", right: true },
    { id: "week52Pos", center: true, label: "52w", sort: "week52Pos", right: false },
    { id: "offHigh", label: "Off high", sort: "offHigh", right: true },
    { id: "volume", label: "Vol", sort: "volume", right: true },
    { id: "spark", center: true, label: "1D", sort: "", right: false },
    { id: "time", label: "Time", sort: "", right: true },
    { id: "remove", label: "", sort: "", right: false }
  ]

  function signColor(value) {
    if (value === null || value === undefined) return stocks.barForeground
    if (value < 0) return stocks.downColor
    if (value > 0) return stocks.upColor
    return stocks.barForeground
  }

  function timeLabel(ts) {
    if (ts === null || ts === undefined) return ""
    var d = new Date(ts * 1000)
    var today = new Date()
    return Qt.formatDateTime(d, d.toDateString() === today.toDateString() ? "HH:mm" : "ddd")
  }

  component Cell: Text {
    property string column: ""
    width: table.w[column] || 0
    elide: Text.ElideRight
    color: table.stocks.barForeground
    font.family: table.stocks.fontFamily
    font.pixelSize: Style.font.bodySmall
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
  }

  // ---- Header: title, market summary, currency switch, freshness.
  Item {
    width: parent.width
    height: Math.max(title.implicitHeight, currencyChip.height)

    Row {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(12)

      Text {
        id: title
        text: "Stocks"
        color: table.stocks.barForeground
        font.family: table.stocks.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)
        visible: table.stocks.validCount > 0

        Text {
          text: "▲" + table.stocks.summary.up
          color: table.stocks.upColor
          font.family: table.stocks.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          text: "▼" + table.stocks.summary.down
          color: table.stocks.downColor
          font.family: table.stocks.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          text: "avg " + Model.formatSignedPct(table.stocks.summary.avgPct)
          color: table.signColor(table.stocks.summary.avgPct)
          font.family: table.stocks.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }

    Row {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(10)

      // Display currency: click cycles forward, right-click back.
      Chip {
        id: currencyChip
        stocks: table.stocks
        text: (table.stocks.displayCurrency !== "" ? table.stocks.displayCurrency : "Native") + " ⇄"
        selected: table.stocks.displayCurrency !== ""
        onClicked: function(button) { table.stocks.selectCurrency(button === Qt.RightButton ? -1 : 1) }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: table.stocks.lastUpdated
          ? "Updated " + Qt.formatTime(table.stocks.lastUpdated, "HH:mm")
          : (table.stocks.loading ? "Loading…" : "")
        color: table.stocks.mutedForeground
        font.family: table.stocks.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  PanelSeparator { foreground: table.stocks.barForeground }

  // ---- Column headers; sortable ones cycle desc -> asc -> watchlist order.
  Row {
    x: Style.space(8)
    spacing: table.gap

    Repeater {
      model: table.columns

      Text {
        id: header
        required property var modelData
        readonly property bool sorted: modelData.sort !== "" && modelData.sort === table.stocks.sortKey
        width: table.w[modelData.id]
        horizontalAlignment: modelData.center ? Text.AlignHCenter : (modelData.right ? Text.AlignRight : Text.AlignLeft)
        text: modelData.label + (header.sorted ? (table.stocks.sortDesc ? " ↓" : " ↑") : "")
        elide: Text.ElideRight
        color: header.sorted || headerMouse.containsMouse ? table.stocks.barForeground : table.stocks.mutedForeground
        font.family: table.stocks.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: header.sorted

        MouseArea {
          id: headerMouse
          anchors.fill: parent
          enabled: header.modelData.sort !== ""
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: table.stocks.cycleSort(header.modelData.sort)
        }
      }
    }
  }

  // ---- One row per symbol.
  Column {
    width: parent.width
    spacing: 0

    Repeater {
      model: table.stocks.tableQuotes

      Rectangle {
        id: row
        required property var modelData
        required property int index
        readonly property var q: modelData
        readonly property bool valid: Model.isValid(q)
        readonly property bool cursor: index === table.stocks.cursorIndex
        readonly property bool hovered: rowMouse.containsMouse || removeMouse.containsMouse

        width: parent.width
        height: symbolCell.implicitHeight + Style.space(10)
        radius: Style.cornerRadius
        color: row.cursor
          ? Style.selectedFillFor(table.stocks.barForeground, Color.accent)
          : (row.hovered && row.valid ? Style.hoverFillFor(table.stocks.barForeground, Color.accent) : "transparent")

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: row.valid ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: table.stocks.showDetail(row.q.symbol)
        }

        Row {
          x: Style.space(8)
          height: parent.height
          spacing: table.gap

          Cell {
            id: symbolCell
            column: "symbol"
            text: row.q.symbol
            font.bold: true
            font.pixelSize: Style.font.body
            color: row.valid ? table.stocks.barForeground : table.stocks.mutedForeground
          }
          Cell {
            column: "name"
            text: row.valid ? row.q.name : (row.q.error || "No data")
            color: table.stocks.mutedForeground
            font.italic: !row.valid
          }
          Cell {
            column: "price"
            horizontalAlignment: Text.AlignRight
            text: row.valid ? Model.formatPrice(row.q.price) : ""
            font.pixelSize: Style.font.body
          }
          Cell {
            column: "change"
            horizontalAlignment: Text.AlignRight
            text: row.valid ? Model.formatSignedNumber(row.q.change, row.q.price) : ""
            color: table.signColor(row.q.change)
          }
          Cell {
            column: "changePct"
            horizontalAlignment: Text.AlignRight
            text: row.valid ? Model.formatSignedPct(row.q.changePct) : ""
            color: table.signColor(row.q.changePct)
            font.bold: true
          }
          RangeBar {
            width: table.w.dayPos
            height: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            visible: row.valid
            value: row.q.price
            low: row.q.dayLow
            high: row.q.dayHigh
            reference: row.q.prevClose
            trackColor: table.stocks.mutedForeground
            dotColor: table.stocks.trendColor(row.q)
          }
          Cell {
            column: "gap"
            horizontalAlignment: Text.AlignRight
            readonly property var v: Model.gapPct(row.q)
            text: row.valid ? Model.formatSignedPct(v) : ""
            color: table.signColor(v)
          }
          Cell {
            column: "range"
            horizontalAlignment: Text.AlignRight
            readonly property var v: Model.dayRangePct(row.q)
            text: row.valid && v !== null ? v.toFixed(2) + "%" : ""
          }
          RangeBar {
            width: table.w.week52Pos
            height: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            visible: row.valid
            value: row.q.price
            low: row.q.week52Low
            high: row.q.week52High
            trackColor: table.stocks.mutedForeground
            dotColor: table.stocks.barForeground
          }
          Cell {
            column: "offHigh"
            horizontalAlignment: Text.AlignRight
            readonly property var v: Model.offHighPct(row.q)
            text: row.valid ? Model.formatSignedPct(v) : ""
            color: v !== null && v > -2 ? table.stocks.upColor : table.stocks.mutedForeground
          }
          Cell {
            column: "volume"
            horizontalAlignment: Text.AlignRight
            text: row.valid ? Model.formatVolume(row.q.volume) : ""
            color: table.stocks.mutedForeground
          }
          SeriesCanvas {
            width: table.w.spark
            height: Style.space(18)
            anchors.verticalCenter: parent.verticalCenter
            visible: row.valid
            series: row.q.series || []
            lineColor: table.stocks.directionColor(row.q.series || [])
            referenceValue: row.q.prevClose
            lineWidth: 1.25
            pad: 1.5
          }
          Cell {
            column: "time"
            horizontalAlignment: Text.AlignRight
            text: row.valid ? table.timeLabel(row.q.marketTime) : ""
            color: table.stocks.mutedForeground
            font.pixelSize: Style.font.caption
          }
          Text {
            width: table.w.remove
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: "×"
            opacity: row.hovered ? 1 : 0
            color: removeMouse.containsMouse ? table.stocks.urgentForeground : table.stocks.mutedForeground
            font.family: table.stocks.fontFamily
            font.pixelSize: Style.font.body

            MouseArea {
              id: removeMouse
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: table.stocks.removeSymbol(row.q.symbol)
            }
          }
        }
      }
    }
  }

  Text {
    visible: table.stocks.loading
    leftPadding: Style.space(8)
    text: "Fetching quotes…"
    color: table.stocks.mutedForeground
    font.family: table.stocks.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.italic: true
  }

  // ---- Add symbols ("tsm, 2330.TW" works); pushed to the gist when syncing.
  Item {
    width: parent.width
    height: addField.implicitHeight

    TextField {
      id: addField
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      width: Style.space(260)
      placeholderText: "Add symbols, e.g. 2330.TW ⏎"
      foreground: table.stocks.barForeground
      font.family: table.stocks.fontFamily
      font.pixelSize: Style.font.bodySmall
      verticalPadding: Style.spacing.controlPaddingY
      onActiveFocusChanged: table.stocks.editing = activeFocus
      onAccepted: {
        table.stocks.addSymbols(text)
        text = ""
      }
      Keys.onEscapePressed: {
        text = ""
        table.stocks.releaseInput()
      }
    }

    Text {
      anchors.left: addField.right
      anchors.leftMargin: Style.space(10)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: "Click a row (or j/k + Enter) for chart & agent · hover a row and × to remove"
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignRight
      color: table.stocks.mutedForeground
      font.family: table.stocks.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  PanelSeparator { foreground: table.stocks.barForeground }

  // ---- Footer: fetch failure (if any) and gist sync state.
  Item {
    width: parent.width
    height: Math.max(footerText.implicitHeight, syncRow.height)

    readonly property var sync: table.stocks.gistSync

    Text {
      id: footerText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: syncRow.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: table.stocks.fetchError !== ""
        ? "Could not update: " + table.stocks.fetchError
        : (parent.sync.status === "error" ? "Gist sync failed: " + parent.sync.error : "Middle-click the tape to refresh · Right-click to pause")
      elide: Text.ElideRight
      color: table.stocks.fetchError !== "" || parent.sync.status === "error" ? table.stocks.urgentForeground : table.stocks.mutedForeground
      font.family: table.stocks.fontFamily
      font.pixelSize: Style.font.caption
    }

    Row {
      id: syncRow
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      readonly property var sync: parent.sync

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: syncRow.sync.configured
        text: {
          var s = syncRow.sync
          if (s.status === "pulling" || s.status === "pushing") return "Gist: syncing…"
          if (s.lastSynced) return "Gist ✓ " + Qt.formatTime(s.lastSynced, "HH:mm")
          return "Gist"
        }
        color: table.stocks.mutedForeground
        font.family: table.stocks.fontFamily
        font.pixelSize: Style.font.caption
      }

      Chip {
        visible: syncRow.sync.configured
        stocks: table.stocks
        text: "Sync"
        active: !syncRow.sync.busy
        onClicked: table.stocks.syncNow()
      }

      Chip {
        visible: syncRow.sync.configured
        stocks: table.stocks
        text: "Open gist ↗"
        onClicked: table.stocks.openGist()
      }

      Chip {
        visible: !syncRow.sync.configured
        stocks: table.stocks
        text: syncRow.sync.status === "creating" ? "Creating gist…" : "Create sync gist"
        active: !syncRow.sync.busy
        onClicked: syncRow.sync.create(table.stocks.symbols)
      }
    }
  }
}
