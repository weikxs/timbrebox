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
platform (handy when the window is hidden and there is no Cmd+Q): it saves the
session and finishes pending file writes before the process exits.

## Security

- Bound to **loopback only** (`127.0.0.1`), so nothing off the machine can
  reach it.
- **Web pages are refused.** A page in your browser can also send requests to
  `127.0.0.1`, so the server additionally:
  - accepts only a `Host` of `127.0.0.1:<port>` or `localhost:<port>` (this
    defeats DNS rebinding);
  - refuses any request with an `Origin` header or a `Sec-Fetch-Site` other
    than `none`, which browsers add to requests made by pages;
  - runs actions only for `POST`, so a plain link or `<img>` cannot trigger
    them (`405` otherwise; reads are `GET`).
- **A per-run token.** Each time the API starts, the app writes a new random
  256-bit token to a file named `control-token` in its support directory,
  readable only by your account (mode `0600` on macOS and Linux; the per-user
  AppData folder on Windows). Every request must send it in the
  `X-TimbreBox-Token` header, or gets `401`. Other users on the machine, and
  anything that cannot read your files, cannot drive the player. The file is
  deleted when the API stops:

  | Platform | Token file |
  |---|---|
  | macOS | `~/Library/Containers/io.timbrebox.timbreboxApp/Data/Library/Application Support/io.timbrebox.timbreboxApp/control-token` |
  | Linux | `${XDG_DATA_HOME:-~/.local/share}/io.timbrebox.timbrebox_app/control-token` |
  | Windows | `%APPDATA%\io.timbrebox\TimbreBox\control-token` |

  Settings → General → Agent control shows the path. `tools/timbrebox-ctl`,
  the Dart CLI and the MCP server read it themselves; `TIMBREBOX_TOKEN_FILE`
  (a path) or `TIMBREBOX_TOKEN` (the token) override the lookup.
- macOS requires the `com.apple.security.network.server` entitlement (already
  shipped).

## Discovery & CLI

The server binds a fixed preferred port in **8787–8796** (first free one), so a
local agent can find it without knowing the ephemeral port. Hand the token to
curl on stdin (`-H @-`) rather than on its command line, where other users
could see it in the process list:

```bash
TOKEN_FILE=...   # the token file for your platform, see above
tb() { printf 'X-TimbreBox-Token: %s\n' "$(cat "$TOKEN_FILE")" | curl -H @- "$@"; }
for p in 8787 8788 8789 8790 8791 8792 8793 8794 8795 8796; do
  tb -s "http://127.0.0.1:$p/" | grep -q 'TimbreBox control API' && BASE="http://127.0.0.1:$p" && break
done
```

The repo ships a wrapper, **`tools/timbrebox-ctl`**, that does this discovery and
wraps every endpoint (e.g. `tools/timbrebox-ctl search "jazz"`,
`tools/timbrebox-ctl play-ref <source> <item>`). For AI agents there is a skill
at `.claude/skills/timbrebox-control/`.

(The app also writes `~/.timbrebox/control.json` with the address and the
token file's path — never the token — but on sandboxed macOS builds the app's
HOME is inside its container, so the port scan above is the reliable
cross-platform discovery.)

## Endpoints

All responses are JSON. Reads are `GET`; everything else is `POST`, and the
server answers `405` to the other method.

| Method | Path | Description |
|---|---|---|
| GET | `/` | Discovery document (endpoints + current status) |
| GET | `/status` | Playback state: `playing`, `positionMs`, `volume`, `loop`, `queueLength`, `track` |
| GET | `/playback-status` | Read-only `state`, `hasError`, optional `stage`, `failureStage`, safe `errorCode`. Distinguishes resolving/opening/native failure without raw error text, track identities or URLs. Does not start playback. CLI: `timbrebox-ctl playback-status`. |
| GET | `/search-status` | Read-only latest search: `hasQuery`, `isSearching`, per-source `status`, `count`, optional `failure.code/retryable`. No query, titles, URLs, credentials or raw error messages; does not start a search. CLI: `timbrebox-ctl search-status`. |
| GET | `/queue` | The play queue (`items[]`) |
| GET | `/sources` | Sources with `id`, `name`, `enabled` |
| GET | `/lyric` | Current track's lyric (plugin sources only), or `null` |
| POST | `/search?q=` | Search all enabled sources; returns `results[]` (`source`, `item`, `title`, `artist`) |
| POST | `/play` `/pause` `/toggle` `/next` `/previous` `/stop` | Transport controls |
| POST | `/seek?ms=<int>` | Seek to a position in milliseconds |
| POST | `/volume?level=<0..1>` | Set the volume |
| POST | `/mode?loop=<queue\|track\|off\|shuffle>` | Set the loop mode |
| POST | `/play-ref?source=<id>&item=<id>` | Play a track from a prior `/search` |
| POST | `/play-queue?i=<index>` | Play the queue entry at `index` |
| POST | `/source?id=<id>&enabled=<true\|false>` | Enable/disable a source |
| POST | `/quit` | Quit the whole app (a background instance) |

Errors return an appropriate HTTP status and `{ "error": "..." }`; a missing or
stale token gets `401`.

## Examples

```bash
BASE="http://127.0.0.1:<port>"   # shown in Settings → General → Agent control
# tb = curl plus the token header, as defined under Discovery & CLI

# Current state
tb "$BASE/status"

# Search, then play the first result
tb -X POST "$BASE/search?q=jazz"
tb -X POST "$BASE/play-ref?source=audius&item=abc123"

# Transport + volume + loop
tb -X POST "$BASE/toggle"
tb -X POST "$BASE/volume?level=0.6"
tb -X POST "$BASE/mode?loop=shuffle"

# Play a queue entry
tb -X POST "$BASE/play-queue?i=2"
```
