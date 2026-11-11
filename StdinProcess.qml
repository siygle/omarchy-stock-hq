import QtQuick
import Quickshell.Io

// A Process whose sensitive input (watchlist JSON, symbol URLs, agent prompts)
// goes to stdin instead of argv: command lines are world-readable through
// ps / /proc. start() takes a Model `{ command, stdin }` spec; the payload is
// written once the process is up, then stdin is closed so the child sees EOF
// even if it reads until end of input.
Process {
  property string payload: ""
  // Byte ceiling the spec's command enforces on stdout (0 = none); handlers
  // drop output longer than this as a whole.
  property real responseLimit: 0

  function start(spec) {
    payload = spec.stdin
    responseLimit = spec.limit || 0
    command = spec.command
    stdinEnabled = true
    running = true
  }

  onStarted: {
    write(payload)
    payload = ""
    stdinEnabled = false
  }
}
