# Stocks bar widget for Omarchy Quattro — design

**Date:** 2026-08-18
**Plugin id:** `io.github.al1gat0r.stocks`
**Target:** Omarchy 4.0 (Quattro) `omarchy-shell` (Quickshell) bar, plugin schema v1

## Goal

A third-party Omarchy shell plugin that shows stock quotes in the bar: a compact
pill that cycles through a configurable list of symbols, plus a click-to-open
panel listing every symbol with price and change. Data comes from Yahoo
Finance's public chart endpoint (no API key). It must pass
`omarchy plugin validate`, `qmllint`, and be publishable to the marketplace as-is.

## Repository layout

```
omarchy-stocks/                    git repo, source of truth
├── manifest.json
├── BarWidget.qml                  bar pill; loads Panel.qml (first-party weather pattern)
├── Panel.qml                      state owner: fetch Process, timers, quotes table popup
├── Model.js                       pure functions, node-testable (module.exports guard)
├── test/model.test.js             node:test unit tests
├── README.md                      install / usage / configure / develop / remove
├── LICENSE                        MIT
├── preview.png                    screenshot (added after first live run)
└── docs/superpowers/specs/        this document
```

The plugin is installed with `omarchy plugin add <path-or-git-url> --enable`,
which git-clones it into `~/.config/omarchy/plugins/io.github.al1gat0r.stocks/`.
The plugin folder must not be a symlink (fails validation; `inotifywait -r`
hot-reload does not follow symlinks). During development the working tree is
rsynced into the installed copy (excluding `.git`) to trigger hot reload.

## Manifest

```json
{
  "schemaVersion": 1,
  "id": "io.github.al1gat0r.stocks",
  "name": "Stocks",
  "version": "0.1.0",
  "author": "al1gat0r",
  "license": "MIT",
  "description": "Stock ticker pill with a quotes panel for the Omarchy bar (Yahoo Finance, no API key).",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "BarWidget.qml" },
  "barWidget": {
    "displayName": "Stocks",
    "category": "Info",
    "allowMultiple": false,
    "defaultSection": "center"
  }
}
```

## Settings

Stored inline on the widget's `shell.json` layout entry (per the shell's storage
rules); read with the `setting(name, fallback)` helper inherited from
`BarWidget`/`Panel`. Users change them with
`omarchy bar set io.github.al1gat0r.stocks <key> <value> [--json]`.

| key              | default                              | rules |
|------------------|--------------------------------------|-------|
| `symbols`        | `["AAPL", "NVDA", "SPCX", "GOOGL"]`  | JSON array **or** comma/space-separated string; trimmed, upper-cased, de-duplicated, empty entries dropped; empty result falls back to the default |
| `refreshMinutes` | `5`                                  | integer, clamped to `>= 1`; non-numeric → default |
| `cycleSeconds`   | `10`                                 | integer, `0` = pin first valid symbol (no rotation); negative/non-numeric → default |
| `compact`        | `false`                              | `true` → bar label omits the price |

## Data source

Yahoo Finance chart endpoint, one URL per symbol, fetched by a single `curl`
invocation so the shell owns exactly one child process per refresh:

```
curl -sS --max-time 10 -A "<UA>" -w "\n" \
  https://query1.finance.yahoo.com/v8/finance/chart/<SYM>?range=1d&interval=1d ...
```

`-w "\n"` terminates each response so stdout is one JSON document per line.
A missing symbol yields `{"chart":{"result":null,"error":{"code":"Not Found",...}}}`
on its own line and does not affect the other symbols. Fields used from
`chart.result[0].meta`: `symbol`, `shortName`/`longName`, `currency`,
`regularMarketPrice`, `chartPreviousClose` (fallback `previousClose`),
`regularMarketDayLow/High`, `fiftyTwoWeekLow/High`, `regularMarketTime`,
`fullExchangeName`.

A `User-Agent` header is required (Yahoo returns 429/403 for curl's default in
some regions); use `Mozilla/5.0 (X11; Linux x86_64) omarchy-stocks/<version>`.

## Model.js (pure, unit-tested)

```
normalizeSymbols(value, fallback)         -> string[]
refreshMinutes(value, fallback)           -> int  (>= 1)
cycleSeconds(value, fallback)             -> int  (>= 0)
curlCommand(symbols, userAgent)           -> string[]   argv for Process.command
parseQuoteLines(stdoutText, symbols)      -> Quote[]    one per requested symbol, in request order
formatPrice(price, currency)              -> "305.59"  (2 decimals; 4 when |price| < 1; thousands separator)
formatChange(quote)                       -> "▲ +1.28 (0.42%)" / "▼ -2.05 (0.50%)" / "" when unknown
barLabel(quote, compact)                  -> "AAPL 305.59 ▲0.42%" / "AAPL ▲0.42%" / "AAPL …" (loading) / "AAPL !" (error, no data)
nextIndex(current, quotes)                -> index of next quote with no error, wrapping; -1 when none
firstValidIndex(quotes)                   -> first non-error index or -1
quoteUrl(symbol)                          -> https://finance.yahoo.com/quote/<SYM>
```

