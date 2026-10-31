# Optional desktop media backend

This is an experimental host capability, **not a claim that four platform sources are ready to use**.
It is disabled unless the build explicitly configures a local executable and SHA-256, or a reviewed
local-test component bundle with a build-pinned manifest. Nothing is downloaded
or installed automatically. Android/iOS report `extractor_unsupported`.

## Architecture

```text
platform plugin → env.media → fixed Dart operations → pinned local yt-dlp
                ← stable items / transient audio description ←
getMediaSource → existing egress-checked stream proxy → playback backend
```

Plugins cannot supply executable paths, environment variables, shell commands or command-line switches.
The supported platform identifiers are `youtube`, `bilibili`, `douyin`, `tiktok`.

- `env.media.search(platform, query, page)`: keyword search and pagination. YouTube/Bilibili use the pinned
  extractor. An explicit macOS Debug `TIMBREBOX_GUEST_SEARCH_TEST=true` enables the fixed official guest
  search bridge for TikTok/Douyin; default builds return `platform_search_unavailable` for those two.
  This is not a general browser/script API: isolated in-memory visitor data, fixed official HTTPS
  navigation, denied media capture/new windows, bounded time/50 metadata rows and scoped cancellation.
  The bridge never creates or displays a search window. A site requiring visibility or user interaction
  returns an error/timeout in the app, with no automatic visible-window fallback.
  Website networking is a separate trust boundary, not Dart HTTP egress. Search is not a playback grant.
  The earlier visible-window TikTok prototype passed five real plugin/RPC/native pages, but this is not
  evidence that the current windowless path succeeds; other queries returned refusals/empty bodies.
  A deadline fix now preserves already validated nonempty pages rather than discarding them while
  waiting for 50 rows; no response, malformed data or a later refusal is still an error, not empty success.
  Cached short-page boundaries remain stable across subsequent fetches. One windowless TikTok keyword
  passed two real pages (20 distinct results) with the fix. After correcting cross-plugin JavaScriptCore
  message routing, the normal app also returned ten TikTok results each for two user keywords alongside
  YouTube and Bilibili. This is not general search acceptance or short-video playback acceptance.
  Douyin's minimal HTTP-200 page has now been positively classified as a short verification shell,
  with no search response. It returns `guest_search_access_required` rather than an ambiguous timeout;
  no window, login or CAPTCHA handling is started automatically. The fixed diagnostic asset exports
  only counters/booleans, never page text or addresses.
- `env.media.resolve(platform, itemOrLink)`: validate a stable item or video/share link, fetch fresh metadata,
  verify content access, and return `{item, media}`. A link is not a search implementation.
- `env.media.source(platform)`: shared adapter returning `search`, `getMediaSource`, `importMusicItem`.
  Its `search` routes supported links through import, so the existing search box can accept a share link.
  The app still does not independently dispatch the `importMusicItem` hook from a separate import UI.

The development plugin files live in the separate `homeplay-plugins/experimental/platforms/` directory.
They are not installed automatically, published by this change, or included in the subscription.
The Bilibili development plugin now uses official HTTP directly, not this optional backend. It has
passed real search and muted native-audio acceptance in the macOS sandbox, including paging, pause/resume,
seek, saved-reference reload and canonical-link import. Short links, expiry, background and other systems
still need acceptance. The normal subscription is unchanged.

## Build configuration

Use a reviewed, locally installed executable and an independently checked SHA-256. These build-time values
are **not plugin settings**:

```sh
flutter build macos --debug \
  --dart-define=TIMBREBOX_YTDLP_PATH=/absolute/path/to/yt-dlp \
  --dart-define=TIMBREBOX_YTDLP_SHA256=<reviewed-64-character-sha256>
```

The runner checks the absolute path, resolves symlinks, and verifies the executable file before every run.
A script wrapper's hash does not pin its interpreter or imported packages: review and pin those separately.
No version is installed, updated or trusted merely because it is on `PATH`.

The macOS application remains sandboxed; no temporary filesystem, semaphore or other exceptions were
added. Direct use of the external tool failed inside it. The single-file packaged executable also failed
because its unpacking bootloader needs a denied SysV semaphore. The reviewed directory-mode local-test
bundle now initializes and plays real audio inside the unchanged sandbox. Filesystem and process-start
failures retain separate privacy-preserving categories.

### Opt-in local macOS arm64 bundle

`tools/prepare_media_bundle.py` accepts only the pinned upstream directory archive and runtime bytes,
preserves original dependency data/notices, signs process entrypoints for sandbox inheritance, and
produces a helper, resources and manifest. No downloads. The manifest pins the supervisor, extractor,
runtime, every Python payload file and mandatory notices; unknown added files or links fail closed.
Verification is cancellable. The C supervisor isolates a worker group and terminates descendants on
cancellation or parent exit, with an OS-level cancellation regression test.

