// Regression for marketplace review 6789444920 (export-permissions): the
// export must fail closed when it cannot make a private file, and must never
// write into a pre-existing target owned by someone else.
const test = require("node:test")
const assert = require("node:assert/strict")
const { spawnSync } = require("node:child_process")
const fs = require("node:fs"), os = require("node:os"), path = require("node:path")
const Model = require("../Model.js")

const BODY = JSON.stringify({ version: 1, watchlists: [{ name: "Private", symbols: ["AAPL"] }] }) + "\n"
const realStat = spawnSync("sh", ["-c", "command -v stat"]).stdout.toString().trim()
const realChmod = spawnSync("sh", ["-c", "command -v chmod"]).stdout.toString().trim()
const mode = (p) => fs.lstatSync(p).mode & 0o777

function setup() {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), "stock-hq-export-"))
  const dir = path.join(base, "shared")
  const bin = path.join(base, "bin")
  fs.mkdirSync(dir); fs.mkdirSync(bin)
  fs.chmodSync(dir, 0o777)  // shared, non-sticky folder from the review
  return { base, dir, bin, target: path.join(dir, "omarchy-stock-hq-2026-11-11.json") }
}

function shim(bin, name, script) {
  fs.writeFileSync(path.join(bin, name), "#!/bin/sh\n" + script + "\n", { mode: 0o755 })
}

function exportTo(ctx, env) {
  const spec = Model.exportCommand(ctx.target, BODY)
  const r = spawnSync(spec.command[0], spec.command.slice(1), {
    input: spec.stdin, env: Object.assign({}, process.env, { PATH: ctx.bin + ":" + process.env.PATH }, env || {})
  })
  return Model.parseCommandResult(r.stdout.toString())
}

test("export writes a private 0600 file and replaces only our own target", () => {
  const ctx = setup()
  let r = exportTo(ctx)
  assert.deepEqual(r, { code: 0, output: ctx.target })
  assert.equal(fs.readFileSync(ctx.target, "utf8"), BODY)
  assert.equal(mode(ctx.target), 0o600)
  fs.chmodSync(ctx.target, 0o666)  // our own earlier, too-wide export
  r = exportTo(ctx)
  assert.deepEqual(r, { code: 0, output: ctx.target })
  assert.equal(mode(ctx.target), 0o600)
  assert.deepEqual(fs.readdirSync(ctx.dir), [path.basename(ctx.target)])
  fs.rmSync(ctx.base, { recursive: true, force: true })
})

test("a foreign 0666 target is left untouched and a fresh unique name is used", () => {
  const ctx = setup()
  fs.writeFileSync(ctx.target, "attacker", { mode: 0o666 }); fs.chmodSync(ctx.target, 0o666)
  // Reports another uid as the target's owner (unprivileged test runs cannot
  // create a file owned by someone else); everything else is the real stat.
  shim(ctx.bin, "stat", 'for a; do last=$a; done\n' +
    'if [ "$1" = -c ] && [ "$2" = %u ] && [ "$last" = "$STOCKHQ_FOREIGN" ]; then echo 4242; exit 0; fi\n' +
    'exec ' + realStat + ' "$@"')
  const r = exportTo(ctx, { STOCKHQ_FOREIGN: ctx.target })
  assert.equal(r.code, 0)
  assert.notEqual(r.output, ctx.target)
  assert.match(path.basename(r.output), /^omarchy-stock-hq-2026-11-11-[A-Za-z0-9]{6}\.json$/)
  assert.equal(fs.readFileSync(ctx.target, "utf8"), "attacker")   // never written
  assert.equal(mode(ctx.target), 0o666)
  assert.equal(fs.readFileSync(r.output, "utf8"), BODY)
  assert.equal(mode(r.output), 0o600)
  fs.rmSync(ctx.base, { recursive: true, force: true })
})

test("a symlink target is not followed or reused (plus a real foreign-owned 0666 target when run as root)", () => {
  const ctx = setup()
  const elsewhere = path.join(ctx.base, "elsewhere.json")
  fs.writeFileSync(elsewhere, "outside")
  fs.symlinkSync(elsewhere, ctx.target)
  let r = exportTo(ctx)
  assert.equal(r.code, 0)
  assert.notEqual(r.output, ctx.target)
  assert.equal(fs.readFileSync(elsewhere, "utf8"), "outside")
  assert.ok(fs.lstatSync(ctx.target).isSymbolicLink())
  assert.equal(mode(r.output), 0o600)
  if (process.getuid && process.getuid() === 0) {
    fs.rmSync(ctx.target)
    fs.writeFileSync(ctx.target, "attacker"); fs.chmodSync(ctx.target, 0o666); fs.chownSync(ctx.target, 65534, 65534)
    r = exportTo(ctx)
    assert.equal(r.code, 0)
    assert.notEqual(r.output, ctx.target)
    assert.equal(fs.readFileSync(ctx.target, "utf8"), "attacker")
  }
  fs.rmSync(ctx.base, { recursive: true, force: true })
})

test("chmod failure fails closed: no export file is left behind", () => {
  const ctx = setup()
  shim(ctx.bin, "chmod", "echo 'chmod: Operation not permitted' >&2; exit 1")
  const r = exportTo(ctx)
  assert.notEqual(r.code, 0)
  assert.match(r.output, /chmod 600 failed/)
  assert.deepEqual(fs.readdirSync(ctx.dir), [])
  fs.rmSync(ctx.base, { recursive: true, force: true })
})

test("a chmod that reports success but leaves the file readable fails closed", () => {
  const ctx = setup()
  // Like a filesystem that ignores modes: chmod exits 0, the mode stays wide.
  shim(ctx.bin, "chmod", 'for a; do last=$a; done\nexec ' + realChmod + ' 644 -- "$last"')
  fs.writeFileSync(ctx.target, "old", { mode: 0o600 })
  const r = exportTo(ctx)
  assert.notEqual(r.code, 0)
  assert.match(r.output, /private/)
  assert.equal(fs.readFileSync(ctx.target, "utf8"), "old")
  assert.deepEqual(fs.readdirSync(ctx.dir), [path.basename(ctx.target)])
  fs.rmSync(ctx.base, { recursive: true, force: true })
})

test("a missing folder fails and the payload never reaches argv", () => {
  const ctx = setup()
  ctx.target = path.join(ctx.dir, "nope", "x.json")
  const r = exportTo(ctx)
  assert.notEqual(r.code, 0)
  assert.match(r.output, /folder not found/)
  const spec = Model.exportCommand("/tmp/x.json", BODY)
  assert.ok(!spec.command.join("\u0000").includes("AAPL"))
  fs.rmSync(ctx.base, { recursive: true, force: true })
})
