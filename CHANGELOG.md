# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Updating a plugin is all or nothing: a new version that does not load leaves the installed one exactly as it was,
  a version that renames itself still replaces the plugin it updates (and keeps it on or off), and an update cut
  short is undone at the next launch. Each plugin that could not be updated is named with the reason.
- The hot library has Chinese radio: the most voted working stations of mainland China, Taiwan and Hong Kong, and
  the top stations worldwide, from Radio Browser, one tap away without searching.
- Openverse is built in: openly licensed music from Jamendo, Freesound, Wikimedia Commons and ccMixter, searched
  without an account. Each track shows its licence (CC BY 4.0, CC0, public domain and so on); mature tracks and
  audio not served over HTTPS are left out. A source that answers "too many requests" now says so.
- Plugins run on Android and iOS too, in the same sandbox as on desktop: HTTP is their only capability, every
  request passes the egress checks, and a run of plugin code is stopped after three seconds (on every platform
  but Windows, whose bundled engine cannot be interrupted).
- More plugins run as written: a plugin built as `exports.default` loads, and plugins get `env` (app
  version, system, language), `process`, `URL` and `URLSearchParams`.
- The plugin `axios` covers what plugins use from axios: `axios.create`, `defaults`, interceptors, `put`,
  `patch`, `delete`, `head`, `baseURL`, `timeout`, `validateStatus` and JSON request bodies.
- Plugin lyrics are line-synced: the line playing is highlighted and kept in view, and tapping a line seeks there.
  A lyric without time stamps is still shown, with a note that it cannot follow playback.
- Downloads show their progress as a percentage and can be stopped: tap the download button again, or the cancel
  button in Local music; the partial file is removed.
- A saved track that can no longer be played offers **Search again**, which searches for its title and artist.
- When a plugin's charts fail to load, the hot library names the plugin and offers **Retry**.
- When settings or library data cannot be saved (a full disk, a permission error), the app says so once per session
  instead of losing the change silently.
- The plugin settings name stored plugins that could not be loaded at launch, and the plugins whose update check
  failed, instead of reporting that everything is up to date.

### Changed

- As in axios, a plugin request answered with a status outside 2xx now rejects, with the response attached
  (`error.response`); plugins that want every status pass `validateStatus: () => true`.
- The online sources and the playback backend moved into their own packages, `timbrebox_sources` and
  `timbrebox_playback`, so other apps can share them. The app works as before.
- Search shows each source's results as soon as that source answers, instead of waiting for the slowest one.
- Much lighter while playing: the window no longer redraws on every position tick, the shown position moves once a
  second, the vinyl record turns at 6 frames a second and stops while the app is in the background, and the frosted
  panels are no longer repainted with it.
- Less memory: the audio engine starts with the first track instead of at launch (about 54 MB less until then), its
  stream cache is sized for audio (2 MB ahead, 512 KB behind), artwork and the custom skin are decoded at the size
  they are shown, the image cache is capped at 32 MB, and old search results are no longer kept for the whole
  session.
- Plugins cost nothing until used: a plugin's engine starts on its first search, stream, chart or lyric, loads only
  the libraries the plugin asks for, and stops after five idle minutes. Launching with several plugins installed
  went from about 400 ms of work to about 20 ms.
- Faster searches and paging: connections are reused instead of opened for every request, plugin responses are
  handed over in one pass, and short-video pages are parsed once, large ones in the background.
- On Linux without a graphics card (software rendering), the spinning record and the frosted glass are off by
  default; turning **Reduce visual effects** off in Settings brings them back.
- The playback position is saved in its own small file, so the queue is no longer rewritten every ten seconds.
- Error messages from the sources, the queue, the control API and the plugin sandbox follow the app's language.
- The audio engine never starts youtube-dl or yt-dlp: TimbreBox resolves every stream itself.

### Removed

- YouTube, Bilibili, Douyin and TikTok are no longer built-in sources. TimbreBox is a player: it builds in only
  open services with public APIs (Audius, Internet Archive, Radio Browser), and other sources are added with
  plugins. Tracks saved from these sources stay in your library; playing one says that a plugin can add its
  source back and offers **Search again**. The hot library's Chinese categories, which searched Bilibili, are
  gone too.

### Fixed

- Playback: a failed load stops the previous track, a superseded play never starts, and resume refuses after a
  failure or the end of a track.
- The queue: a track queued twice no longer loops back to its first copy, removing the playing track no longer skips
  the next one, and playing a list replaces the queue in its order.
- Resuming after a long pause, a Bluetooth reconnect or a restart continues from the saved position.
- The position is saved on pause, seek, stop, every ten seconds and on exit; settings, the session, favorites,
  playlists, history and the download index are written safely, one write at a time, so a crash cannot leave a
  half-written file.
- A failed "load more" waits 15 seconds before trying again instead of retrying in a loop.
- Downloads of two tracks with the same name no longer overwrite each other, and get the right file extension.
- The sleep timer also pauses a track that was still loading.
- A slow track load no longer holds up play, pause and seek: another play, a pause or a stop cancels it, and it gives
  up after 30 seconds.
- Saved radio, plugin and short-video tracks (favorites, playlists, the restored queue) play after a restart.
- Downloads no longer hang on a stalled connection (they give up after 30 seconds without data), partial files left
  by a crash are cleared at the next start, and error messages no longer show local paths.
- Plugin results (search, streams, lyrics, charts) were empty on macOS and iOS; they now arrive.
- A plugin script stuck in a loop is stopped after three seconds instead of freezing the app.
- Updating a plugin no longer stops the track it is playing.
- Installing or updating a plugin writes its files safely, so a crash cannot leave a broken plugin behind.
- Quitting through the control API (`/quit`) saves the session and pending changes before the app exits.

### Security

- The control API needs a per-run token: each start writes a new token to `control-token` in the app's support
  folder, readable only by your account, and every request must send it in the `X-TimbreBox-Token` header. The
  `timbrebox` command, the MCP server and `tools/timbrebox-ctl` read it for you; your own scripts must send it.
  Settings shows where the file is, with a `curl` example.
- Streams relayed through the loopback proxy get random addresses, and the proxy refuses requests that do not name
  it, so a web page cannot reach them through DNS rebinding.
- Every plugin stream and every download goes through the network checks, hop by hop, including redirects.
- Android and iOS builds never load or install plugins; the plugin settings explain that plugins are a desktop
  feature.
