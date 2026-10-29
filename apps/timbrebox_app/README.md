# TimbreBox

The TimbreBox player app — the five-platform (Windows / macOS / Linux / iOS /
Android) Flutter shell. It hosts the UI, downloads, themes, the plugin system,
the system media session, and the local agent control API. Business rules that
must stay UI-, network-, and platform-free live in the `timbrebox_core` package;
the online sources live in `timbrebox_sources` and the playback backend in
`timbrebox_playback`, so other apps can share them.

For features, architecture, and getting started see the repository
[README](../../README.md); for authoring plugins see
[docs/plugin-development.md](../../docs/plugin-development.md); for the local
control API see [docs/agent-control-api.md](../../docs/agent-control-api.md).

## Run

```bash
flutter pub get
flutter run -d macos   # or windows / linux / <device>
flutter analyze
flutter test
```
