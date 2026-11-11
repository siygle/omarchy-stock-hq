import QtQuick
import QtQuick.Controls
import QtTest
import "../Model.js" as Model

// Offscreen stand-in for the panel. Loads the real SettingsView and QuoteTable
// against a fixed Omarchy-like palette and the font-size limits.
TestCase {
  id: shot
  name: "PreviewShot"
  when: windowShown
  visible: true
  width: 1000
  height: 1680

  property int saved: 0
  property string shotDir: "/opt/cursor/artifacts"

  QtObject {
    id: gist
    property bool configured: false
    property string status: "off"
    property string error: ""
    property var lastSynced: null
    property bool busy: false
    function create(lists) {}
  }

  function quote(symbol, name, price, prev, change) {
    return {
      symbol: symbol, name: name, price: price, prevClose: prev, change: change,
      changePct: change / prev, dayLow: price - 2, dayHigh: price + 1,
      week52Low: price * 0.7, week52High: price * 1.2, volume: 52000000,
      marketTime: 1762770000,
      series: [{ t: 1, c: prev }, { t: 2, c: price - 0.4 }, { t: 3, c: price }]
    }
  }

  function makeStocks(size, page) {
    var roles = Model.fontRoles(size)
    return {
      opened: true,
      view: page || "list",
      editing: false,
      fontFamily: "sans-serif",
      fontFamilySetting: "sans-serif",
      fontSize: size,
      fonts: roles,
      textColor: "#c0caf5",
      barForeground: "#c0caf5",
      mutedForeground: "#565f89",
      upColor: "#9ece6a",
      downColor: "#f7768e",
      urgentForeground: "#f7768e",
      accentColor: "#7aa2f7",
      surfaceColor: "#1a1b26",
      hasTheme: true,
      themeStatus: "Tokyo Night",
      validCount: 2,
      summary: ({ up: 1, down: 1, avgPct: 0.12 }),
      displayCurrency: "",
      lastUpdated: new Date(1762770000000),
      loading: false,
      cursorIndex: 0,
      sortKey: "",
      sortDesc: true,
      editingIndex: -1,
      fetchError: "",
      fileDialogMessage: "",
      watchlistsPath: "/home/user/.local/share/omarchy-stock-hq/watchlists.json",
      refreshMinutes: 5,
      activeWatchlist: 0,
      activeList: ({ name: "Main", symbols: ["AAPL", "2330.TW"] }),
      symbols: ["AAPL", "2330.TW"],
      watchlists: [
        { name: "Main", symbols: ["AAPL", "2330.TW"] },
        { name: "台灣", symbols: ["2330.TW"] }
      ],
      tableQuotes: [
        quote("AAPL", "Apple Inc.", 189.2, 188.0, 1.2),
        quote("2330.TW", "台積電", 980, 1002, -22)
      ],
      gistSync: gist,
      trendColor: function(q) { return q.change < 0 ? "#f7768e" : "#9ece6a" },
      directionColor: function(series) { return "#9ece6a" },
      showSettings: function() {},
      showList: function() {},
      selectCurrency: function(d) {},
      refresh: function() {},
      selectWatchlist: function(i) {},
      addWatchlist: function() {},
      renameActiveWatchlist: function(n) {},
      releaseInput: function() {},
      deleteActiveWatchlist: function() {},
      setSort: function(k, d) {},
      cycleSort: function(k) {},
      showDetail: function(s) {},
      beginEditSymbol: function(s) {},
      submitSymbols: function(t) {},
      removeSymbol: function(s) {},
      selectFontFamily: function(f) {},
      selectFontSize: function(n) {},
      saveRefreshMinutes: function(t) {},
      requestExportWatchlists: function() {},
      requestImportWatchlists: function() {},
      openWatchlistsFile: function() {},
      syncNow: function() {},
      openGist: function() {}
    }
  }

  property var smallStocks: makeStocks(11)
  property var largeStocks: makeStocks(14)
  property var settingsStocks: makeStocks(13, "settings")

  Rectangle {
    id: settingsCard
    color: "#1a1b26"
    width: 720
    height: 340
    SettingsView {
      id: settingsPage
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 8
      stocks: settingsStocks
    }
  }

  Rectangle {
    id: smallCard
    y: 360
    color: "#1a1b26"
    width: 980
    height: 280
    QuoteTable {
      id: smallTable
      width: parent.width
      stocks: smallStocks
      maxHeight: 260
    }
  }

  Rectangle {
    id: largeCard
    y: 660
    color: "#1a1b26"
    width: 980
    height: 320
    QuoteTable {
      id: largeTable
      width: parent.width
      stocks: largeStocks
      maxHeight: 300
    }
  }

  function save(item, file) {
    item.grabToImage(function(result) {
      if (result) result.saveToFile(shotDir + "/" + file)
      saved = saved + 1
    })
  }

  Loader {
    id: offlineLoader
    width: 980
    active: true
    sourceComponent: Component {
      QuoteTable {
        width: offlineLoader.width
        stocks: offlineStocks
        maxHeight: 360
      }
    }
  }

  property var offlineStocks: {
    var s = makeStocks(13)
    s.tableQuotes = [{ symbol: "AAPL", name: null, price: null, error: "No response", change: null, changePct: null }]
    s.validCount = 0
    s.summary = ({ up: 0, down: 0, avgPct: 0 })
    return s
  }

  function test_failedQuotesStillShowTheTable() {
    wait(50)
    verify(offlineLoader.item !== null)
    verify(offlineLoader.height > 80, "quote table collapsed to " + offlineLoader.height)
  }

  function test_writeShots() {
    settingsStocks.view = "settings"
    wait(100)
    save(settingsCard, "settings-view.png")
    save(smallCard, "panel-font-11.png")
    save(largeCard, "panel-font-14.png")
    tryCompare(shot, "saved", 3, 4000)
  }
}
