const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("fs")
const path = require("path")
const { spawnSync } = require("child_process")

const root = path.join(__dirname, "..")
const qmllint = "/usr/lib/qt6/bin/qmllint"

test("qmllint catches missing imports and unknown Loader signals", () => {
  assert.ok(fs.existsSync(qmllint), "qmllint is not installed")
  const settings = fs.readFileSync(path.join(root, "SettingsView.qml"), "utf8")
  const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
  assert.match(settings, /import qs\.Ui/)
  assert.doesNotMatch(panel, /onUnloaded\b/)
  assert.doesNotMatch(panel, /height:\s*item\s*\?\s*item\.height/)

  const run = spawnSync(qmllint, [
    "-I", path.join(__dirname, "stubs"),
    path.join(root, "SettingsView.qml"),
    path.join(root, "Panel.qml"),
    path.join(root, "QuoteTable.qml"),
    path.join(root, "DetailView.qml"),
    path.join(root, "Chip.qml")
  ], { encoding: "utf8" })
  const out = (run.stdout || "") + "\n" + (run.stderr || "")
  const bad = out.split("\n").filter((line) =>
    /non-existent property|does not exist|unavailable|is not a type|Cannot assign/.test(line))
  assert.deepEqual(bad, [], out)
})
