#!/bin/sh
# Drafts the release notes of one version from its section of CHANGELOG.md,
# in the layout of .github/release-notes/TEMPLATE.md:
#
#   scripts/release-notes.sh v0.2.0 > .github/release-notes/v0.2.0.md
#
# The draft fills in what the changelog knows (date, summary, upgrading
# steps, new features, changes, fixes, security, downloads, links) and
# leaves TODO comments where a person writes: the theme, who the release is
# for and what you can do now. Sections with nothing to say are left out.
# The release workflow publishes the edited file, not this draft. A
# pre-release (v0.2.0-rc.1) is drafted from its version's section (0.2.0).
# Fails when the changelog has no section for the version.
#
# usage: scripts/release-notes.sh <tag> [CHANGELOG.md]
set -eu

tag=${1:?usage: release-notes.sh <tag> [changelog]}
changelog=${2:-CHANGELOG.md}
version=${tag#v}
repo=https://github.com/weikxs/timbrebox

# trim drops leading and trailing blank lines.
trim() { sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}'; }

# A pre-release without a section of its own uses its version's section.
if ! grep -q "^## \[$version\]" "$changelog"; then version=${version%%-*}; fi

# section prints the lines under "### $1" in this version's section.
section() {
	awk -v version="$version" -v want="$1" '
		/^## \[/ { inside = index($0, "## [" version "]") == 1; next }
		!inside { next }
		/^### / { current = substr($0, 5); next }
		current == want { print }
	' "$changelog" | trim
}

# block prints a heading and the CHANGELOG category, unless it is empty.
block() {
	body=$(section "$2")
	if [ -n "$body" ]; then printf '%s\n%s\n\n' "$1" "$body"; fi
}

heading=$(grep -m1 "^## \[$version\]" "$changelog" || true)
if [ -z "$heading" ]; then
	echo "release-notes: CHANGELOG has no section for $version" >&2
	exit 1
fi
date=${heading##* - }
case "$date" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) date=TODO ;; esac
summary=$(awk -v version="$version" '
	/^## \[/ { inside = index($0, "## [" version "]") == 1; next }
	inside && /^### / { exit }
	inside { print }
' "$changelog" | trim)
# The version released before this one: the next section below it.
previous=$(awk -v version="$version" '
	/^## \[/ { if (found) { sub(/^## \[/, ""); sub(/\].*/, ""); print; exit } if (index($0, "## [" version "]") == 1) found = 1 }
' "$changelog")
files=${tag#v}
upgrading=$(section Upgrading)
removed=$(section Removed)
deprecated=$(section Deprecated)

cat <<EOF
# TimbreBox $tag — <!-- TODO: one-line theme -->

Released on \`$date\`.

> TimbreBox is a lightweight music player that brings public music sources into one calm place: search once, play
> from open archives, radio and video platforms, with no account and no login flow.

## Summary

${summary:-<!-- TODO: two or three sentences: what this release is about and what changes for you. -->}

## Who this release is for

<!-- TODO: the person this release helps most, specifically. -->

EOF
if [ -n "$upgrading$removed$deprecated" ]; then
	printf '## Before you upgrade\n\n'
	if [ -n "$upgrading" ]; then printf '%s\n\n' "$upgrading"; fi
	block "### Removed" Removed
	block "### Deprecated" Deprecated
fi
cat <<EOF
## What you can do now

<!-- TODO: 3–6 short paragraphs, one per capability, from the reader's side. -->

EOF
if [ -n "$(section Added)$(section Changed)" ]; then
	printf "## What's new\n\n"
	block "### New" Added
	block "### Changed" Changed
fi
block "## Bug fixes" Fixed
cat <<EOF
## Privacy and security

EOF
security=$(section Security)
if [ -n "$security" ]; then printf '%s\n' "$security"; fi
cat <<EOF
- **No account, no telemetry.** TimbreBox never asks for, collects or stores source accounts, cookies, API keys or
  device IDs; anonymous temporary cookies live in memory and are cleared on exit. Nothing is reported anywhere.
- **Your library stays on your computer.** Favorites, playlists, history, downloads and settings are saved in the
  app's own folder; the download index holds only file names inside the download folder.
- **Plugins run in a sandbox.** A plugin's script gets HTTP and nothing else — no files, processes or sockets — and
  every connection it makes is checked; mobile builds never download or run plugin code.
- **Local control stays local.** The control API listens on \`127.0.0.1\` only, refuses web pages, and needs a
  per-run token from a file only your account can read.

## Install

- Script (macOS and Linux x86_64, fully automatic): \`curl -fsSL https://raw.githubusercontent.com/weikxs/timbrebox/main/install.sh | sh\`
- Homebrew (macOS): \`brew install --cask weikxs/tap/timbrebox\`, or \`brew upgrade --cask timbrebox\`
- A package below; check it against \`checksums.txt\`

| File | Platform |
|---|---|
| \`timbrebox_${files}_darwin_universal.dmg\` | macOS 10.15 or newer, Apple silicon and Intel |
| \`timbrebox_${files}_linux_amd64.deb\` | Debian 12+, Ubuntu 22.04+ and their relatives (x86_64) |
| \`timbrebox_${files}_linux_amd64.tar.gz\` | Other Linux distributions with glibc, GTK 3 and libmpv (x86_64) |
| \`timbrebox_${files}_windows_amd64.zip\` | Windows 10 and 11 (x64): unzip and start \`timbrebox_app.exe\` |

## Compatibility

- macOS 10.15 (Catalina) or newer on Apple silicon and Intel.
- Linux with glibc on x86_64: Ubuntu 22.04+, Debian 12+ and their relatives through the \`.deb\`; other
  distributions through the \`.tar.gz\`, with GTK 3 and libmpv from the distribution.
- Windows 10 and 11 on x64.
- Android and iOS are not part of the release packages; build them from source (see the README).
- English and Simplified Chinese.

## Notes

- The macOS app is not signed or notarized by Apple, and there are no plans to sign it. Homebrew and the install
  script handle this for you. If you open the disk image by hand, open TimbreBox once, then choose **Open Anyway** in
  System Settings → Privacy & Security, or run \`xattr -dr com.apple.quarantine /Applications/TimbreBox.app\`. See
  [SECURITY.md]($repo/blob/$tag/SECURITY.md#release-packages-and-macos).
- The Windows app is not signed either: if SmartScreen stops it, choose **More info** → **Run anyway**.
EOF
if [ -n "$previous" ]; then
	printf -- '- **Full changelog:** [v%s...%s](%s/compare/v%s...%s) · [CHANGELOG.md](%s/blob/%s/CHANGELOG.md)\n' \
		"$previous" "$tag" "$repo" "$previous" "$tag" "$repo" "$tag"
else
	printf -- '- **Full changelog:** [CHANGELOG.md](%s/blob/%s/CHANGELOG.md)\n' "$repo" "$tag"
fi
cat <<EOF
- Documentation: [README]($repo#readme) · [简体中文]($repo/blob/main/README.zh-CN.md)
- Feedback and problems: [issues]($repo/issues).
EOF
