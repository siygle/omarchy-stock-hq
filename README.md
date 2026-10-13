# Omarchy Stock HQ

> Fork of [5d0tal1gat0r/omarchy-stocks](https://github.com/5d0tal1gat0r/omarchy-stocks)
> that adds multiple watchlists, a quant-dense quote table, technical
> analysis, a local AI agent per symbol and gist-synced watchlists. All
> original stock ticker implementation credit goes to the upstream project and
> its author; see [Credits](#credits).

A Wall-Street-style ticker tape for the Omarchy Quattro bar. The tape scrolls
your symbols (`AAPL 305.59 ▲0.42%  •  NVDA …`) in the theme's green/red; click
it for a two-level panel:

- **Level 1** — the active watchlist as a dense, sortable table: last, change,
  change %, day-range bar, opening gap, day span, 52-week position, distance
  off the 52-week high, volume, 1D sparkline and last trade time, plus an
  advancers/decliners summary. Switch, create, rename and delete watchlists;
  add, edit and remove symbols inline.
- **Level 2** — one symbol: chart with range selector, SMA20 and
  support/resistance overlays, plain-English technical notes (trend, SMA20/50,
  RSI14, volume), full stats, and a local AI agent (Claude Code, Codex,
  Gemini, …) that analyses the symbol in the background with preset or custom
  prompts.

Watchlists live in a JSON file you can import/export, and can sync with a
GitHub gist so you can also edit them on the web. Taiwan and other Asian
markets work too (`2330.TW` or `TW:2330`). Quotes and FX rates come from Yahoo
Finance — no API key — and are cached so the panel shows the last known data
right after a shell restart.

**Level 1: every symbol at a glance.** Sort by any column; the bars show where
the price sits in the day's range (tick = previous close) and in its 52-week range.

![Level 1: quote table](preview-table.png)

**Level 2: one symbol, with the agent's answer.** Chart, full stats, and a
Quick take written by Claude Code with web search, rendered in the panel.

![Level 2: chart, stats and agent analysis](preview-detail.png)

## Install

```sh
omarchy plugin add https://github.com/siygle/omarchy-stock-hq.git --enable
```

The plugin id is `io.github.siygle.stock-hq`, so it installs next to the
upstream `io.github.5d0tal1gat0r.stocks` widget instead of replacing it. If you
are switching over, an upstream `symbols` setting seeds the first watchlist
once you copy it across with `omarchy bar set`; then remove the upstream plugin. Optional requirements: the
[`gh`](https://cli.github.com) CLI, signed in, for gist sync, and an agent CLI
(`claude`, `codex`, `gemini`, …) for analysis.

The widget lands in the bar's center section. Move it with:

```sh
omarchy bar move io.github.siygle.stock-hq --section right
```

## Usage

| where | action | effect |
|-------|--------|--------|
| tape | left click | open / close the panel (Esc closes, Tab switches panels) |
| tape | middle click | refresh now |
| tape | right click / hover | pause the tape (hover pauses while pointing) |
| table | click a row / `j` `k` + Enter | open that symbol (level 2); Esc or `h` goes back |
| table | `Sort` chips: `Chg% ↓` `Chg% ↑` `Chg ↓` `Chg ↑` `List order` | one-click sort by daily move (percent or amount), or back to the list's own order (persisted) |
| table | click a column header | sort by any column: descending → ascending → watchlist order (persisted) |
| table | watchlist chips / `+ List` | switch lists or create another one |
| table | list name field (Enter) / `Delete list` | rename or remove the active watchlist |
| table | `Add symbols` field | add one or more symbols (`tsm, TW:2330`) |
| table | hover a row, `✎` / `×` | edit (replace) or remove the symbol |
| table | `USD ⇄` chip | left click: next currency · right click: previous · `Native` = each quote in its own currency |
| table | `⟳` | refresh all quotes now |
| table | `⚙` | settings: refresh interval, `Export` / `Import` / `Open JSON ↗` for the watchlists file |
| table | `Create sync gist` / `Sync` / `Open gist ↗` | see [Gist sync](#gist-sync) |
| detail | `1D 5D 1M 6M 1Y` | chart range (persisted); the technical notes follow it |
| detail | agent preset chips / custom prompt field | run the agent on this symbol, see [Agent](#agent) |
| detail | `Open on Yahoo Finance ↗` | open the symbol in your browser |

IPC (for keybindings): `omarchy-shell io.github.siygle.stock-hq toggle|open|close|refresh|pause|sync`,
`… detail <SYMBOL>` (open level 2) and `… analyze <SYMBOL>` (open level 2 and run the first agent preset).

## Watchlists

Watchlists live in a JSON definition file, not in `shell.json`:

```sh
$EDITOR ~/.local/share/omarchy-stock-hq/watchlists.json   # picked up on save
```

```json
{
  "version": 1,
  "activeWatchlist": 0,
  "watchlists": [
    { "name": "Main", "symbols": ["AAPL", "NVDA", "SPCX", "GOOGL"] },
    { "name": "Taiwan", "symbols": ["2330.TW", "0050.TW"] }
  ]
}
```

The panel edits this file; `⚙` → `Export` writes a dated copy to a folder you
pick and `Import` loads one. Until the file exists, the widget's `watchlists`
or `symbols` setting seeds it.

Native Yahoo symbols work everywhere (`2330.TW`, `6488.TWO`, `0700.HK`,
`7203.T`, `005930.KS`), and the add field also accepts shortcuts like
`TW:2330`, `tw2330`, `TWO:6488`, `HK:0700`, `JP:7203`, `KR:005930`,
`SH:600519`, `SZ:000001`, `SG:D05` and `AU:BHP`.

## Gist sync

Click `Create sync gist` in the panel footer: a secret gist holding
`stocks.json` is created with all your watchlists and its id is stored as
`gistId`. Or point at an existing gist:

```sh
omarchy bar set io.github.siygle.stock-hq gistId https://gist.github.com/<you>/<id>
```

Every refresh pulls the gist; an edit made on gist.github.com replaces the
local watchlists, and every edit in the panel (or an import) pushes straight
back. The gist wins when both sides changed (and on shell start). Which list
is active stays per machine. The gist file uses the `watchlists.json` shape;
`{"symbols": [...]}`, a JSON array, or plain text (one symbol per line or comma
separated, `#` for comments) also work and become a single "Main" list. All calls go through the signed-in `gh` CLI
(`gh auth login`); no token is stored by the widget.

## Agent

Level 2 runs a local agent CLI in the background on the shown symbol, streams
its answer into the panel (rendered as Markdown), and keeps the latest answer
per symbol in `~/.cache/omarchy-stocks/agent/<SYMBOL>.md`. One run at a time;
`Cancel` stops it.

```sh
# the default; any CLI that takes a prompt argument and prints the answer works
omarchy bar set io.github.siygle.stock-hq agentCommand '["claude","-p","--allowedTools=WebSearch,WebFetch","{prompt}"]' --json
omarchy bar set io.github.siygle.stock-hq agentCommand '["codex","exec","{prompt}"]' --json
omarchy bar set io.github.siygle.stock-hq agentPrompts '[{"name":"繁中快評","prompt":"用繁體中文分析 {name} ({symbol})，最新報價：{quote}"}]' --json
```

Every prompt is sent with the symbol on screen as context: a line naming it
and its latest quote as JSON is prepended, so a bare custom prompt like
`這支股票近期的風險？` works. Prompts that already use `{quote}` (such as the
Quick take preset) carry the data themselves and are sent as written.

Prompts (presets and the custom field) can also use `{symbol} {name} {exchange}
{currency} {price} {change} {changePct} {dayLow} {dayHigh} {week52Low}
{week52High} {volume}` and `{quote}` (all quote fields, plus the technical
notes for the chart range on screen, as JSON).

## Configure

UI preferences live on the widget's entry in `~/.config/omarchy/shell.json` and
apply instantly. Fetched quotes and charts are cached separately in
`~/.local/state/omarchy-stock-hq/cache.json`.

```sh
omarchy bar set io.github.siygle.stock-hq tickerWidth 260
omarchy bar set io.github.siygle.stock-hq scrollSpeed 30
omarchy bar set io.github.siygle.stock-hq currency EUR
omarchy bar set io.github.siygle.stock-hq compact true --json    # "AAPL ▲0.42%" without the price
```

| key | default | meaning |
|-----|---------|---------|
| `watchlistsPath` | `~/.local/share/omarchy-stock-hq/watchlists.json` | another watchlists definition file |
| `symbols` / `watchlists` | `["AAPL","NVDA","SPCX","GOOGL"]` | only seed `watchlists.json` when it does not exist yet |
| `refreshMinutes` | `5` | quote refresh interval (minimum 1; `⚙` sets it) |
| `tickerWidth` | `180` | tape width in px (minimum 80) |
| `scrollSpeed` | `20` | tape speed in px/s; `0` = static |
| `compact` | `false` | drop the price from the tape |
| `chartRange` | `1d` | one of `1d 5d 1mo 6mo 1y` (the panel chips set this) |
| `currency` | `""` (native) | show every price in this currency, e.g. `EUR` (the panel chip sets this) |
| `currencies` | `["USD","EUR","GBP","JPY","CHF"]` | what the currency chip cycles through |
| `upColor` / `downColor` | theme `green` / `red` | override the tints with a hex color, e.g. `"#a6e3a1"` |
| `sortKey` / `sortDesc` | `""` / `true` | table sort (the column headers set these); `""` = watchlist order |
| `gistId` | `""` (off) | gist id or URL for watchlist sync |
| `gistFile` | `stocks.json` | file inside the gist |
| `agentCommand` | `["claude","-p","--allowedTools=WebSearch,WebFetch","{prompt}"]` | agent argv; `{prompt}` is replaced (appended when absent) |
| `agentPrompts` | Quick take / Technical / News & catalysts | `[{"name": …, "prompt": …}]` preset chips |

Unknown symbols show as `Not Found` in the panel and are left out of the tape.
Colors follow the current theme's `colors.toml`; themes without a `green` get a
neutral fallback.

## Develop

Clone this repository (or your fork), then from its root:

```sh
node --test test/model.test.js                              # Model.js unit tests
/usr/lib/qt6/bin/qmllint -I /usr/share/omarchy/shell *.qml
omarchy plugin validate "$PWD"
omarchy plugin add "$PWD" --enable                          # installs a clone into ~/.config/omarchy/plugins/
rsync -a --delete --exclude .git ./ ~/.config/omarchy/plugins/io.github.siygle.stock-hq/
omarchy restart shell                                       # QML is cached per shell process; a restart loads the edit
qs log -p /usr/share/omarchy/shell --tail 100               # shell log
```

`Model.js` holds every piece of logic that does not need QML (parsing, formatting,
conversion, chart geometry, watchlists, technical indicators, table metrics,
gist and agent commands) so it can be tested with plain Node. `Panel.qml` owns the state; `QuoteTable.qml` (level 1)
and `DetailView.qml` (level 2) render it; `GistSync.qml` and `AgentRunner.qml`
wrap the `gh` and agent processes.

## Remove

```sh
omarchy plugin remove io.github.siygle.stock-hq
```

## Credits

Built on [omarchy-stocks](https://github.com/5d0tal1gat0r/omarchy-stocks) by
[@5d0tal1gat0r](https://github.com/5d0tal1gat0r). This fork reuses its whole
foundation: the ticker tape, the Yahoo Finance fetching and parsing, currency
conversion, chart geometry, theming and the test suite. Thank you! This fork
adds multiple watchlists with import/export, Asian market symbols, the quote
cache, technical analysis, the level-1 quote table, the level-2 view with the
local agent runner, and gist sync.

## License

MIT. See [LICENSE](LICENSE); the original copyright notice of
omarchy-stocks is kept.
