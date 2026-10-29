# TimbreBox Plugin Development Guide

**Language: English · [简体中文](./plugin-development.zh-CN.md)**

> How to write, package, install, and debug a third-party music-source plugin for
> TimbreBox. Plugins are single-file CommonJS scripts written in the **TimbreBox
> plugin format**.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Security Model](#2-security-model)
3. [Plugin Anatomy](#3-plugin-anatomy)
4. [Supported Functions & Data Shapes](#4-supported-functions--data-shapes)
5. [Available `require()` Modules](#5-available-require-modules)
6. [Complete Example Plugin](#6-complete-example-plugin)
7. [Installing, Updating & Managing](#7-installing-updating--managing)
8. [Limitations / Not-Yet-Supported](#8-limitations--not-yet-supported)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Overview

A TimbreBox plugin is **one JavaScript file** that exports a music source using
the CommonJS convention:

```js
module.exports = {
  platform: 'My Source',
  version: '1.0.0',
  async search(query, page, type) { /* ... */ },
  async getMediaSource(musicItem, quality) { /* ... */ },
};
```

This is the **TimbreBox plugin format** — a plugin is just a script that exports
the functions and metadata fields TimbreBox understands (see below).

### How the app runs it

Each installed plugin is loaded into its own **sandboxed JavaScript engine**:

| Platform                | Runtime engine     |
| ----------------------- | ------------------ |
| Windows / Linux / Android | interpreted engine (QuickJS) |
| macOS / iOS             | system engine (JavaScriptCore) |

On load, TimbreBox evaluates, in order: a small **prelude** (`console`, `env`,
`process`, `require` and the host-HTTP bridge), **`URL`/`URLSearchParams`**, an
**axios-compatible client**, the **bundled shim libraries** your plugin names,
a fresh `module`/`exports` pair, then your plugin source. What the module
exported is captured as `globalThis.__plugin`: `module.exports`, or
`module.exports.default` when a build from an ES module set `exports.default`
(and left no `platform` on `module.exports` itself). Exported functions are
invoked on demand.

Plugins written in the same format for other players usually run unchanged:
the globals and the axios behavior they rely on are provided (section 5).

Function calls are **serialized** on the single runtime (search and resolve
requests never interleave), each call is JSON-encoded in and out, and each call
has a **25-second timeout**. The engine runs on the app's UI thread, so a run of
plugin code that does not yield — a `while (true) {}` — is **stopped after
three seconds** (on Linux, Android, macOS and iOS; the Windows engine build
offers no such stop) and the engine is restarted on the next call. Await network requests
instead of busy-waiting.

The engine starts on the plugin's first call, not at launch, and is **shut
down after five minutes without a call**; the next call starts a fresh one.
Keep state that must survive that in the items you return, not in globals.

### The HTTP bridge

Your plugin never talks to the network directly. When you call `axios(...)`, the
shim posts the request description to the Dart host (`__hostHttp`), Dart runs
the request **off the runtime thread** through the egress policy, then settles the
promise (`__resolveHost`). This is the *only* capability that crosses the sandbox
boundary.

---

## 2. Security Model

Plugins are treated as **untrusted code**. The design assumptions:

- **Only HTTP is exposed.** No `fs`, no `process`, no raw sockets, no arbitrary
  `require`, no timers-to-native, no access to other plugins or app state. The
  engine's own `fetch` / `XMLHttpRequest` are removed — `axios` is the only way
  out.
- **Egress policy** (enforced in Dart, in one place, on *every* request and
  *every* redirect hop):
  - Only `http` / `https` schemes are allowed.
  - **Internal targets are blocked**: `localhost`, `*.localhost`, `*.local`,
    `*.internal`, and every loopback, private, link-local, CGNAT, multicast or
    reserved address (IPv4, IPv6, and IPv4 embedded in IPv6 such as
    `::ffff:127.0.0.1`).
  - **Host names are resolved first** and every address they resolve to must be
    public; the connection then goes to that checked address, so DNS rebinding
    cannot swap in a private one.
  - IPv4 written in any form other than plain dotted decimal (`127.1`,
    `0177.0.0.1`, `2130706433`, `0x7f000001`) is refused.
  - **Redirects are followed manually** (max 4 hops; more is an error), and
    every hop is checked again. Redirects are followed as `GET` and drop the
    request body.
  - Responses are capped (**8 MB** for plugin requests; installs cap the script
    at **6 MB**) and each request has a **20-second** transport timeout.
- **Isolation:** each plugin runs in its own runtime; a crash or exception in one
  plugin does not affect others or the app.
- **User consent on install:** installing shows a confirmation dialog
  ("插件是社区提供的脚本，会以你的名义发起网络请求…请仅安装你信任的来源") that the
  user must accept ("我信任，安装").

> Because all traffic is proxied through the host with your device's IP,
> **install only sources you trust.** A malicious plugin can still exfiltrate the
> queries you type or fetch tracking URLs — it just cannot touch your machine,
> your LAN, or the filesystem.

---

## 3. Plugin Anatomy

`module.exports` (or `exports.default`, see above) must be an object. Fields
fall into three groups.

### Required metadata

| Field      | Type   | Meaning                                                                      |
| ---------- | ------ | ---------------------------------------------------------------------------- |
| `platform` | string | **Identity of the source.** Shown in UI; drives the stable source id.        |
| `version`  | string | Semver, e.g. `"1.2.0"`. Displayed as `vX.Y.Z`; defaults to `0.0.0` if absent. |

> The source id is derived from `platform`:
> `plugin_<slug>` where `<slug>` is `platform` lowercased with non-alphanumerics
> replaced by `_`, truncated to 32 chars (ids must match
> `^[a-z][a-z0-9_]{1,31}$`). **Two plugins with the same `platform` collide** —
> installing the second replaces the first.

### Optional metadata

| Field    | Type   | Meaning                                                                          |
| -------- | ------ | -------------------------------------------------------------------------------- |
| `srcUrl` | string | Canonical update URL. Used by "检查更新" to re-fetch and diff. Falls back to the install URL if omitted. |
| `author` | string | Displayed under the plugin name in Settings.                                     |

### Functions

At minimum you must export **`search`** — a plugin without it is rejected at
install time ("插件缺少 search 功能，无法作为音源"). Everything else is optional and
enables extra capabilities. See the next section for exact signatures.

The capabilities TimbreBox advertises for a plugin are derived from which
functions exist:

| Exported function | Capability enabled |
| ----------------- | ------------------ |
| `search`          | Search             |
| `getMediaSource`  | Streaming / playback |
| `getLyric`        | Lyrics             |
| `getTopLists` (+ `getTopListDetail`) | Charts in the "热门" library |

---

## 4. Supported Functions & Data Shapes

All functions may be `async` (return a Promise). Arguments and return values are
JSON-serialized across the bridge, so **only plain JSON-compatible data** (no
functions, no class instances) survives round-trips.

### The `MusicItem` shape

Returned by `search`, chart details, etc. Consumed by `getMediaSource` /
`getLyric` (the *entire* object you returned is handed back, so plugin-private
fields you attach are preserved).

| Field       | Type            | Notes                                                                 |
| ----------- | --------------- | --------------------------------------------------------------------- |
| `id`        | string/number   | **REQUIRED.** Items without a non-empty `id` are silently dropped.    |
| `title`     | string          | **REQUIRED** (non-empty after trim).                                  |
| `artist`    | string          | Optional. Falls back to the source name if empty.                     |
| `album`     | string          | Optional.                                                             |
| `artwork`   | string (URL)    | Cover art. TimbreBox also accepts `coverImg` or `pic` as fallbacks.   |
| `duration`  | number          | **Seconds** (a bare number is treated as seconds).                    |

You may attach any additional fields your `getMediaSource` needs (track hashes,
signed tokens, mid, etc.) — they ride along on the item. When the user saves a
track (favorites, a playlist, the play queue), the item is saved with it so it
can still play after a restart — **minus** any URL value or field named `url`,
and minus fields whose names look like credentials (`token`, `cookie`, `auth`,
`secret`, `session`, `sign`, `key`, `passw`). Give `getMediaSource` stable ids
it can re-resolve from; anything credential-like is available only until the
app quits.

### `search(query, page, type) -> { isEnd, data }`

```js
async function search(query, page, type) {
  // type is ALWAYS 'music' in TimbreBox (other search types are not used).
  // page is 1-based.
  return {
    isEnd: false,               // true when there are no more pages
    data: [ /* MusicItem[] */ ] // each item MUST have an id
  };
}
```

- If `isEnd` is falsy, TimbreBox offers page `page + 1` as the next cursor.
- A return value that isn't an object, or whose `data` isn't an array, yields an
  empty result page (not an error).

### `getMediaSource(musicItem, quality) -> { url, headers?, userAgent? }`

```js
async function getMediaSource(musicItem, quality) {
  return {
    url: 'https://cdn.example.com/audio/123.mp3',
    headers: { Referer: 'https://example.com/' }, // optional
    userAgent: 'Mozilla/5.0 ...'                  // optional
  };
}
```

- **Quality fallback:** TimbreBox calls this repeatedly, trying qualities in the
  order **`standard` → `high` → `super` → `low`**, and stops at the first result
  with a non-empty `url`. So a plugin that only exposes `high`/`super` still
  works. (Note: TimbreBox does **not** pass a user's preferred quality — it only
  probes this fixed order. See [Limitations](#8-limitations--not-yet-supported).)
- **Every URL is played through a loopback proxy.** It injects the `headers`
  and/or `userAgent` you return on every request hop (the media player cannot
  attach arbitrary headers itself) and checks every redirect hop against the
  egress policy. `userAgent` is merged into the headers as `User-Agent`.
- MIME type is inferred from the URL extension (`.m4a`/`.mp4`, `.mp3`, `.flac`,
  `.ogg`); include a recognizable extension when you can.
- **The `url` must be a public `http(s)` URL.** It goes through the same egress
  policy before anything plays, proxies or downloads it; `file://` and
  local/LAN addresses are refused.

### `getTopLists() -> [ { title, data } ]`

```js
async function getTopLists() {
  return [
    {
      title: 'Featured Charts',      // group heading (not surfaced individually)
      data: [
        { id: 'chart_hot', title: 'Hot 100', coverImg: 'https://…/cover.jpg' },
        // ...
      ]
    }
  ];
}
```

- TimbreBox **flattens all groups** into one list of charts.
- Each chart entry needs `id` + non-empty `title`. Cover comes from
  `coverImg` / `artwork` / `pic` (first present).

### `getTopListDetail(topListItem, page) -> { isEnd, musicList | data }`

```js
async function getTopListDetail(topListItem, page) {
  // topListItem is the exact chart object you returned from getTopLists.
  return {
    isEnd: true,
    musicList: [ /* MusicItem[] */ ] // 'data' is also accepted
  };
}
```

TimbreBox currently requests page `1` and reads `musicList` (or `data`).

### `getLyric(musicItem) -> { rawLrc | lrc }`

```js
async function getLyric(musicItem) {
  return { rawLrc: '[00:00.00] line one\n[00:03.20] line two' };
  // 'lrc' and 'lyric' are also accepted as the text field.
}
```

Returns LRC-formatted lyric text. An empty/absent value means "no lyric".

---

## 5. Available `require()` Modules

Only this **whitelist** resolves; any other `require('…')` throws
`插件请求了不允许的模块：<name>`. These are the modules available via `require()`:

| Module        | What it is                                                                 |
| ------------- | ------------------------------------------------------------------------- |
| `axios`       | An **HTTP client** — a fetch shim wired to the host HTTP bridge. See below. |
| `crypto-js`   | Crypto helpers: hashing / HMAC / AES etc. (`CryptoJS.MD5`, `CryptoJS.HmacSHA256`, …). |
| `cheerio`     | An HTML parser with a jQuery-like API (`cheerio.load(html)`).             |
| `he`          | HTML entity encode/decode.                                                |
| `dayjs`       | Date parsing/formatting.                                                  |
| `qs`          | Query-string stringify/parse.                                            |
| `big-integer` | Arbitrary-precision integers (for signing schemes).                      |

You can `require('axios')` or rely on the global `axios` — both are the same shim.

`require` is also available as `__musicfree_require`, the name some plugin
builds use; it resolves the same whitelist.

### Globals

| Global | What it is |
| ------ | ---------- |
| `env` | Read-only: `env.appVersion` (TimbreBox's version, `dev` in local builds), `env.os` (`android`, `ios`, `macos`, `windows` or `linux`), `env.lang` (`zh-CN` or `en-US`), and `env.getUserVariables()`, which returns a fresh object each call (currently always `{}`, see section 8). |
| `process` | Read-only: `process.platform` (same as `env.os`), `process.version` (same as `env.appVersion`), `process.env` (the `env` object). |
| `URL`, `URLSearchParams` | Parse and build http(s) URLs, resolve a relative URL against a base, read and write the query. Hosts are kept as written (no IDNA conversion). |
| `console` | `log`, `info`, `warn`, `error`, `debug`; objects are printed as JSON. |
| `setTimeout`, `clearTimeout` | Provided by the engine. |

### The axios-compatible client

`axios` behaves like axios for what plugins use:

```js
axios(config) / axios(url, config?) / axios.request(config)
axios.get / delete / head / options (url, config?)
axios.post / put / patch (url, data?, config?)
const api = axios.create({ baseURL, headers, params, timeout });   // an instance
axios.defaults.headers.common['X-Name'] = 'value';                  // every request
axios.defaults.headers.get = { /* GET only */ };
api.interceptors.request.use(fn); api.interceptors.response.use(fn, onError);
```

- **Config**: `url`, `method`, `baseURL`, `headers`, `params` (object or
  `URLSearchParams`), `data`, `timeout` (ms, at most 20 000),
  `responseType`, `validateStatus`, `transformRequest`, `transformResponse`.
  Instance defaults and per-request config are merged as in axios.
- **Body**: a string is sent as is; a `URLSearchParams` is sent form-encoded;
  any other object is sent as JSON with `Content-Type: application/json` unless
  you set a content type yourself.
- **Response**: `{ data, status, statusText, headers, config }`. `data` is
  JSON-parsed when it parses; set `responseType: 'text'` (or `'arraybuffer'` /
  `'blob'`) to keep the raw text. The bridge carries text only, so binary
  bodies arrive as a UTF-8 string.
- **Errors**: as in axios, a status outside 2xx **rejects** with an error that
  has `isAxiosError: true`, `code` (`ERR_BAD_REQUEST` / `ERR_BAD_RESPONSE`),
  `message` (`Request failed with status code 404`) and `response`. Pass
  `validateStatus: () => true` (or `null`) to resolve every status. A
  `timeout` that runs out rejects with `code: 'ECONNABORTED'`; a refused or
  failed request with `code: 'ERR_NETWORK'`.
- **Headers you set are sent as they are**, `Cookie` included; nothing is
  stored or added between requests.

```js
const res = await axios.get('https://api.example.com/search', {
  params: { q: 'hello', page: 1 },
  headers: { 'User-Agent': 'TimbreBox' },
});
// res.status === 200; res.data is a parsed object, or a string if not JSON.
```

### What is NOT available

- No `fs`, `path`, `os`, `child_process`, `net`, `http`/`https` (Node), `crypto`
  (Node's — use `crypto-js`), `buffer`, or any other Node builtin.
- No real `process` (only the read-only object above), no environment
  variables, no timers into native code.
- **No cookie jar persistence.** Each `axios` call is independent; `Set-Cookie`
  is not stored or replayed. If a source needs a session cookie, you must read it
  from a response header yourself and pass it back explicitly on the next
  request's `headers`.
- No `import`/ESM — use CommonJS (`module.exports`, `require`).

---

## 6. Complete Example Plugin

A minimal but realistic **API-based** plugin using `axios` + `crypto-js`. It
implements `platform`, `version`, `search`, and `getMediaSource`, and shows how
to carry a plugin-private field (`songmid`) from search into media resolution and
how to return header-gated playback URLs.

```js
// my-source.js — a TimbreBox plugin.
const axios = require('axios');
const CryptoJS = require('crypto-js');

const API = 'https://api.example.com';

// Some APIs require a signed timestamp. crypto-js runs in-sandbox.
function sign(path, ts) {
  return CryptoJS.MD5(`${path}:${ts}:my-secret-salt`).toString();
}

async function search(query, page, type) {
  // type is always 'music' in TimbreBox — no need to branch on it.
  const ts = Date.now();
  const res = await axios.get(`${API}/search`, {
    params: { keyword: query, page, sign: sign('/search', ts), ts },
    headers: { 'User-Agent': 'TimbreBox/1.0' },
  });

  // res.data is auto JSON-parsed. Guard everything — never trust the API.
  const list = (res.data && res.data.songs) || [];
  const data = list.map((s) => ({
    id: String(s.id),              // REQUIRED, must be a stable non-empty id
    title: s.name,                 // REQUIRED
    artist: (s.artists || []).map((a) => a.name).join(', '),
    album: s.album && s.album.name,
    artwork: s.album && s.album.cover,   // 'coverImg' / 'pic' also accepted
    duration: Math.round((s.durationMs || 0) / 1000), // SECONDS
    songmid: s.mid,                // plugin-private: carried into getMediaSource
  }));

  return {
    isEnd: data.length === 0 || page >= (res.data.totalPages || 1),
    data,
  };
}

async function getMediaSource(musicItem, quality) {
  // quality is one of: 'standard' | 'high' | 'super' | 'low'
  // TimbreBox probes them in that order and takes the first with a url.
  const ts = Date.now();
  const res = await axios.get(`${API}/url`, {
    params: {
      mid: musicItem.songmid,      // the private field we attached in search()
      br: quality,
      sign: sign('/url', ts),
      ts,
    },
  });

  const url = res.data && res.data.playUrl;
  if (!url) return null;           // no url at this quality → TimbreBox tries next

  return {
    url,
    // If the CDN needs a Referer/Cookie/UA, return them here and TimbreBox
    // will auto-proxy playback and inject these per hop.
    headers: { Referer: 'https://example.com/' },
    userAgent: 'Mozilla/5.0 (compatible; TimbreBox)',
  };
}

module.exports = {
  platform: 'Example Source',      // identity + drives the source id
  version: '1.0.0',                // semver
  author: 'you',                   // optional
  srcUrl:                          // optional, used by "检查更新"
    'https://example.com/plugins/my-source.js',
  search,
  getMediaSource,
};
```

An **HTML-scraping** variant would instead `require('cheerio')` and parse
`res.data` (returned as text) with `cheerio.load(html)`.

---

## 7. Installing, Updating & Managing

### Where to install

**设置 (Settings) → 音源插件 (Music Source Plugins).**

Paste one of these into the URL field
("粘贴插件 .js 原始链接，或订阅 JSON 地址") and tap **安装 (Install)**:

1. **A raw plugin `.js` URL** — a direct link to the script file, e.g.
   `https://example.com/plugins/plugin.js`. Plugin scripts, subscriptions and
   update checks are fetched over **https only**, from public hosts, on every
   redirect hop.
   > If your host serves a "preview" page URL for a file, TimbreBox tries to
   > resolve it to the corresponding raw-file URL, so both forms usually work.
2. **A subscription JSON URL** — a document listing many plugins:

   ```json
   {
     "desc": "My plugin bundle",
     "plugins": [
       { "name": "Source A", "url": "https://…/a.js", "version": "1.0.0" },
       { "name": "Source B", "url": "https://…/b.js", "version": "2.1.0" }
     ]
   }
   ```

   Every `url` in `plugins[]` is fetched and installed; individual failures are
   tolerated as long as at least one installs.

Install runs the script once to read `platform` (required) and confirm a `search`
function exists, then persists it. You must accept the **trust confirmation
dialog** first.

### How updates work

Tap **检查更新 (Check for updates)**. For each installed plugin with a `srcUrl`,
TimbreBox re-fetches the script and compares its **SHA-256** against the stored
hash. If the content changed, it reinstalls (and re-reads metadata); if the hash
matches, it's left untouched ("插件已是最新"). Plugins without a `srcUrl` are never
auto-updated.

### Enable / disable / uninstall

- **Toggle switch** next to each plugin enables/disables it as a search source
  (state persists in its `manifest.json`).
- **Trash icon (卸载)** uninstalls: unregisters the source and deletes its stored
  files.

### Where plugins are stored

Under the app support directory:

```
<appSupport>/plugins/<id>/
    plugin.js        # the raw script
    manifest.json    # { id, platform, version, author, srcUrl, sha256, enabled }
```

`<id>` is the derived `plugin_<slug>` id. On app start, every stored plugin is
reloaded into a fresh runtime; a plugin that fails to load is skipped rather than
crashing the app.

---

## 8. Limitations / Not-Yet-Supported

TimbreBox implements a **subset** of the plugin surface. The following are **not
currently wired up** — exporting them has no effect:

- **Login / auth flows:** cookie-based login and persistent cookie jars are not
  supported. `Set-Cookie` is not stored between requests. Declared
  `userVariables` are not shown in Settings yet, so `env.getUserVariables()`
  returns `{}`.
- **Metadata functions:** `getMusicInfo`, `getAlbumInfo`, `getArtistWorks`,
  `getMusicSheetInfo`, `getRecommendSheetsByTag`, and any `import*`
  (`importMusicItem`, `importMusicSheet`) are **not called**.
- **Non-music search:** the `type` argument to `search` is **always `'music'`**.
  Album/artist/sheet/lyric search types are not requested.
- **Quality preference passthrough:** `getMediaSource` is probed in a fixed order
  (`standard → high → super → low`); a user's chosen quality is **not** passed
  through — only the fallback order is used.
- **Charts detail paging:** `getTopListDetail` is currently called for page `1`
  only.
- **Regional backends:** many community sources point at **region-locked**
  backends that may be **geo-blocked or rate-limited** from your network.
  A plugin can install fine yet return no playable URL simply because its API is
  unreachable from your location.

Keep your plugin minimal: as long as `platform`, `version`, and `search` are
present, it will work; unsupported hooks are simply ignored.

---

## 9. Troubleshooting

| Symptom / message | Likely cause & fix |
| ----------------- | ------------------ |
| **"插件缺少 search 功能，无法作为音源"** | `module.exports` has no `search` function. Every source plugin must export `search`. Check you assigned `module.exports` (not just `exports.x = …` in a way that gets clobbered) and that `search` is a function. |
| **"这不是有效的插件（缺少 platform 字段）"** | `platform` must be a non-empty **string**. |
| **"插件脚本无法加载：…"** | The script threw at top level (syntax error, calling a missing global, or `require('somenode')`). Only the whitelisted modules resolve. |
| **"插件请求了不允许的模块：X"** | You `require`'d something outside the whitelist (`axios`, `crypto-js`, `cheerio`, `he`, `dayjs`, `qs`, `big-integer`). Node builtins (`fs`, `crypto`, `http`, `buffer`) are not available. |
| **`cheerio`-style / `require` errors at runtime** | Ensure you `require('cheerio')` (bundled) and feed it `res.data` **as text** — set `responseType: 'text'` so the body isn't JSON-parsed into an object. |
| **"插件未返回可播放的地址"** | `getMediaSource` returned no object, or no non-empty `url`, at any of the four probed qualities. Verify the media API is reachable (see geo-blocking) and that you return `{ url }`. Return `null` at a quality to let TimbreBox try the next. |
| **"出于安全，禁止访问本机或内网地址：…" / "出于安全，不允许使用该协议：…"** (English UI: "Blocked for safety: …") | The egress policy blocked the request or the returned stream `url`: an internal/LAN/loopback host (also one a public name resolves to), a non-http(s) scheme, or a **redirect to an internal address**. Point the plugin at a public https endpoint. |
| **"曲目信息已过期，请重新搜索"** | Playback was attempted for an item TimbreBox no longer has in memory (e.g. after a reload). Re-run the search so the full `MusicItem` is re-cached. |
| **Request "timed out" / hangs** | Requests have a 20s transport cap and each function call a 25s cap; responses over 8 MB are rejected. Avoid downloading large bodies inside the plugin. |
| **Search returns nothing but no error** | `search` returned a non-object, `data` wasn't an array, or every item was missing an `id`/`title`. Every item needs a non-empty `id` **and** `title`. |
| **Plugin silently disappears after restart** | The stored script failed to reload (e.g. it now throws on load). Reinstall from a known-good URL. |
| **Two plugins overwrite each other** | They share the same `platform` (→ same derived id). Give each a distinct `platform`. |

### Debugging tips

- `console.log` / `console.warn` / `console.error` from a plugin are forwarded to
  the app's debug log (prefixed `[plugin]`). Run a debug build and watch the log
  to trace requests and parsing.
- Test your API calls with the exact `axios` config first — remember the response
  body is auto-JSON-parsed unless you pass `responseType: 'text'`.
- When a source needs headers for playback, confirm they're returned from
  `getMediaSource` (not just used during search) — playback proxying only kicks
  in for `getMediaSource` headers.