`Quote` shape:

```
{ symbol, name, currency, exchange, price, prevClose, change, changePct,
  dayLow, dayHigh, week52Low, week52High, marketTime, error }
```

`error` is `""` on success, otherwise a short message (`"Not Found"`, `"No data"`,
`"Bad response"`). Numeric fields are `null` when unavailable. `changePct` is a
percentage number (0.42), not a fraction.

## Panel.qml (state owner)

- `property var quotes: []`, `property string fetchError: ""`,
  `property var lastUpdated: null`, `property int cycleIndex: 0`,
  `property string label: ""`, `readonly property bool loading`.
- `refresh()` starts `fetchProc` unless already running; resets the retry budget.
- `fetchProc` (Quickshell.Io `Process`) with `StdioCollector { waitForEnd: true }`.
  On finish: empty stdout → `scheduleRetry()` (max 3, 2.5 s apart, like
  `omarchy.weather`); otherwise `quotes = Model.parseQuoteLines(...)`,
  `lastUpdated = new Date()`, `fetchError = ""` if any quote succeeded, else the
  first quote's error. On failure the previous `quotes` stay visible (stale but
  useful) and `fetchError` explains it in the footer.
- `refreshTimer`: `interval = refreshMinutes * 60000`, `repeat`, `triggeredOnStart`.
- `cycleTimer`: `interval = cycleSeconds * 1000`, `running` only when
  `cycleSeconds > 0` and more than one valid quote; `onTriggered` sets
  `cycleIndex = Model.nextIndex(cycleIndex, quotes)`.
- `onQuotesChanged`: clamp `cycleIndex` to a valid index (`firstValidIndex` when
  the current one is invalid); `onSymbolsChanged` (settings edit): reset
  `cycleIndex = 0`, restart refresh.
- `label` binding: `Model.barLabel(currentQuote, compact)`; while nothing has
  loaded yet it shows `<firstSymbol> …`.
- `currentIsDown`: `currentQuote && currentQuote.change < 0` (drives bar text
  color).
- Panel UI: `KeyboardPanel` + `PanelKeyCatcher` (Esc closes, Tab switches
  panels). Content column: header row (`Stocks` bold + `Updated HH:mm` muted),
  `Repeater` over `quotes`: symbol (bold, fixed width), name (muted, elided),
  price (right-aligned), change (right-aligned; `Color.urgent` when negative);
  rows with `error` show the symbol and the error text muted. Row click opens
  `Model.quoteUrl(symbol)` with `xdg-open` through `bar.run(...)`. Footer:
  `fetchError` (urgent) when non-empty; otherwise `Middle-click to refresh`.
- `IpcHandler` on target `io.github.al1gat0r.stocks` with `open/close/show/hide/toggle/refresh`
  (`manageIpc: false` on the base, own handler like weather so `refresh` exists).

## BarWidget.qml

Follows `omarchy.weather` exactly for panel plumbing: `Loader` for `Panel.qml`,
`injectPanel()` forwarding `bar`, `settings`, `anchorItem`, `hostWidget`;
forwards `opened`, `open()`, `close()`, `closeForPopoutSwitch()`,
`popoutSwitchClosing` so `omarchy-shell shell summon/hide/toggle` route to it.

Button: `WidgetButton` (text pill, like the clock) with
`text: panel.label`, `active: panel.currentIsDown`, `activeColor: bar.urgent`
(theme "urgent" color for a falling stock, plain foreground otherwise).

Input: left click → toggle panel; middle click → `refresh()`; right click and
scroll wheel → step to the next/previous valid symbol (restarting the cycle timer).
`tooltipText: ""` (panel is the detail view, as with weather).

## Error handling summary

| situation | bar | panel |
|-----------|-----|-------|
| first load in flight | `AAPL …` | header + "Loading…" |
| network down, no prior data | `AAPL !` | footer shows curl/parse error, retries 3× then waits for the timer |
| network down, prior data | last good label (unchanged) | last good rows + footer error |
| one bad symbol | skipped by cycler | row shown muted with `Not Found` |
| all symbols bad | `<first> !` | rows muted, footer error |
| `symbols` set to junk | falls back to defaults | — |

## Verification

1. `node --test test/` — Model.js unit tests (written first, TDD).
2. `qmllint -I /usr/share/omarchy/shell BarWidget.qml Panel.qml`.
3. `omarchy plugin validate <repo>`.
4. `omarchy plugin add <repo path> --enable --yes` → `omarchy plugin list --json`
   shows the id enabled; `omarchy bar move io.github.al1gat0r.stocks --section center`.
5. `omarchy-shell shell summon io.github.al1gat0r.stocks '{}'` /
   `omarchy-shell shell hide io.github.al1gat0r.stocks`; screenshot with `grim`
   for visual check (also becomes `preview.png`).