```sh
python3 tools/prepare_media_bundle.py \
  --extractor "$REVIEWED_EXTRACTOR_ZIP" --runtime "$REVIEWED_DENO" \
  --licenses "$REVIEWED_NOTICES" --output build/media-bundle-local
```

Use its digest as `TIMBREBOX_MEDIA_BUNDLE_SHA256`, and point the build-only environment variable
`TIMBREBOX_PREPARED_MEDIA_BUNDLE` at that prepared folder. The optional Xcode phase embeds it in Debug
only; Release/Profile embedding is refused. Ordinary builds without that variable remove optional
components from their own output. The embedding phase never touches user data.

The combined extractor is GPLv3+, while its source is Unlicense; the runtime is MIT. Original notices
accompany the local build. Public redistribution, corresponding-source obligations, standard release
layout, other architectures and store approval need separate review. This local profile adds about
220 MB; unused sources start neither a tool nor a resident service.

## Limits and trust

- On-demand one-shot processes: at most two globally and one per runtime, 20-second deadline, 4 MiB stdout,
  64 KiB discarded stderr. Cancel/dispose kills the active process. No idle process or background polling.
- No shell, inherited user environment, user configs, extractor plugin directories, disk cache, account/cookie
  options, unconfigured JS runtimes, remote components, download, conversion or transcoding. The opt-in
  bundle permits only its pinned local runtime and private per-job cache, removed on exit.
- YouTube's full feature set can require components disabled by these choices. Return failure; do not silently
  enable downloads, unreviewed runtimes or login.
- Input URLs are HTTPS, known platform hosts and supported video/short-link shapes. Tracking parameters are
  stripped; stable references preserve TikTok handles and Bilibili parts.
- The native tool performs its own network requests: **its internal DNS and redirects do not pass through the
  Dart egress policy**. It is an explicit binary/dependency trust boundary, not a generic sandboxed HTTP client.
  Returned playback URLs still pass through the existing proxy and egress checks.
- Prefer supported progressive audio-only streams. The fixed desktop bridge may fall back to a progressive
  MP4/WebM containing audio only after access verification, with known dimensions no larger than 720p and
  total bitrate no greater than 1.5 Mbps. It reports the actual video-container MIME. The shared player keeps
  `vid=no` and `vo=null`; no video view is attached. This fallback still needs real-platform application
  acceptance. DRM-marked formats and manifests are rejected. Only transport headers are returned;
  cookies and authorization headers are dropped.

## Paid, VIP and preview filtering

Known paid/VIP/subscriber-only/private/preview flags exclude search entries. Search entries whose status is
unknown remain marked `accessState: unknown`; they must pass a fresh full check before playback.
Playback requires explicit public, free and non-preview evidence; missing fields are not silently assumed
false. Partial sections and uninterpreted entitlement objects are not accepted.

A reviewed YouTube-specific evidence profile now accepts a full `Youtube` video response with explicit
public availability, zero age restriction, non-live state, positive duration, formats and no DRM. This
profile does not apply to flat search entries or other providers. Explicit paid/preview/private flags,
malformed flag values, partial sections and uninterpreted entitlement objects still deny access first.
No synthetic free/non-preview flags are inserted. Other responses without sufficient evidence still
return `content_unverified`. Video audio is not a promise of a complete song.

## Explicit live acceptance

Create a private JSON build-defines file containing `LIVE_PLUGIN_BASE64` (base64 of the reviewed plugin
source), `LIVE_PLUGIN_ORIGIN` (its stable public source URL), `LIVE_PLUGIN_QUERY` (a real search query), and
`LIVE_PLUGIN_LINK_TEMPLATE` (the canonical page pattern containing `{id}`). Do not put account credentials,
anonymous session values or signed media URLs in build defines. The test installs into a temporary plugin
directory, never the user's plugin collection, keeps playback muted, and disposes its runtime/player/proxy.

```sh
flutter test integration_test/live_plugin_audio_test.dart -d macos --no-pub \
  --dart-define-from-file=<private-build-defines.json>
```

The tool-only initialization target accepts the reviewed `TIMBREBOX_YTDLP_*` pair or the opt-in
`TIMBREBOX_MEDIA_BUNDLE_SHA256` manifest. It invokes
`--version` without any platform request, separating sandbox/dependency startup failure from upstream
network or content failure. Neither opt-in target runs from ordinary offline `flutter test`.

Earlier metadata-only selection returned YouTube URLs that actually refused playback with HTTP 403.
The resolver now checks real bytes after access verification, probes a bounded quality ladder including
a low-bandwidth audio fallback, and rejects empty or HTML responses. Verified `contentLength` and
`boundedRanges` reach the generic proxy; it fetches at most 1 MB per window and rejects a server ignoring
the range contract rather than concatenating whole files.

