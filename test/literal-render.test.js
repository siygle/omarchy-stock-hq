const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("fs")
const os = require("os")
const path = require("path")
const { spawn, spawnSync } = require("child_process")

const PNG = Buffer.from(
  "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6300010000000500010d0a2db40000000049454e44ae426082",
  "hex"
)

test("plain text renders a markup-shaped watchlist name and does not fetch its image", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "stock-hq-literal-"))
  const hitLog = path.join(dir, "hits.log")
  const portFile = path.join(dir, "port")
  const serverPath = path.join(dir, "server.js")
  fs.writeFileSync(serverPath, `
const http = require("http")
const fs = require("fs")
const png = Buffer.from(${JSON.stringify(PNG.toString("base64"))}, "base64")
const server = http.createServer((req, res) => {
  fs.appendFileSync(${JSON.stringify(hitLog)}, req.url + "\\n")
  res.writeHead(200, { "Content-Type": "image/png", "Content-Length": png.length })
  res.end(png)
})
server.listen(0, "127.0.0.1", () => {
  fs.writeFileSync(${JSON.stringify(portFile)}, String(server.address().port))
})
`)
  const server = spawn(process.execPath, [serverPath], { stdio: "ignore" })
  const started = Date.now()
  while (!fs.existsSync(portFile)) {
    if (Date.now() - started > 3000) throw new Error("local image server did not start")
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 20)
  }
  const port = fs.readFileSync(portFile, "utf8").trim()
  const url = "http://127.0.0.1:" + port + "/chip.png"
  const name = '台積電 <img src="' + url + '" alt="chip"> 觀察 A&B'
  const qmlPath = path.join(dir, "literal.qml")
  fs.writeFileSync(qmlPath, `
import QtQuick
import QtTest

TestCase {
  name: "LiteralName"
  when: windowShown
  visible: true
  width: 640
  height: 120

  property string labelText: ${JSON.stringify(name)}

  Text {
    id: literal
    textFormat: Text.PlainText
    text: labelText
    font.pixelSize: 14
  }

  function test_literalNameDoesNotLoadAnImage() {
    wait(400)
    compare(literal.text, labelText)
    verify(literal.implicitWidth > 0)
    verify(literal.text.indexOf("台積電") >= 0)
    verify(literal.text.indexOf("<img") >= 0)
    verify(literal.text.indexOf("觀察") >= 0)
    verify(literal.text.indexOf("A&B") >= 0)
  }
}
`)
  const run = spawnSync("/usr/lib/qt6/bin/qmltestrunner", ["-input", qmlPath, "-o", "-,txt"], {
    env: Object.assign({}, process.env, {
      QT_QPA_PLATFORM: "offscreen",
      XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR || "/tmp/runtime-ubuntu"
    }),
    encoding: "utf8",
    timeout: 20000
  })
  server.kill()
  const hits = fs.existsSync(hitLog) ? fs.readFileSync(hitLog, "utf8") : ""
  assert.equal(run.status, 0, (run.stdout || "") + "\n" + (run.stderr || "") + "\n" + (run.error || ""))
  assert.equal(hits.includes("chip.png"), false, "image fetch log:\n" + hits)
})
