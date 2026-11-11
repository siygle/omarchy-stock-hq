const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("fs")
const os = require("os")
const path = require("path")
const { spawnSync } = require("child_process")

const root = path.join(__dirname, "..")
const qmltestrunner = "/usr/lib/qt6/bin/qmltestrunner"

test("offscreen shots of settings and both font sizes", { skip: !fs.existsSync(qmltestrunner) && "qmltestrunner not installed" }, () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "stock-hq-shot-"))
  const shotDir = process.env.STOCKHQ_SHOT_DIR || path.join(dir, "shots")
  fs.mkdirSync(shotDir, { recursive: true })
  for (const name of ["SettingsView.qml", "QuoteTable.qml", "Chip.qml", "SeriesCanvas.qml", "RangeBar.qml", "Model.js"]) {
    let text = fs.readFileSync(path.join(root, name), "utf8")
    text = text.replace(/^([ \t]+)foreground:/gm, "$1color:")
    text = text.replace(/^([ \t]+)verticalPadding:.*\n/gm, "")
    fs.writeFileSync(path.join(dir, name), text)
  }
  let shot = fs.readFileSync(path.join(__dirname, "preview-shot.qml"), "utf8")
  shot = shot.replace('import "../Model.js" as Model', 'import "Model.js" as Model')
  shot = shot.replace('property string shotDir: "/opt/cursor/artifacts"', "property string shotDir: " + JSON.stringify(shotDir))
  fs.writeFileSync(path.join(dir, "preview-shot.qml"), shot)
  const run = spawnSync(qmltestrunner, [
    "-import", path.join(__dirname, "stubs"),
    "-input", path.join(dir, "preview-shot.qml"),
    "-o", "-,txt"
  ], {
    env: Object.assign({}, process.env, {
      QT_QPA_PLATFORM: "offscreen",
      XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR || "/tmp/runtime-ubuntu"
    }),
    encoding: "utf8",
    timeout: 20000
  })
  assert.equal(run.status, 0, (run.stdout || "") + "\n" + (run.stderr || ""))
  for (const file of ["settings-view.png", "panel-font-11.png", "panel-font-14.png"]) {
    const full = path.join(shotDir, file)
    assert.ok(fs.existsSync(full), full)
    assert.ok(fs.statSync(full).size > 2000, file + " looks empty")
  }
})
