import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Two-way sync of the watchlist with one file in a GitHub gist, through the
// signed-in `gh` CLI. The gist is the source of truth: a pull that differs
// from what was last synced (an edit on gist.github.com) replaces the local
// list; a local list that drifted from the last sync (panel add/remove,
// `omarchy bar set`) is pushed.
Item {
  id: sync
  visible: false

  property string gistId: ""
  property string gistFile: Model.DEFAULT_GIST_FILE
  property var symbols: []

  // "off" | "pulling" | "pushing" | "creating" | "ok" | "error"
  property string status: gistId === "" ? "off" : "idle"
  property string error: ""
  property var lastSynced: null
  // Symbols (joined) as of the last successful pull or push.
  property string lastSyncedKey: ""
  property var pushingSymbols: []
  property bool pushAgain: false

  readonly property bool configured: gistId !== ""
  readonly property bool busy: pullProc.running || pushProc.running || createProc.running

  signal remoteChanged(var symbols)
  signal created(string id)

  onGistIdChanged: {
    lastSyncedKey = ""
    error = ""
    lastSynced = null
    status = gistId === "" ? "off" : "idle"
    if (gistId !== "") Qt.callLater(sync.pull)
  }

  function pull() {
    if (!configured || busy) return
    status = "pulling"
    pullProc.command = Model.gistPullCommand(gistId, gistFile)
    pullProc.running = true
  }

  function push(list) {
    if (!configured) return
    if (pushProc.running || pullProc.running) {
      pushAgain = true
      return
    }
    pushingSymbols = list || symbols
    status = "pushing"
    pushProc.command = Model.gistPushCommand(gistId, gistFile, pushingSymbols)
    pushProc.running = true
  }

  function create(list) {
    if (busy) return
    status = "creating"
    error = ""
    createProc.command = Model.gistCreateCommand(gistFile, list || symbols)
    createProc.running = true
  }

  function fail(result) {
    error = Model.commandError(result)
    status = "error"
  }

  function succeed(key) {
    lastSyncedKey = key
    lastSynced = new Date()
    error = ""
    status = "ok"
  }

  function handlePull(text) {
    var result = Model.parseCommandResult(text)
    if (result.code !== 0) return fail(result)
    var remote = Model.parseWatchlist(result.output)
    var localKey = symbols.join(",")
    // An empty or missing file: seed it from the local list.
    if (!remote.length) {
      status = "idle"
      return push(symbols)
    }
    var remoteKey = remote.join(",")
    if (remoteKey !== lastSyncedKey && remoteKey !== localKey) {
      succeed(remoteKey)
      remoteChanged(remote)
    } else if (remoteKey === lastSyncedKey && localKey !== lastSyncedKey) {
      status = "idle"
      push(symbols)
    } else {
      succeed(remoteKey)
    }
    if (pushAgain) {
      pushAgain = false
      push(symbols)
    }
  }

  function handlePush(text) {
    var result = Model.parseCommandResult(text)
    if (result.code !== 0) fail(result)
    else succeed(pushingSymbols.join(","))
    if (pushAgain) {
      pushAgain = false
      if (symbols.join(",") !== lastSyncedKey) Qt.callLater(function() { sync.push(sync.symbols) })
    }
  }

  function handleCreate(text) {
    var result = Model.parseCommandResult(text)
    if (result.code !== 0) return fail(result)
    var id = Model.normalizeGistId(result.output)
    if (id === "") {
      error = "Unexpected gh output"
      status = "error"
      return
    }
    created(id)
  }

  Process {
    id: pullProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: sync.handlePull(text)
    }
  }

  Process {
    id: pushProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: sync.handlePush(text)
    }
  }

  Process {
    id: createProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: sync.handleCreate(text)
    }
  }
}
