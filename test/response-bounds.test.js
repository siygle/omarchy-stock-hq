// Regression for marketplace review 6789373295 (market-response-bounds):
// provider responses are capped while curl runs, the whole batch is bounded
// in time, stopping it leaves no child behind, and parsed rows are bounded.
const test = require("node:test")
const assert = require("node:assert/strict")
const http = require("node:http")
const { spawn, spawnSync } = require("node:child_process")
const Model = require("../Model.js")

function listen(handler) {
  return new Promise((resolve) => {
    const server = http.createServer(handler)
    server.listen(0, "127.0.0.1", () => resolve(server))
  })
}

// curlCommand's real command line, pointed at a local URL instead of Yahoo.
function localSpec(url, count, marker) {
  const spec = Model.curlCommand(Array.from({ length: count }, (_, i) => "S" + i), marker, "1d")
  const config = Array.from({ length: count }, () => "url = " + JSON.stringify(url) + "\n").join("")
  const command = spec.command.slice()
  command[command.length - 4] = String(Buffer.byteLength(config))
  return { command, stdin: config, limit: spec.limit }
}

function run(spec) {
  return new Promise((resolve) => {
    const child = spawn(spec.command[0], spec.command.slice(1), { stdio: ["pipe", "pipe", "pipe"] })
    const chunks = []
    child.stdout.on("data", (c) => chunks.push(c))
    child.on("close", (code) => resolve({ code, stdout: Buffer.concat(chunks) }))
    child.stdin.end(spec.stdin)
  })
}

test("curlCommand: byte cap, per-response cap and batch deadline are in the command", () => {
  const spec = Model.curlCommand(["AAPL", "MSFT"], "ua")
  assert.deepEqual(spec.command.slice(0, 4), ["timeout", "-k", "2", String(Model.FETCH_BATCH_SECONDS)])
  assert.match(spec.command[6], /--max-filesize "\$3"/)
  assert.match(spec.command[6], /\| head -c "\$4"$/)
  assert.equal(spec.limit, 2 * Model.MAX_RESPONSE_BYTES_PER_SYMBOL)
  assert.equal(spec.command[spec.command.length - 1], String(spec.limit + 1))
  assert.equal(Model.responseLimit(10000), Model.MAX_RESPONSE_BYTES)
})

test("oversized response without Content-Length stops at the first excess byte (real curl)", async () => {
  let sent = 0
  let closed = false
  const server = await listen((req, res) => {
    res.writeHead(200, { "Content-Type": "application/json" })  // chunked, no Content-Length
    const block = Buffer.alloc(64 * 1024, 0x61)
    const pump = () => {
      while (!res.destroyed && sent < 512 * 1024 * 1024) {
        sent += block.length
        if (!res.write(block)) return res.once("drain", pump)
      }
    }
    res.on("close", () => { closed = true })
    pump()
  })
  const url = "http://127.0.0.1:" + server.address().port + "/chart"
  const spec = localSpec(url, 1, "stock-hq-bounds-test")
  const started = Date.now()
  const r = await run(spec)
  assert.equal(r.stdout.length, spec.limit + 1)          // exactly one byte past the limit
  assert.equal(Model.responseTooLarge(r.stdout.toString(), spec.limit), true)
  assert.ok(Date.now() - started < 5000, "stopped long before the 10 s transfer timeout")
  await new Promise((resolve) => setTimeout(resolve, 100))
  assert.ok(closed, "server saw the transfer aborted")
  assert.ok(sent < 64 * 1024 * 1024, "producer stopped early, sent " + sent)
  server.close()
})

test("a response announcing more than the per-symbol limit is refused (real curl)", async () => {
  const body = Buffer.alloc(Model.MAX_RESPONSE_BYTES_PER_SYMBOL + 10, 0x61)
  const server = await listen((req, res) => {
    res.writeHead(200, { "Content-Length": body.length })
    res.end(body)
  })
  const spec = localSpec("http://127.0.0.1:" + server.address().port + "/chart", 2, "stock-hq-bounds-test")
  const r = await run(spec)
  assert.ok(r.stdout.length < 16, "nothing but the -w newlines, got " + r.stdout.length)
  assert.equal(Model.responseTooLarge(r.stdout.toString(), spec.limit), false)
  server.close()
})

test("stopping the batch kills sh, head and curl (process group)", async () => {
  const server = await listen(() => {})  // accepts, never answers
  const marker = "stock-hq-cleanup-" + process.pid
  const spec = localSpec("http://127.0.0.1:" + server.address().port + "/chart", 1, marker)
  const child = spawn(spec.command[0], spec.command.slice(1), { stdio: ["pipe", "ignore", "ignore"] })
  child.stdin.end(spec.stdin)
  await new Promise((resolve) => setTimeout(resolve, 500))
  assert.equal(spawnSync("pgrep", ["-f", marker]).status, 0, "curl is running")
  const exited = new Promise((resolve) => child.on("close", resolve))
  child.kill("SIGTERM")  // what Quickshell does when the Process stops
  await exited
  await new Promise((resolve) => setTimeout(resolve, 300))
  assert.equal(spawnSync("pgrep", ["-f", marker]).status, 1, "no child left behind")
  server.close()
  server.closeAllConnections()
})

test("parsed provider rows and strings are bounded before reaching QML", () => {
  const n = Model.MAX_SERIES_POINTS + 1
  const result = (rows) => ({
    meta: { symbol: "AAPL", regularMarketPrice: 1, previousClose: 1, shortName: "N".repeat(5000), currency: "USD".repeat(100) },
    timestamp: Array.from({ length: rows }, (_, i) => i),
    indicators: { quote: [{ close: Array.from({ length: rows }, () => 1), open: Array.from({ length: rows }, () => 1) }] }
  })
  const big = Model.parseChartResponse(JSON.stringify({ chart: { result: [result(n)] } }))
  assert.deepEqual(big.series, [])
  assert.deepEqual(big.candles, [])
  assert.ok(big.name.length <= 128 && big.currency.length <= 8)
  const ok = Model.parseChartResponse(JSON.stringify({ chart: { result: [result(Model.MAX_SERIES_POINTS)] } }))
  assert.equal(ok.series.length, Model.MAX_SERIES_POINTS)
  // Forged array-likes from the provider are not iterated.
  const forged = Model.parseChartResponse(JSON.stringify({ chart: { result: [{ meta: { symbol: "A", regularMarketPrice: 1 },
    timestamp: { length: 1000000000 }, indicators: { quote: { length: 1000000000 } } }] } }))
  assert.deepEqual(forged.series, [])
  // Extra lines past one per symbol are not parsed.
  const lines = Array.from({ length: 50 }, () => "{}").join("\n")
  assert.equal(Model.parseQuoteLines(lines, ["A"]).length, 1)
})