Three real music queries now pass inside the sandbox: search, a distinct second page, actual HTTP 206
audio bytes, native audio progress, disabled video, pause/resume, seek, stable-reference reload and
canonical link import. The local user trial has YouTube and Bilibili enabled; the normal subscription is
unchanged. Short links, real paid/trial counterexamples, expiry, background and other systems need further
acceptance.

### Original YouTube audio path comparison

A macOS Debug test build can set `TIMBREBOX_YOUTUBE_DART_AUDIO_TEST=true` to restore the original
`youtube_explode_dart` 2.5.3 keyword search and independent audio-manifest paths (BSD-3-Clause; original
notices retained in Flutter NOTICES). Search traverses real official continuation pages in a bounded
per-call client, closes HTTP on completion/cancel/timeout, and does not invent access evidence. Audio
prefers AAC, checks the returned video identity/CDN/duration where provided, verifies
real bytes, and uses the existing bounded Range proxy. Each library HTTP client closes on completion,
cancellation or timeout; the library is not started for unused sources.

This is a transitional search/audio switch, not a whole-repository rollback: the fixed tool still supplies
fresh public/full-access evidence before the original manifest client may run. Paid/preview/unknown or
mismatched metadata cannot reach it. Search retains the existing plugin protocol; this profile still
includes the optional tool bundle for rights verification. No Cookie or browser login is used.
Two real user keywords passed native sandbox search/second-page tests in about two seconds total per
keyword; the normal app returned ten YouTube results for each, alongside TikTok and Bilibili.

Apple plugin engines now use the host's context-addressed JavaScriptCore message callback, avoiding
flutter_js 0.8.7's process-global last-engine callback. Messages are decoded only in their originating
context; owned JS timers, context entries and handlers are removed before engine disposal. The other
engines, sandbox privileges and credential boundaries are unchanged. Multi-engine interleaving and
last-engine disposal have regression coverage. `timbrebox-ctl search-status` reads protected per-source
counts/states/error codes without triggering searches or returning queries/payloads.

Two same-reference sandbox tests (the user's selected video and a previously failing video) passed actual
206 independent MP4 audio, at least eight seconds of native progress, disabled video, pause/resume, seek,
saved-reference reload and link import. The normal local test app has been started with this switch while
preserving the user's queue, volume and source enablement. It does not claim all YouTube videos or either
short-video source are now working. After the context-routing fix the selected YouTube reference again
passed full muted native acceptance; another previously failing reference then timed out within the
old 22-second resolution budget. Per-phase live measurements showed a valid sequence needing about
23 seconds. The shared total budget is now 24 seconds, still below the plugin's 25-second async envelope;
all phases, cancellation and refresh remain inside that bound. Both same references subsequently passed
full muted native acceptance, including >=8 seconds, controls, reload and link import. This corrects the
measured cutoff, not a guarantee that every video or network condition will succeed.

A subsequent failing user reference exposed redundant watch-page work in the Dart manifest stage. The
host now uses the pinned library's documented `requireWatchPage: false` option only after the same fresh
access/identity checks; the library may still retrieve the page if decoding needs it. No client identity,
Cookie or signature implementation was added. Two same-reference sandbox resolutions took about
15.7/11.9 seconds, and both passed the complete app engine/controller/native playback pipeline.

Native asynchronous decoder errors are now optional backend/engine events. They invalidate the active
load and publish a sanitized failed state instead of silently remaining playing or advancing the queue
as a natural completion. Native opening is cancellable and bounded; stopping an unfinished open also
stops its assigned source. A real invalid-file negative test verifies this path. The mini player exposes
loading/cancellation and failure text. The protected read-only `playback-status` endpoint reports safe
phase/error codes without addresses or raw decoder messages. A short muted test of the selected user
reference in the normal app confirmed at least eight seconds of progress; original position, queue,
volume and paused state were restored. This is not an audible listening check or short-video admission.

## Tests and rollback

Offline tests cover request validation, keyword routing, pagination, reference identities, paid/preview
filtering, audio format selection, the real JS bridge, error codes, cancellation/serialization, process
hash checks and process termination. Two explicit online integration targets separate real audio acceptance
(`integration_test/live_plugin_audio_test.dart`) from sandbox tool initialization
(`integration_test/media_tool_sandbox_test.dart`). They are skipped without build-time opt-in. The former
has passed for the direct-HTTP Bilibili plugin, with real source data, native audio progress, disabled video,
pause/resume, seek and stable-reference reload. It is muted and does not replace manual listening or other
systems' acceptance. Directory-mode tool initialization and three real YouTube music-query runs now pass inside the sandbox.

To disable: build without any media-backend defines or prepared-bundle environment variable, or
disable/uninstall a development plugin. No migration or
subscription change is required; the normal player and HTTP plugins keep working.
