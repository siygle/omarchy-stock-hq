import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Runs the configured agent CLI on one symbol at a time in the background,
// streams its stdout into `results[SYMBOL].output`, and keeps the latest
// answer per symbol under ~/.cache/omarchy-stocks/agent/<SYMBOL>.md so it
// survives a shell restart.
Item {
  id: runner
  visible: false

  property var command: Model.DEFAULT_AGENT_COMMAND
  readonly property string cacheDir: {
    var base = Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
    return base + "/omarchy-stocks/agent"
  }

  // SYMBOL -> { status: running|done|error|cancelled|saved, output, prompt, at, exitCode }
  property var results: ({})
  property string runningSymbol: ""
  property string readerSymbol: ""
  property bool cancelRequested: false
  property double now: Date.now()
  readonly property bool running: agentProc.running

  function setResult(symbol, patch) {
    var next = {}
    for (var k in results) next[k] = results[k]
    var entry = {}
    var prev = results[symbol] || {}
    for (var p in prev) entry[p] = prev[p]
    for (var q in patch) entry[q] = patch[q]
    next[symbol] = entry
    results = next
  }

  function resultFor(symbol) {
    return symbol ? (results[symbol] || null) : null
  }

  function elapsedFor(symbol) {
    var r = resultFor(symbol)
    return r && r.at ? Model.formatElapsed((now - r.at) / 1000) : ""
  }

  // Returns false when another run is in flight.
  function run(quote, promptName, template) {
    if (!quote || agentProc.running) return false
    var symbol = quote.symbol
    var prompt = Model.fillPrompt(template, quote)
    runningSymbol = symbol
    cancelRequested = false
    now = Date.now()
    setResult(symbol, { status: "running", output: "", prompt: promptName, at: now, exitCode: null })
    agentProc.command = ["sh", "-c", "mkdir -p \"$1\" && cd \"$1\" && shift && exec \"$@\" </dev/null 2>&1", "sh", cacheDir]
      .concat(Model.agentArgv(command, prompt))
    agentProc.running = true
    return true
  }

  function cancel() {
    if (!agentProc.running) return
    cancelRequested = true
    agentProc.running = false
  }

  // Loads the saved answer for `symbol` unless this session already has one.
  function loadCached(symbol) {
    if (!symbol || results[symbol]) return
    readerSymbol = symbol
    reader.path = cacheDir + "/" + Model.agentFileName(symbol)
  }

  function finish(exitCode) {
    var symbol = runningSymbol
    if (symbol === "") return
    var r = results[symbol] || {}
    var status = cancelRequested ? "cancelled" : (exitCode === 0 ? "done" : "error")
    setResult(symbol, { status: status, exitCode: exitCode })
    if (status === "done" && String(r.output || "").replace(/\s+/g, "") !== "") {
      writer.path = cacheDir + "/" + Model.agentFileName(symbol)
      writer.setText(Model.agentFileText({ prompt: r.prompt, at: r.at }, r.output))
    }
    runningSymbol = ""
  }

  Process {
    id: agentProc
    stdout: SplitParser {
      onRead: function(line) {
        var r = runner.results[runner.runningSymbol]
        if (!r) return
        runner.setResult(runner.runningSymbol, { output: (r.output ? r.output + "\n" : "") + line })
      }
    }
    // Let the last buffered lines land before the run is closed out.
    onExited: function(exitCode) { finishTimer.exitCode = exitCode; finishTimer.restart() }
  }

  Timer {
    id: finishTimer
    property int exitCode: 0
    interval: 150
    onTriggered: runner.finish(exitCode)
  }

  Timer {
    interval: 1000
    repeat: true
    running: agentProc.running
    onTriggered: runner.now = Date.now()
  }

  FileView {
    id: reader
    printErrors: false
    onLoaded: {
      var symbol = runner.readerSymbol
      if (symbol === "" || runner.results[symbol]) return
      var parsed = Model.parseAgentFile(text())
      runner.setResult(symbol, { status: "saved", output: parsed.output, prompt: parsed.prompt, at: parsed.at, exitCode: 0 })
    }
  }

  FileView {
    id: writer
    printErrors: false
  }
}