6. `qs log -p /usr/share/omarchy/shell --tail 100` shows no QML errors from the plugin.
7. Settings round-trip: `omarchy bar set io.github.al1gat0r.stocks symbols '["SPY","QQQ"]' --json`
   updates the pill without restart.

## Out of scope (v1)

Sparkline/price history, Finnhub or other providers, `allowMultiple` instances,
pre/post-market prices, per-symbol alerts, currency conversion.

---

## Revision 2 (2026-08-18) — ticker tape + charts

Requested after the v1 pill was built: the bar shows a **horizontally scrolling
ticker tape** instead of a cycling pill, and the panel shows **charts and more
details**. Sections above remain valid except where this revision overrides them.

### Bar (replaces "BarWidget.qml" section)

`WidgetButton` container (keeps bar hover/tooltip/click registration) with the
label hidden and a clipped tape viewport inside:

- Fixed width `tickerWidth` px (setting, default `360`, min `80`).
- Content: every valid quote as `SYM price ▲pct` (`compact` drops the price),
  separated by ` • `; items whose day change is negative use the bar's urgent
  color, others the bar foreground. Invalid symbols are omitted from the tape
  (still listed in the panel).
- Scrolls right-to-left at `scrollSpeed` px/s (setting, default `40`; `0` =
  static). The run is repeated enough times to cover the viewport plus one run
  and animated over exactly one run width, so the loop is seamless.
- Hover pauses; right-click toggles pause; left-click toggles the panel;
  middle-click refreshes. Wheel does nothing.
- Vertical bars show a static `SYM\n▲` for the first valid symbol.
- While loading / when nothing is valid the label falls back to `AAPL …` /
  `AAPL !` (v1 behavior).
- IPC target `io.github.al1gat0r.stocks`: `open close show hide toggle refresh pause`.
- `cycleSeconds` setting is removed. `cycleIndex` becomes the panel's
  `selectedIndex`.

### Data (extends "Data source")

- Quote fetch (periodic, one curl): `range=1d&interval=5m` per symbol. Meta
  gives price/day change (`previousClose`, falling back to
  `chartPreviousClose`), `regularMarketVolume`; `timestamp[]` +
  `indicators.quote[0].close[]` give the intraday series (nulls skipped);
  `indicators.quote[0].open[]` first non-null gives the day's open.
- Chart fetch (on demand, second curl): `range=<r>&interval=<i>` with
  `1d→5m, 5d→15m, 1mo→1d, 6mo→1d, 1y→1wk`, for all symbols, when the panel's
  active range is not `1d`. Only the series is used from these responses
  (`chartPreviousClose` there is the close before the range start, not the
  previous session). Cached until the next quote refresh or range change.
- New setting `chartRange` (default `1d`, one of `1d 5d 1mo 6mo 1y`); the
  panel's range chips persist their choice into the entry via
  `bar.shell.updateEntryInline` (as `omarchy.clock` does for `format`).

### Panel (replaces the "Panel UI" bullet)

Width `Style.space(440)`. Top to bottom:

1. Header: `Stocks` · range chips `1D 5D 1M 6M 1Y` (selected chip filled) · `Updated HH:mm`.
2. Rows, one per symbol: `SYM` · name (elided) · sparkline (Canvas 72×20,
   colored by direction over the active range) · price · day change (urgent
   when negative). Clicking selects the row (highlighted); invalid symbols
   show their error muted, no sparkline.
3. Detail block for the selected valid symbol: name + `exchange · currency`;
   big price + change; chart (Canvas, full width × `Style.space(120)`: line,
   soft gradient fill, min/max labels, dashed previous-close line on `1d`
   when inside the bounds, first/last time labels); stats grid: Prev close,
   Open, Day range, 52w range, Volume (`32.7M`), Last trade (`ddd HH:mm`);
   `Open on Yahoo Finance ↗` link (xdg-open).
4. Footer: fetch error (urgent) or hint.

### Model.js additions

```
CHART_RANGES = ["1d","5d","1mo","6mo","1y"]
chartRange(value, fallback="1d")          -> validated lower-case range
chartInterval(range)                      -> "5m"|"15m"|"1d"|"1wk"
chartUrl(symbol, range="1d")              -> URL with matching interval
curlCommand(symbols, ua, range="1d")
tickerWidth(value, fallback=360)          -> int >= 80
scrollSpeed(value, fallback=40)           -> number >= 0
parseChartResponse(line)                  -> Quote + { series: [{t,c}], open, volume }
parseSeriesLines(text, symbols)           -> { SYM: series }
seriesBounds(series)                      -> {min,max} | null
seriesDirection(series)                   -> last.c - first.c (0 when < 2 points)
seriesPoints(series, w, h, pad)           -> [{x,y}] time-proportional x, value-scaled y
valueToY(value, bounds, h, pad)           -> y | null when outside bounds
tapeItems(quotes, compact)                -> [{symbol, text, down}] valid quotes only
formatVolume(n)                           -> "950" | "114.9K" | "32.7M" | "1.2B" | ""
```
