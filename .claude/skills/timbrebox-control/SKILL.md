---
name: timbrebox-control
description: Control the TimbreBox desktop music player (this repo's Flutter app) whenever the user wants to play, find, or control music by natural language — e.g. "播放周杰伦的歌", "放首歌听", "搜索<歌名/歌手>", "暂停/继续/停止", "下一首/上一首", "调大声音/音量 0.6", "单曲循环/随机播放", "看看播放队列", "关掉某个音源", or English "play some Jay Chou", "pause", "next track", "set volume", "shuffle", "show the queue". Trigger on ANY request to play / search-and-play / pause / resume / stop / skip / seek / set volume / change loop or shuffle mode / inspect or play from the queue / read the lyric / enable-disable a source. Drives the one running app instance via its local loopback HTTP control API (timbrebox-ctl subcommands). Not for editing the player's source code.
---

# Controlling the TimbreBox player

TimbreBox (the Flutter desktop music player in this repo) exposes a **local HTTP
control API** bound to loopback. It is **on by default** (Settings → General →
Agent control). Loopback binding *is* the security boundary — nothing off the
machine can reach it — so there is **no token**.

This skill drives the **one running app instance**. It does not launch, build, or
edit the player; if the app isn't running, ask the user to start it.

## When to use (auto-trigger)

Invoke this skill automatically — without asking — for any natural-language music
request aimed at the player, in Chinese or English. Examples:

- "播放周杰伦的歌" / "放首歌" / "play some Jay Chou" → **search then play** (see the
  flow below): `timbrebox-ctl search "周杰伦"` → `timbrebox-ctl play-ref <source> <item>`.
- "暂停" / "继续" / "停" → `timbrebox-ctl pause` / `play` / `stop`.
- "下一首" / "上一首" → `timbrebox-ctl next` / `prev`.
- "声音调到 0.6" / "静音" → `timbrebox-ctl volume 0.6` / `timbrebox-ctl volume 0`.
- "随机播放" / "单曲循环" → `timbrebox-ctl mode shuffle` / `track`.
- "现在放的什么" / "看看队列" → `timbrebox-ctl status` / `queue`.

A bare artist/song name with an intent to listen ("来点周杰伦") is a **play**
request: run the search→play flow, don't just show results.

> **These are not slash commands.** The only slash command this skill adds is
> `/timbrebox-control`. Everything below is either a **`timbrebox-ctl`
> subcommand** or an **HTTP path on the local server** (`$BASE/…`). Generic words
> like `status`, `search`, `stop`, `help` are namespaced by the `timbrebox-ctl`
> binary and the loopback port — always write them as `timbrebox-ctl <cmd>`, never
> as a bare `/status`, so they never collide with Claude Code's built-in `/status`,
> `/help`, etc.

## Step 1 — Find the running player

The server binds the first free port in the fixed range **8787–8796**. Discover
it by probing until one answers with the discovery document:

```bash
for p in 8787 8788 8789 8790 8791 8792 8793 8794 8795 8796; do
  if curl -s "http://127.0.0.1:$p/" | grep -q 'TimbreBox control API'; then
    BASE="http://127.0.0.1:$p"; break
  fi
done
[ -n "$BASE" ] || echo "TimbreBox not running / Agent control disabled"
```

From inside this repo, prefer the wrapper `tools/timbrebox-ctl`, which does the
discovery for you: `tools/timbrebox-ctl <command> [args]` (run `timbrebox-ctl
help` for usage). If nothing responds, the app isn't running or Agent control was
turned off — tell the user to launch TimbreBox (it's on by default).

## Step 2 — Commands

Every response is JSON. Prefer the wrapper; the raw curl equivalent is shown too.

| Intent | Wrapper | Raw request |
|---|---|---|
| Current state | `timbrebox-ctl status` | `curl -s "$BASE/status"` |
| Search all enabled sources | `timbrebox-ctl search "周杰伦"` | `curl -sG "$BASE/search" --data-urlencode "q=周杰伦"` |
| Play a search/queue result | `timbrebox-ctl play-ref <source> <item>` | `curl -sG "$BASE/play-ref" --data-urlencode source=<s> --data-urlencode item=<i>` |
| Resume / Pause / Toggle | `timbrebox-ctl play` \| `pause` \| `toggle` | `curl -s "$BASE/play"` \| `/pause` \| `/toggle` |
| Next / Previous | `timbrebox-ctl next` \| `prev` | `curl -s "$BASE/next"` \| `/previous` |
| Stop (clears playback) | `timbrebox-ctl stop` | `curl -s "$BASE/stop"` |
| Seek to position (ms) | `timbrebox-ctl seek 30000` | `curl -sG "$BASE/seek" --data-urlencode ms=30000` |
| Volume (0..1) | `timbrebox-ctl volume 0.6` | `curl -sG "$BASE/volume" --data-urlencode level=0.6` |
| Loop mode | `timbrebox-ctl mode shuffle` | `curl -sG "$BASE/mode" --data-urlencode loop=shuffle` |
| Show queue | `timbrebox-ctl queue` | `curl -s "$BASE/queue"` |
| Play queue index | `timbrebox-ctl play-queue 2` | `curl -sG "$BASE/play-queue" --data-urlencode i=2` |
| List sources | `timbrebox-ctl sources` | `curl -s "$BASE/sources"` |
| Enable/disable a source | `timbrebox-ctl source youtube false` | `curl -sG "$BASE/source" --data-urlencode id=youtube --data-urlencode enabled=false` |
| Current lyric | `timbrebox-ctl lyric` | `curl -s "$BASE/lyric"` |
| Quit the app | `timbrebox-ctl quit` | `curl -s "$BASE/quit"` |

`loop` / `mode` accept exactly `queue`, `track`, `off`, `shuffle`. `volume` and
`level` are `0.0`–`1.0`. `seek`/`ms` is an absolute position in milliseconds.
`play-queue`/`i` is a 0-based index into the queue.

## Response shapes

Field names are exact — parse these, don't guess.

**Status object** — returned by `/status` and by every transport action
(`/play`, `/pause`, `/toggle`, `/next`, `/previous`, `/stop`, `/seek`, `/volume`,
`/mode`, and on success of `/play-ref`, `/play-queue`):

```json
{
  "playing": true,
  "loading": false,
  "positionMs": 14730,
  "volume": 0.6,
  "loop": "queue",
  "queueLength": 12,
  "track": {
    "source": "youtube", "item": "abc123",
    "title": "…", "artist": "…", "sourceName": "YouTube",
    "durationMs": 213000
  }
}
```
`track` is `null` when nothing is loaded.

**`/search`** → `results` items carry `source` + `item` (the ids you feed back to
`/play-ref`); they do **not** include `durationMs`:

```json
{ "query": "周杰伦",
  "results": [ { "source": "youtube", "item": "abc123",
                 "title": "…", "artist": "…", "sourceName": "YouTube" } ] }
```

**`/queue`** → `{ "items": [ { source, item, title, artist, sourceName, durationMs } ] }`
**`/sources`** → `{ "sources": [ { "id": "youtube", "name": "YouTube", "enabled": true } ] }`
**`/lyric`** → `{ "lyric": "…" }` (or `{ "lyric": null }` when the source has none)
**`/source`** → `{ "ok": true }`
**`/play-ref`, `/play-queue`** → success: `{ "ok": true, …status }`; failure:
`{ "ok": false, "error": "…" }` with HTTP 404.
**`/`** → discovery doc: `{ name, version, auth, endpoints, status }`.

**Errors** come back as `{ "error": "…" }` with HTTP 400 (bad/missing param),
404 (not found), or 500 (internal). Always check the status code / `ok` field
before reporting success.

## Typical flow: "play a song"

1. `timbrebox-ctl search "<query>"` → read `results[]`; each has `source`, `item`, `title`, `artist`.
2. Pick the best match (usually the first, or match `title`/`artist` to the request).
3. `timbrebox-ctl play-ref <source> <item>` → the response is the fresh status object.
4. Confirm playback from that status (`playing: true`, the `track` fields).

Search hits every enabled source, so results may span YouTube / Bilibili / Audius
/ etc. If the user names a source, filter `results[]` by `source`, or disable the
others first with `timbrebox-ctl source <id> false`.

## Notes

- The app must be running; this API controls that one instance only.
- `stop` clears playback; `pause`/`toggle` keep the position (resume continues).
- Some sources are region-limited; a `play-ref` can fail if no stream resolves —
  report the `error` and try another result or source.
