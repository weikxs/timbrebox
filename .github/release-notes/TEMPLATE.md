<!--
  Release notes template, in the layout of the other weikxs projects (see
  https://github.com/weikxs/otpkeep/releases/tag/v0.1.0); keep every release in
  the same order and voice.

  One file per release: .github/release-notes/vX.Y.Z.md (a pre-release such as
  vX.Y.Z-rc.1 has its own file too). The release workflow publishes it, word
  for word, as the GitHub release page, and stops when the file is missing or
  still contains TODO. Draft one from the changelog:

      scripts/release-notes.sh vX.Y.Z > .github/release-notes/vX.Y.Z.md

  Voice: product communication for people deciding whether to install or
  upgrade, not a developer changelog (CHANGELOG.md is that). Speak to "you",
  say what the reader notices, not how it was built. No commit hashes, author
  emails, real names, companies or local paths; examples use demo data
  (docs/development/standards.md, section 4).

  Sections marked "(only when …)" are left out when they have nothing to say.
  Every other section is always there. Delete these comments when done.
-->

# TimbreBox vX.Y.Z — One-line theme

Released on `YYYY-MM-DD`.

> TimbreBox is a lightweight music player that brings public music sources into one calm place: search once, play
> from open archives, radio and video platforms, with no account and no login flow.

## Summary

<!-- Two or three sentences: what this release is, what changes for you, which systems it runs on. -->

## Who this release is for

<!--
  One or two sentences naming the person it helps most, specifically, then an
  "If you have ever:" list of 3–5 real moments, then one sentence on how this
  release changes them.
-->

## Before you upgrade

<!-- (only when you must act) Changes to saved data, settings or shortcuts, steps to run after upgrading, in order. -->

## What you can do now

<!--
  3–6 short paragraphs, one per capability. Each starts with a bold verb
  phrase and ends with the moment you notice it.
-->

## What's new

<!--
  Grouped by theme, one "###" per theme (for example: Playback, Sources and
  search, Plugins, Agent control, Look and feel). Each item: a bold lead, what
  it does, and its boundary (what it does not do).
-->

### Theme

- **Lead.** What it does, and what it does not do.

## Bug fixes

<!-- (only when there are fixes) One line each, in the reader's words: what went wrong, and that it no longer does. -->

## Privacy and security

<!--
  Always present, even when nothing changed. Keep the four promises, then add
  this release's security fixes with their severity (and advisory ID).
-->

- **No account, no telemetry.** TimbreBox never asks for, collects or stores source accounts, cookies, API keys or
  device IDs; anonymous temporary cookies live in memory and are cleared on exit. Nothing is reported anywhere.
- **Your library stays on your computer.** Favorites, playlists, history, downloads and settings are saved in the
  app's own folder; the download index holds only file names inside the download folder.
- **Plugins run in a sandbox.** A plugin's script gets HTTP and nothing else — no files, processes or sockets — and
  every connection it makes is checked, on desktop and mobile alike.
- **Local control stays local.** The control API listens on `127.0.0.1` only, refuses web pages, and needs a
  per-run token from a file only your account can read.

## Install

- Script (macOS and Linux x86_64, fully automatic): `curl -fsSL https://raw.githubusercontent.com/weikxs/timbrebox/main/install.sh | sh`
- Homebrew (macOS): `brew install --cask weikxs/tap/timbrebox`, or `brew upgrade --cask timbrebox`
- A package below; check it against `checksums.txt`

| File | Platform |
|---|---|
| `timbrebox_X.Y.Z_darwin_universal.dmg` | macOS 10.15 or newer, Apple silicon and Intel |
| `timbrebox_X.Y.Z_linux_amd64.deb` | Debian 12+, Ubuntu 22.04+ and their relatives (x86_64) |
| `timbrebox_X.Y.Z_linux_amd64.tar.gz` | Other Linux distributions with glibc, GTK 3 and libmpv (x86_64) |
| `timbrebox_X.Y.Z_windows_amd64.zip` | Windows 10 and 11 (x64): unzip and start `timbrebox_app.exe` |

## Compatibility

- macOS 10.15 (Catalina) or newer on Apple silicon and Intel.
- Linux with glibc on x86_64: Ubuntu 22.04+, Debian 12+ and their relatives through the `.deb`; other
  distributions through the `.tar.gz`, with GTK 3 and libmpv from the distribution.
- Windows 10 and 11 on x64.
- Android and iOS are not part of the release packages; build them from source (see the README).
- English and Simplified Chinese.

## What's coming next

<!-- (only when there is a plan to share) One or two themes of the next release, without dates. -->

## Notes

- The macOS app is not signed or notarized by Apple, and there are no plans to sign it. Homebrew and the install
  script handle this for you. If you open the disk image by hand, open TimbreBox once, then choose **Open Anyway** in
  System Settings → Privacy & Security, or run `xattr -dr com.apple.quarantine /Applications/TimbreBox.app`. See
  [SECURITY.md](https://github.com/weikxs/timbrebox/blob/vX.Y.Z/SECURITY.md#release-packages-and-macos).
- The Windows app is not signed either: if SmartScreen stops it, choose **More info** → **Run anyway**.
- **Full changelog:** [vA.B.C...vX.Y.Z](https://github.com/weikxs/timbrebox/compare/vA.B.C...vX.Y.Z) ·
  [CHANGELOG.md](https://github.com/weikxs/timbrebox/blob/vX.Y.Z/CHANGELOG.md)
- Documentation: [README](https://github.com/weikxs/timbrebox#readme) ·
  [简体中文](https://github.com/weikxs/timbrebox/blob/main/README.zh-CN.md)
- Feedback and problems: [issues](https://github.com/weikxs/timbrebox/issues).
