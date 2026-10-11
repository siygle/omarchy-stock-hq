import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Two-way sync of the watchlists definition (same JSON shape as
// watchlists.json) with one file in a GitHub gist, through the signed-in `gh`
// CLI. The gist is the source of truth: a pull that differs from what was last
// synced (an edit on gist.github.com) replaces the local lists; local lists
// that drifted from the last sync (panel edits, an import, a hand-edited
// watchlists.json) are pushed.
Item {
  id: sync
  visible: false

  property string gistId: ""
  property string gistFile: Model.DEFAULT_GIST_FILE
  property var watchlists: []

  // "off" | "pulling" | "pushing" | "creating" | "ok" | "error"
  property string status: gistId === "" ? "off" : "idle"
  property string error: ""
  property var lastSynced: null
  // Model.watchlistsKey() as of the last successful pull or push.
  property string lastSyncedKey: ""
  property var pushingLists: []
  property bool pushAgain: false

  readonly property bool configured: gistId !== ""
  readonly property bool busy: pullProc.running || pushProc.running || createProc.running

  signal remoteChanged(var watchlists)
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
    pushingLists = list || watchlists
    status = "pushing"
    pushProc.command = Model.gistPushCommand(gistId, gistFile, pushingLists)
    pushProc.running = true
  }

  function create(list) {
    if (busy) return
    status = "creating"
    error = ""
    createProc.command = Model.gistCreateCommand(gistFile, list || watchlists)
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
    var remote = Model.parseWatchlistsDefinition(result.output)
    var localKey = Model.watchlistsKey(watchlists)
    // An empty or missing file: seed it from the local lists.
    if (!remote) {
      status = "idle"
      return push(watchlists)
    }
    var remoteKey = Model.watchlistsKey(remote.watchlists)
    if (remoteKey !== lastSyncedKey && remoteKey !== localKey) {
      succeed(remoteKey)
      remoteChanged(remote.watchlists)
    } else if (remoteKey === lastSyncedKey && localKey !== lastSyncedKey) {
      status = "idle"
      push(watchlists)
    } else {
      succeed(remoteKey)
    }
    if (pushAgain) {
      pushAgain = false
      push(watchlists)
    }
  }

  function handlePush(text) {
    var result = Model.parseCommandResult(text)
    if (result.code !== 0) fail(result)
    else succeed(Model.watchlistsKey(pushingLists))
    if (pushAgain) {
      pushAgain = false
      if (Model.watchlistsKey(watchlists) !== lastSyncedKey) Qt.callLater(function() { sync.push(sync.watchlists) })
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
