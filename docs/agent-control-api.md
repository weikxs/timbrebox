# TimbreBox Agent Control API

**Language: English · [简体中文](./agent-control-api.zh-CN.md)**

---

A local HTTP API that lets a local agent, CLI, or script drive the TimbreBox
player. It is **on by default** and can be toggled in **Settings → General →
Agent control**; the settings panel shows the address.

## Running in the background

The app serves this API for as long as its **process** is alive — it does not
need to be the foreground window. Closing the window keeps the app (and the
control server) running in the background on every desktop:

- **macOS** — the window hides; reopen from the Dock or by relaunching. Quit with
  Cmd+Q.
- **Windows / Linux** — the window hides; **relaunch** the app to bring it back
  (it is single-instance). Quit with `POST /quit` (`timbrebox-ctl quit`).

To start it without stealing focus, launch it backgrounded — on macOS:
`open -g -a TimbreBox`. `POST /quit` shuts the whole app down cleanly on any
platform (handy when the window is hidden and there is no Cmd+Q).

## Security

- Bound to **loopback only** (`127.0.0.1`) on an ephemeral port. Loopback is the
  security boundary: nothing off the machine can reach it, only local processes.
- **No token / authentication** — since only local processes can connect, a
  token would add friction without adding protection.
- macOS requires the `com.apple.security.network.server` entitlement (already
  shipped).

## Discovery & CLI

The server binds a fixed preferred port in **8787–8796** (first free one), so a
local agent can find it without knowing the ephemeral port:

```bash
for p in 8787 8788 8789 8790 8791 8792 8793 8794 8795 8796; do
  curl -s "http://127.0.0.1:$p/" | grep -q 'TimbreBox control API' && BASE="http://127.0.0.1:$p" && break
done
```

The repo ships a wrapper, **`tools/timbrebox-ctl`**, that does this discovery and
wraps every endpoint (e.g. `tools/timbrebox-ctl search "jazz"`,
`tools/timbrebox-ctl play-ref <source> <item>`). For AI agents there is a skill
at `.claude/skills/timbrebox-control/`.

(The app also writes `~/.timbrebox/control.json` with the address, but on
sandboxed macOS builds the app's HOME is inside its container, so the port scan
above is the reliable cross-platform discovery.)

## Endpoints

All responses are JSON. `GET` is used for reads, `POST` for actions (the server
does not enforce the method, but this is the intended convention).

| Method | Path | Description |
|---|---|---|
| GET | `/` | Discovery document (endpoints + current status) |
| GET | `/status` | Playback state: `playing`, `positionMs`, `volume`, `loop`, `queueLength`, `track` |
| GET | `/queue` | The play queue (`items[]`) |
| GET | `/sources` | Sources with `id`, `name`, `enabled` |
| GET | `/lyric` | Current track's lyric (plugin sources only), or `null` |
| GET | `/search?q=` | Search all enabled sources; returns `results[]` (`source`, `item`, `title`, `artist`) |
| POST | `/play` `/pause` `/toggle` `/next` `/previous` `/stop` | Transport controls |
| POST | `/seek?ms=<int>` | Seek to a position in milliseconds |
| POST | `/volume?level=<0..1>` | Set the volume |
| POST | `/mode?loop=<queue\|track\|off\|shuffle>` | Set the loop mode |
| POST | `/play-ref?source=<id>&item=<id>` | Play a track from a prior `/search` |
| POST | `/play-queue?i=<index>` | Play the queue entry at `index` |
| POST | `/source?id=<id>&enabled=<true\|false>` | Enable/disable a source |
| POST | `/quit` | Quit the whole app (a background instance) |

Errors return an appropriate HTTP status and `{ "error": "..." }`.

## Examples

```bash
BASE="http://127.0.0.1:<port>"   # shown in Settings → General → Agent control

# Current state
curl "$BASE/status"

# Search, then play the first result
curl "$BASE/search?q=jazz"
curl "$BASE/play-ref?source=audius&item=abc123"

# Transport + volume + loop
curl "$BASE/toggle"
curl "$BASE/volume?level=0.6"
curl "$BASE/mode?loop=shuffle"

# Play a queue entry
curl "$BASE/play-queue?i=2"
```
