const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("fs")
const path = require("path")
const Model = require("../Model.js")

const root = path.join(__dirname, "..")
const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8")
const table = fs.readFileSync(path.join(root, "QuoteTable.qml"), "utf8")
const detail = fs.readFileSync(path.join(root, "DetailView.qml"), "utf8")

test("text fields exist only on the open page", () => {
  assert.equal(Model.listPageLive(false, "list"), false)
  assert.equal(Model.listPageLive(false, "detail"), false)
  assert.equal(Model.detailPageLive(false, "detail"), false)
  assert.equal(Model.listPageLive(true, "list"), true)
  assert.equal(Model.detailPageLive(true, "list"), false)
  assert.equal(Model.detailPageLive(true, "detail"), true)
  assert.equal(Model.listPageLive(true, "detail"), false)
  assert.equal(Model.settingsFieldLive(true, "list", true), false)
  assert.equal(Model.settingsFieldLive(true, "settings", true), true)
  assert.equal(Model.settingsFieldLive(true, "detail", true), false)
  assert.equal(Model.settingsFieldLive(false, "settings", true), false)
  assert.equal(Model.listPageLive("true", "list"), false)
  assert.equal(Model.detailPageLive(1, "detail"), false)
})

test("panel loads each page's text fields only while that page is open", () => {
  assert.match(panel, /active:\s*Model\.listPageLive\(root\.opened,\s*root\.view\)/)
  assert.match(panel, /active:\s*Model\.detailPageLive\(root\.opened,\s*root\.view\)/)
  assert.equal(panel.includes("TextField"), false)
  assert.doesNotMatch(panel, /visible:\s*root\.view/)

  const tableAt = panel.indexOf("QuoteTable {")
  const detailAt = panel.indexOf("DetailView {")
  assert.ok(tableAt > panel.indexOf("id: quoteTablePage"))
  assert.ok(tableAt < panel.indexOf("id: detailPage"))
  assert.ok(detailAt > panel.indexOf("id: detailPage"))
  assert.equal(panel.match(/QuoteTable\s*\{/g).length, 1)
  assert.equal(panel.match(/DetailView\s*\{/g).length, 1)

  const tableLoader = panel.indexOf("id: tableLoader")
  const detailLoader = panel.indexOf("id: detailLoader")
  assert.ok(panel.slice(tableLoader, tableLoader + 400).includes("sourceComponent: quoteTablePage"))
  assert.ok(panel.slice(detailLoader, detailLoader + 400).includes("sourceComponent: detailPage"))
})

test("imported and gist list names stay literal, including markup and CJK", () => {
  const name = '台積電 <img src="http://127.0.0.1/secret.png" alt="x"> 觀察 A&B'
  const imported = Model.parseWatchlistsDefinition(JSON.stringify({
    version: 1,
    watchlists: [{ name: name, symbols: ["tw2330"] }]
  }))
  assert.equal(imported.watchlists[0].name, name)
  assert.deepEqual(imported.watchlists[0].symbols, ["2330.TW"])
  const synced = Model.parseWatchlistsDefinition(Model.serializeWatchlists(imported.watchlists))
  assert.equal(synced.watchlists[0].name, name)
  const symbolsOnly = Model.parseWatchlistsDefinition(JSON.stringify({
    name: name,
    symbols: ["2330.TW"]
  }))
  assert.equal(symbolsOnly.watchlists[0].name, name)
})

test("external labels are plain text, not AutoText", () => {
  const chip = fs.readFileSync(path.join(root, "Chip.qml"), "utf8")
  const bar = fs.readFileSync(path.join(root, "BarWidget.qml"), "utf8")
  assert.match(chip, /textFormat:\s*Text\.PlainText/)
  assert.match(table, /component Cell: Text \{[^}]*textFormat:\s*Text\.PlainText/)
  assert.match(detail, /textFormat:\s*Text\.PlainText[\s\S]{0,80}detail\.quote\.name/)
  assert.match(bar, /textFormat:\s*Text\.PlainText/)
  assert.match(panel, /active:\s*Model\.listPageLive\(root\.opened,\s*root\.view\)/)
})

test("settings text field is created only on the settings page", () => {
  const settings = fs.readFileSync(path.join(root, "SettingsView.qml"), "utf8")
  assert.equal((table.match(/TextField\s*\{/g) || []).length, 2)
  assert.equal(settings.match(/TextField\s*\{/g).length, 2)
  const gate = settings.indexOf("Model.settingsFieldLive(page.stocks.opened, page.stocks.view, true)")
  assert.ok(gate > 0)
  const field = settings.indexOf("id: refreshField")
  assert.ok(field > gate)
  const customGate = settings.indexOf("Model.customFontFieldLive(page.stocks.opened, page.stocks.view, page.stocks.customFontOpen)")
  assert.ok(customGate > 0)
  assert.ok(settings.indexOf("id: customFontField") > customGate)
  assert.match(panel, /active:\s*Model\.settingsPageLive\(root\.opened,\s*root\.view\)/)
  assert.equal(Model.settingsPageLive(true, "settings"), true)
  assert.equal(Model.settingsPageLive(true, "list"), false)
  assert.equal(Model.settingsFieldLive(true, "settings", false), true)
  assert.equal(Model.settingsFieldLive(true, "list", true), false)
  assert.equal(Model.settingsFieldLive(false, "settings", true), false)
})
