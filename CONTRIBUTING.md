# Contributing to TimbreBox

Thanks for helping! This page is the short version; the full rules are in
[docs/development/standards.md](docs/development/standards.md), and the collaboration rules for people and agents
are in [AGENTS.md](AGENTS.md).

> TimbreBox is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE).
> Please open an issue to discuss before starting larger work.

## Set up

Requirements: Flutter 3.44.0 (Dart 3.12, the version CI uses), Make and Bash, plus the toolchain of each platform
you build for:

| Platform | Needs |
|---|---|
| macOS, iOS | Xcode and CocoaPods |
| Windows | Visual Studio with the "Desktop development with C++" workload |
| Linux | `clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev` (Debian and Ubuntu names) |
| Android | The Android SDK and NDK, and Java 17 |

```sh
git clone https://github.com/weikxs/timbrebox.git
cd timbrebox
make hooks     # install the pre-commit and commit-msg hooks
make check     # privacy, analysis, formatting and tests of every package
make app       # release build of the desktop app for this machine
```

`make help` lists every target. Run the app with `flutter run -d macos` (or `windows`, `linux`, a device id) in
`apps/timbrebox_app`.

## Workflow

1. Open or pick an issue, and say you are working on it.
2. Create a branch from `main`: `feat/<topic>`, `fix/<topic>`, `docs/<topic>`, …
3. Write a failing test first, then the code that makes it pass.
4. Keep the change focused. Update `CHANGELOG.md` under **Unreleased** for anything users notice.
5. Run `make check`, then open a pull request using the template.

New sources implement the `CatalogSource` adapter contract rather than touching the interface or playback code.

## Commit messages

[Conventional Commits 1.0](https://www.conventionalcommits.org/en/v1.0.0/), enforced by the `commit-msg` hook:

```text
feat(search): page Bilibili results past the first page
fix(player): keep the position when a Bluetooth headset reconnects
```

Commits are authored by you only; do not add tool or bot attribution trailers.

## Test data

Use demo data only: hosts such as `media.example` or `example.org`, the demo user `me` in home paths
(`/Users/me/…`, `/home/me/…`, `C:\Users\me\…`), and tokens generated inside the test. Tests keep their files in
temporary folders they create and never read or write the real app data. **Never put real accounts, cookies,
tokens, private plugin or subscription links, or personal paths in the repository, an issue or a pull request.**
`make privacy` blocks the common cases.

## Security

Report vulnerabilities privately; see [SECURITY.md](SECURITY.md).
