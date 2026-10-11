import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Level 1: the active watchlist as one dense row per symbol with every
// number the chart endpoint gives us, sortable by column, plus watchlist
// switching/editing and the settings box. Clicking a row opens DetailView.
Column {
  id: table

  property var stocks: null
  // Height budget from the panel; only the rows scroll to stay inside it.
  property real maxHeight: 100000

  spacing: Style.space(6)

  readonly property real gap: Style.space(6)
  readonly property var w: ({
    symbol: Style.space(64), name: Style.space(88), price: Style.space(72), change: Style.space(62),
    changePct: Style.space(62), dayPos: Style.space(84), gap: Style.space(54), range: Style.space(50),
    week52Pos: Style.space(72), offHigh: Style.space(58), volume: Style.space(54), spark: Style.space(60),
    time: Style.space(40), remove: Style.space(30)
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

  // ✎ on a row: load the symbol into the add field, which then replaces it.
  function editSymbol(symbol) {
    stocks.beginEditSymbol(symbol)
    addField.text = symbol
    addField.forceActiveFocus()
    addField.selectAll()
  }

  // Everything but the rows (visible children plus Column spacing), so the
  // rows area gets exactly the height that is left.
  readonly property real chromeHeight: {
    var h = 0
    var n = 0
    for (var i = 0; i < children.length; i++) {
      var c = children[i]
      if (!c.visible) continue
      n++
      if (c !== rowsArea) h += c.height
    }
    return h + spacing * Math.max(0, n - 1)
  }
  readonly property real rowHeight: Style.font.body + Style.space(14)

  onVisibleChanged: if (visible) listStrip.revealActive()

  Connections {
    target: table.stocks
    function onOpenedChanged() { if (table.stocks.opened) listStrip.revealActive() }
  }

  // Keep the keyboard cursor's row in view.
  Connections {
    target: table.stocks
    function onCursorIndexChanged() {
      var i = table.stocks.cursorIndex
      if (i < 0 || !rowsColumn.children[i]) return
      var item = rowsColumn.children[i]
      if (item.y < rowsArea.contentY) rowsArea.contentY = item.y
      else if (item.y + item.height > rowsArea.contentY + rowsArea.height)
        rowsArea.contentY = item.y + item.height - rowsArea.height
    }
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
        text: "Stock HQ"
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

      Chip {
        stocks: table.stocks
        text: "⚙"
        fontSize: Style.font.body
        selected: table.stocks.settingsOpen
        onClicked: table.stocks.toggleSettings()
      }

      Chip {
        stocks: table.stocks
        text: "⟳"
        fontSize: Style.font.body
        onClicked: table.stocks.refresh()
      }
    }
  }

  // ---- Settings box: refresh interval and the watchlists JSON file.
  Rectangle {
    visible: table.stocks.settingsOpen
    x: Style.space(8)
    width: parent.width - Style.space(16)
    height: settingsColumn.implicitHeight + Style.space(16)
    radius: Style.cornerRadius
    color: Qt.rgba(table.stocks.barForeground.r, table.stocks.barForeground.g, table.stocks.barForeground.b, 0.06)
    border.color: Qt.rgba(table.stocks.barForeground.r, table.stocks.barForeground.g, table.stocks.barForeground.b, 0.16)
    border.width: 1

    Column {
      id: settingsColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(8)
      spacing: Style.space(8)

      Row {
        spacing: Style.space(6)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Refresh every"
          color: table.stocks.mutedForeground
          font.family: table.stocks.fontFamily
          font.pixelSize: Style.font.caption
        }
        TextField {
          id: refreshField
          width: Style.space(48)
          text: String(table.stocks.refreshMinutes)
          foreground: table.stocks.barForeground
          font.family: table.stocks.fontFamily
          font.pixelSize: Style.font.caption
          verticalPadding: Style.space(2)
          onActiveFocusChanged: table.stocks.editing = activeFocus
          onAccepted: {
            table.stocks.saveRefreshMinutes(text)
            table.stocks.releaseInput()
          }
          Keys.onEscapePressed: table.stocks.releaseInput()
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "minutes ⏎"
          color: table.stocks.mutedForeground
          font.family: table.stocks.fontFamily
          font.pixelSize: Style.font.caption
        }

        Item { width: Style.space(18); height: 1 }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Watchlists JSON"
          color: table.stocks.mutedForeground
          font.family: table.stocks.fontFamily
          font.pixelSize: Style.font.caption
        }
        Chip {
          anchors.verticalCenter: parent.verticalCenter
          stocks: table.stocks
          text: "Export"
          onClicked: table.stocks.requestExportWatchlists()
        }
        Chip {
          anchors.verticalCenter: parent.verticalCenter
          stocks: table.stocks
          text: "Import"
          onClicked: table.stocks.requestImportWatchlists()
        }
        Chip {
          anchors.verticalCenter: parent.verticalCenter
          stocks: table.stocks
          text: "Open JSON ↗"
          onClicked: table.stocks.openWatchlistsFile()
        }
      }

      Text {
        width: parent.width
        text: table.stocks.fileDialogMessage !== "" ? table.stocks.fileDialogMessage : table.stocks.watchlistsPath
        elide: Text.ElideMiddle
        color: table.stocks.mutedForeground
        font.family: table.stocks.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // ---- Watchlists: a strip of list chips that scrolls sideways (wheel or
  //      scrollbar) once it outgrows the row, with add / rename (Enter) /
  //      delete pinned on the right.
  Item {
    x: Style.space(8)
    width: parent.width - Style.space(16)
    height: Math.max(listControls.height, listStrip.chipHeight) + (listStrip.overflowing ? Style.space(6) : 0)

    ListView {
      id: listStrip
      readonly property real chipHeight: Style.font.caption + Style.space(10)
      // Measured against the room the strip has without page buttons, so the
      // buttons appearing cannot feed back into it.
      readonly property bool overflowing: contentWidth > parent.width - listControls.width - Style.space(10)
      anchors.left: prevLists.visible ? prevLists.right : parent.left
      anchors.leftMargin: prevLists.visible ? Style.space(2) : 0
      anchors.right: nextLists.visible ? nextLists.left : listControls.left
      anchors.rightMargin: nextLists.visible ? Style.space(2) : Style.space(10)
      anchors.top: parent.top
      height: chipHeight
      orientation: ListView.Horizontal
      spacing: Style.space(4)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: table.stocks.watchlists
      // Few, small delegates: build them all so any chip can be revealed.
      cacheBuffer: 100000
      // Not currentIndex: ListView resets that on every model change, which
      // would break a binding to the active list.
      readonly property int activeIndex: table.stocks.activeWatchlist
      // Chip widths are only known after layout, so reveal the active list late.
      function revealActive() { Qt.callLater(listStrip.scrollToActive) }
      function scrollToActive() {
        var item = itemAtIndex(activeIndex)
        if (!item) return
        var left = item.x
        var right = item.x + item.width
        if (left < contentX) contentX = Math.max(originX, left - spacing)
        else if (right > contentX + width) contentX = Math.min(originX + contentWidth - width, right - width + spacing)
      }
      function page(direction) {
        var maxX = Math.max(0, contentWidth - width)
        contentX = Math.max(0, Math.min(maxX, contentX + direction * width * 0.8))
      }
      onActiveIndexChanged: revealActive()
      onCountChanged: revealActive()
      onWidthChanged: revealActive()
      onContentWidthChanged: revealActive()
      Component.onCompleted: revealActive()
      ScrollBar.horizontal: ScrollBar {
        policy: listStrip.overflowing ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        y: listStrip.height + Style.space(1)
        height: Style.space(4)
      }

      delegate: Chip {
        required property var modelData
        required property int index
        stocks: table.stocks
        text: modelData.name + " " + modelData.symbols.length
        selected: index === table.stocks.activeWatchlist
        onClicked: table.stocks.selectWatchlist(index)
      }

      // A vertical wheel scrolls the strip sideways; clicks pass through.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
          var delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
          var maxX = Math.max(0, listStrip.contentWidth - listStrip.width)
          listStrip.contentX = Math.max(0, Math.min(maxX, listStrip.contentX - delta))
        }
      }
    }

    // Page buttons appear only while some lists sit off-screen.
    Chip {
      id: prevLists
      visible: listStrip.overflowing
      anchors.left: parent.left
      anchors.top: parent.top
      stocks: table.stocks
      text: "‹"
      active: !listStrip.atXBeginning
      onClicked: listStrip.page(-1)
    }
    Chip {
      id: nextLists
      visible: listStrip.overflowing
      anchors.right: listControls.left
      anchors.rightMargin: Style.space(10)
      anchors.top: parent.top
      stocks: table.stocks
      text: "›"
      active: !listStrip.atXEnd
      onClicked: listStrip.page(1)
    }

    Row {
      id: listControls
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(4)

      Chip {
        anchors.verticalCenter: parent.verticalCenter
        stocks: table.stocks
        text: "+ List"
        onClicked: table.stocks.addWatchlist()
      }

      TextField {
        id: listNameField
        width: Style.space(130)
        text: table.stocks.activeList.name
        placeholderText: "List name ⏎"
        foreground: table.stocks.barForeground
        font.family: table.stocks.fontFamily
        font.pixelSize: Style.font.caption
        verticalPadding: Style.space(2)
        onActiveFocusChanged: table.stocks.editing = activeFocus
        onAccepted: {
          table.stocks.renameActiveWatchlist(text)
          table.stocks.releaseInput()
        }
        Keys.onEscapePressed: {
          text = table.stocks.activeList.name
          table.stocks.releaseInput()
        }
      }

      Chip {
        anchors.verticalCenter: parent.verticalCenter
        visible: table.stocks.watchlists.length > 1
        stocks: table.stocks
        text: "Delete list"
        onClicked: table.stocks.deleteActiveWatchlist()
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

  // ---- One row per symbol, scrolling under the fixed column headers. At
  //      least a few rows stay visible however little room is left.
  Flickable {
    id: rowsArea
    readonly property bool scrolling: contentHeight > height + 1
    width: parent.width
    height: Math.min(rowsColumn.implicitHeight,
      Math.max(table.rowHeight * 4, table.maxHeight - table.chromeHeight))
    contentWidth: width
    contentHeight: rowsColumn.implicitHeight
    clip: true
    interactive: scrolling
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: rowsArea.scrolling ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }

    Column {
      id: rowsColumn
      width: rowsArea.width - (rowsArea.scrolling ? Style.space(10) : 0)
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
          readonly property bool hovered: rowMouse.containsMouse || removeMouse.containsMouse || editMouse.containsMouse

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
            Row {
              width: table.w.remove
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)
              opacity: row.hovered ? 1 : 0

              Text {
                text: "✎"
                color: editMouse.containsMouse ? table.stocks.barForeground : table.stocks.mutedForeground
                font.family: table.stocks.fontFamily
                font.pixelSize: Style.font.body

                MouseArea {
                  id: editMouse
                  anchors.fill: parent
                  anchors.margins: -Style.space(3)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: table.editSymbol(row.q.symbol)
                }
              }

              Text {
                text: "×"
                color: removeMouse.containsMouse ? table.stocks.urgentForeground : table.stocks.mutedForeground
                font.family: table.stocks.fontFamily
                font.pixelSize: Style.font.body

                MouseArea {
                  id: removeMouse
                  anchors.fill: parent
                  anchors.margins: -Style.space(3)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: table.stocks.removeSymbol(row.q.symbol)
                }
              }
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

  // ---- Add symbols ("tsm, TW:2330" works) or replace the one being edited.
  Item {
    width: parent.width
    height: addField.implicitHeight

    TextField {
      id: addField
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      width: Style.space(260)
      placeholderText: table.stocks.editingIndex >= 0
        ? "Replace " + table.stocks.symbols[table.stocks.editingIndex] + " ⏎"
        : "Add symbols, e.g. TW:2330 ⏎"
      foreground: table.stocks.barForeground
      font.family: table.stocks.fontFamily
      font.pixelSize: Style.font.bodySmall
      verticalPadding: Style.spacing.controlPaddingY
      onActiveFocusChanged: table.stocks.editing = activeFocus
      onAccepted: {
        table.stocks.submitSymbols(text)
        text = ""
      }
      Keys.onEscapePressed: {
        text = ""
        table.stocks.editingIndex = -1
        table.stocks.releaseInput()
      }
    }

    Text {
      anchors.left: addField.right
      anchors.leftMargin: Style.space(10)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: "Click a row (or j/k + Enter) for chart & agent · hover a row: ✎ edit, × remove"
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
        onClicked: syncRow.sync.create(table.stocks.watchlists)
      }
    }
  }
}
