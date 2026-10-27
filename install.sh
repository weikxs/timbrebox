#!/bin/sh
# TimbreBox installer for macOS and Linux (x86_64).
#
#   curl -fsSL https://raw.githubusercontent.com/weikxs/timbrebox/main/install.sh | sh
#
# It picks the package for this system, downloads it from the GitHub release,
# checks it against the release's checksums.txt and installs it:
#   macOS          TimbreBox.app into /Applications (or ~/Applications)
#   Debian, Ubuntu the .deb, with apt (asks for sudo)
#   other Linux    the .tar.gz, into ~/.local/share/timbrebox, as timbrebox-app in ~/.local/bin,
#                  with a menu entry (libmpv and GTK 3 come from your distribution)
# Nothing else is changed. Your favorites, playlists, downloads and settings are
# never touched: they stay in TimbreBox's data folder whatever you install,
# upgrade or remove.
#
# Options (or the environment variables in brackets):
#   --version <tag>     install this release, such as v0.1.0 [TIMBREBOX_VERSION]; default: the latest
#   --format <format>   Linux only: deb or tar [TIMBREBOX_FORMAT]; default: what this system uses
#   --dir <directory>   macOS: where TimbreBox.app goes; tar: where timbrebox-app goes [TIMBREBOX_INSTALL_DIR]
#   --no-modify-path    tar: do not add the directory to your shell's startup file [TIMBREBOX_NO_MODIFY_PATH=1]
#   --help              show this help
#
# Run it again to upgrade.
set -eu

REPO="weikxs/timbrebox"
BASE_URL="${TIMBREBOX_BASE_URL:-https://github.com/$REPO/releases}"
PATH_MARK="# Added by the TimbreBox installer"
APP_COMMAND="timbrebox-app"

say() { printf 'timbrebox-install: %s\n' "$*"; }
fail() {
	printf 'timbrebox-install: error: %s\n' "$*" >&2
	exit 1
}

usage() {
	cat <<'EOF'
TimbreBox installer for macOS and Linux (x86_64).

  curl -fsSL https://raw.githubusercontent.com/weikxs/timbrebox/main/install.sh | sh
  curl -fsSL https://raw.githubusercontent.com/weikxs/timbrebox/main/install.sh | sh -s -- [options]

Options (or environment variables):
  --version <tag>     install this release, such as v0.1.0 (TIMBREBOX_VERSION); default: the latest
  --format <format>   Linux only: deb or tar (TIMBREBOX_FORMAT); default: what this system uses
  --dir <directory>   macOS: where TimbreBox.app goes; tar: where timbrebox-app goes (TIMBREBOX_INSTALL_DIR)
  --no-modify-path    tar: do not add the directory to your shell's startup file (TIMBREBOX_NO_MODIFY_PATH=1)
  --help              show this help

Run it again to upgrade. Your library and settings are never touched.
EOF
}

parse_args() {
	version="${TIMBREBOX_VERSION:-}"
	format="${TIMBREBOX_FORMAT:-}"
	install_dir="${TIMBREBOX_INSTALL_DIR:-}"
	modify_path=1
	[ "${TIMBREBOX_NO_MODIFY_PATH:-}" = "1" ] && modify_path=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--version) [ $# -ge 2 ] || fail "--version needs a tag, such as v0.1.0"; version="$2"; shift 2 ;;
		--version=*) version="${1#*=}"; shift ;;
		--format) [ $# -ge 2 ] || fail "--format needs deb or tar"; format="$2"; shift 2 ;;
		--format=*) format="${1#*=}"; shift ;;
		--dir) [ $# -ge 2 ] || fail "--dir needs a directory"; install_dir="$2"; shift 2 ;;
		--dir=*) install_dir="${1#*=}"; shift ;;
		--no-modify-path) modify_path=0; shift ;;
		-h | --help) usage; exit 0 ;;
		*) fail "unknown option: $1 (see --help)" ;;
		esac
	done
	case "$version" in
	"" | v[0-9]*.[0-9]*.[0-9]*) ;;
	[0-9]*.[0-9]*.[0-9]*) version="v$version" ;;
	*) fail "not a release tag: $version (expected something like v0.1.0)" ;;
	esac
	case "$format" in
	"" | deb | tar) ;;
	tar.gz | tgz) format=tar ;;
	*) fail "unknown format: $format (expected deb or tar)" ;;
	esac
}

detect_platform() {
	case "$(uname -s)" in
	Darwin) os=darwin ;;
	Linux) os=linux ;;
	*) fail "$(uname -s) is not supported by this script; Windows users download the .zip from the release page" ;;
	esac
	if [ "$os" = linux ]; then
		case "$(uname -m)" in
		x86_64 | amd64) ;;
		*) fail "$(uname -m) CPUs are not supported on Linux; TimbreBox for Linux runs on x86_64" ;;
		esac
	fi
	[ "$os" = darwin ] && [ -n "$format" ] && fail "--format is for Linux; macOS always gets TimbreBox.app"
	return 0
}

detect_tools() {
	if command -v curl >/dev/null 2>&1; then
		downloader=curl
	elif command -v wget >/dev/null 2>&1; then
		downloader=wget
	else
		fail "curl or wget is needed to download TimbreBox"
	fi
	if command -v sha256sum >/dev/null 2>&1; then
		hasher="sha256sum"
	elif command -v shasum >/dev/null 2>&1; then
		hasher="shasum -a 256"
	else
		fail "sha256sum or shasum is needed to check the download"
	fi
}

# Releases are only fetched over HTTPS; a plain http:// TIMBREBOX_BASE_URL (a test server) is the only exception.
secure() {
	case "$BASE_URL" in https://*) return 0 ;; esac
	return 1
}

# download URL FILE
download() {
	if [ "$downloader" = curl ]; then
		if secure; then
			curl --proto '=https' --tlsv1.2 -fsSL --retry 3 -o "$2" "$1"
		else
			curl -fsSL --retry 3 -o "$2" "$1"
		fi
	else
		wget -q -O "$2" "$1"
	fi
}

# latest_version prints the tag of the newest release, read from where
# releases/latest redirects (no API call, so no rate limit).
latest_version() {
	if [ "$downloader" = curl ]; then
		url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$BASE_URL/latest")
	else
		url=$(wget -S --spider "$BASE_URL/latest" 2>&1 | sed -n 's/^ *[Ll]ocation: *//p' | tail -n 1 | tr -d '\r')
	fi
	tag="${url##*/}"
	case "$tag" in
	v[0-9]*.[0-9]*.[0-9]*) printf '%s\n' "$tag" ;;
	*) fail "could not find the latest release at $BASE_URL/latest" ;;
	esac
}

# choose_format picks deb or tar for this Linux, unless --format chose one.
choose_format() {
	if ldd --version 2>&1 | grep -qi musl; then
		fail "this Linux uses musl (such as Alpine); TimbreBox needs a glibc-based distribution"
	fi
	if [ -n "$format" ]; then return 0; fi
	if command -v apt-get >/dev/null 2>&1 && command -v dpkg >/dev/null 2>&1; then
		format=deb
	else
		format=tar
	fi
}

asset_name() {
	v="${version#v}"
	if [ "$os" = darwin ]; then
		printf 'timbrebox_%s_darwin_universal.dmg\n' "$v"
		return
	fi
	case "$format" in
	deb) printf 'timbrebox_%s_linux_amd64.deb\n' "$v" ;;
	tar) printf 'timbrebox_%s_linux_amd64.tar.gz\n' "$v" ;;
	esac
}

# fetch_and_verify downloads the package and checksums.txt into $tmp and
# stops unless the package's SHA-256 matches its line in checksums.txt.
fetch_and_verify() {
	file=$(asset_name)
	say "downloading $file ($version)"
	download "$BASE_URL/download/$version/$file" "$tmp/$file" ||
		fail "could not download $file; is $version a TimbreBox release?"
	download "$BASE_URL/download/$version/checksums.txt" "$tmp/checksums.txt" ||
		fail "could not download checksums.txt for $version"
	expected=$(awk -v f="$file" '$2 == f || $2 == "*" f { print $1 }' "$tmp/checksums.txt")
	[ -n "$expected" ] || fail "checksums.txt has no entry for $file"
	actual=$(cd "$tmp" && $hasher "$file" | awk '{ print $1 }')
	[ "$expected" = "$actual" ] || fail "checksum mismatch for $file (expected $expected, got $actual); nothing was installed"
	say "checksum OK"
}

# as_root runs a command as root: directly when already root, otherwise with sudo.
as_root() {
	if [ "$(id -u)" = 0 ]; then
		"$@"
	elif command -v sudo >/dev/null 2>&1; then
		sudo "$@"
	else
		fail "installing a system package needs root; run as root, install sudo, or use --format tar"
	fi
}

install_deb() {
	command -v apt-get >/dev/null 2>&1 || fail "apt-get is needed for the .deb; use --format tar instead"
	[ "$(id -u)" = 0 ] || say "installing the .deb with apt; sudo may ask for your password"
	as_root apt-get install -y "$tmp/$file" || fail "apt could not install $file"
}

# expand_dir makes a --dir value absolute.
expand_dir() {
	case "$1" in
	"~"/*) printf '%s\n' "$HOME/${1#"~/"}" ;;
	/*) printf '%s\n' "$1" ;;
	*) printf '%s\n' "$(pwd)/$1" ;;
	esac
}

install_tar() {
	if [ "$(id -u)" = 0 ]; then
		share=/usr/local/share
		[ -n "$install_dir" ] || install_dir=/usr/local/bin
	else
		share="${XDG_DATA_HOME:-$HOME/.local/share}"
		[ -n "$install_dir" ] || install_dir="$HOME/.local/bin"
	fi
	install_dir=$(expand_dir "$install_dir")
	mkdir -p "$install_dir" "$share" || fail "cannot create $install_dir or $share"
	[ -w "$install_dir" ] || fail "$install_dir is not writable; choose another with --dir, or run as root"
	tar -xzf "$tmp/$file" -C "$tmp" || fail "could not unpack $file"
	[ -x "$tmp/timbrebox/timbrebox_app" ] || fail "$file has no timbrebox/timbrebox_app"
	# Unpack next to the target, then swap, so an interrupted install never leaves half an app.
	rm -rf "$share/.timbrebox.new"
	cp -R "$tmp/timbrebox" "$share/.timbrebox.new" || fail "cannot write to $share"
	rm -rf "$share/timbrebox"
	mv "$share/.timbrebox.new" "$share/timbrebox"
	ln -sf "$share/timbrebox/timbrebox_app" "$install_dir/$APP_COMMAND"
	add_menu_entry
	# The app loads libmpv when it plays the first track; it and GTK 3 come from the distribution.
	if ! { ldconfig -p 2>/dev/null | grep -Eq 'libmpv\.so\.[12] '; }; then
		say "note: libmpv was not found; install your distribution's libmpv package (such as libmpv2 or mpv-libs)"
	fi
	if ! { ldconfig -p 2>/dev/null | grep -q 'libgtk-3\.so\.0 '; }; then
		say "note: GTK 3 was not found; install your distribution's GTK 3 package (such as libgtk-3-0 or gtk3)"
	fi
	ensure_path
}

# add_menu_entry puts TimbreBox, with its icon, in the desktop's applications menu.
add_menu_entry() {
	mkdir -p "$share/applications" "$share/icons/hicolor/512x512/apps"
	cp "$share/timbrebox/timbrebox.png" "$share/icons/hicolor/512x512/apps/timbrebox.png"
	sed "s|^Exec=.*|Exec=$install_dir/$APP_COMMAND|" "$share/timbrebox/timbrebox.desktop" \
		>"$share/applications/timbrebox.desktop"
	say "added TimbreBox to the applications menu"
}

on_path() {
	case ":${PATH:-}:" in *":$1:"*) return 0 ;; esac
	return 1
}

# startup_file prints the file the login shell reads for PATH.
startup_file() {
	case "$(basename "${SHELL:-sh}")" in
	zsh) printf '%s\n' "${ZDOTDIR:-$HOME}/.zshrc" ;;
	bash) printf '%s\n' "$HOME/.bashrc" ;;
	fish) printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/timbrebox-path.fish" ;;
	*) printf '%s\n' "$HOME/.profile" ;;
	esac
}

ensure_path() {
	if on_path "$install_dir"; then return 0; fi
	if [ "$modify_path" = 0 ]; then
		say "$install_dir is not on your PATH; add it to start \`$APP_COMMAND\` by name"
		return 0
	fi
	rc=$(startup_file)
	if [ -f "$rc" ] && grep -qF "$PATH_MARK" "$rc"; then
		say "$rc already adds the install directory to PATH; open a new terminal"
		return 0
	fi
	mkdir -p "$(dirname "$rc")"
	case "$rc" in
	*.fish) line="fish_add_path -g \"$install_dir\"" ;;
	*) line="export PATH=\"$install_dir:\$PATH\"" ;;
	esac
	printf '\n%s\n%s\n' "$PATH_MARK" "$line" >>"$rc"
	say "added $install_dir to PATH in $rc; open a new terminal (or run: $line)"
}

install_mac() {
	command -v hdiutil >/dev/null 2>&1 || fail "hdiutil is needed to open the disk image"
	if pgrep -x TimbreBox >/dev/null 2>&1; then
		fail "TimbreBox is running; quit it (TimbreBox → Quit TimbreBox), then run the installer again"
	fi
	if [ -z "$install_dir" ]; then
		if [ -w /Applications ]; then install_dir=/Applications; else install_dir="$HOME/Applications"; fi
	fi
	install_dir=$(expand_dir "$install_dir")
	mkdir -p "$install_dir" || fail "cannot create $install_dir"
	[ -w "$install_dir" ] || fail "$install_dir is not writable; choose another with --dir"
	mount="$tmp/mount"
	mkdir -p "$mount"
	hdiutil attach -nobrowse -readonly -quiet -mountpoint "$mount" "$tmp/$file" || fail "could not open $file"
	mounted=1
	[ -d "$mount/TimbreBox.app" ] || fail "$file has no TimbreBox.app"
	# Copy next to the target, then swap, so an interrupted install never leaves half an app.
	rm -rf "$install_dir/.TimbreBox.app.new"
	ditto "$mount/TimbreBox.app" "$install_dir/.TimbreBox.app.new" || fail "cannot write to $install_dir"
	hdiutil detach -quiet "$mount" && mounted=0
	# Downloaded by this script, not a browser: no "downloaded from the internet" prompt.
	xattr -dr com.apple.quarantine "$install_dir/.TimbreBox.app.new" 2>/dev/null || true
	rm -rf "$install_dir/TimbreBox.app"
	mv "$install_dir/.TimbreBox.app.new" "$install_dir/TimbreBox.app"
	app="$install_dir/TimbreBox.app"
}

# check_installed confirms the app is where it should be.
check_installed() {
	if [ "$os" = darwin ]; then
		[ -x "$app/Contents/MacOS/TimbreBox" ] || fail "TimbreBox.app was copied but its program is missing"
		say "installed TimbreBox ${version#v} to $app"
		say "done. Start it from Launchpad or with: open \"$app\""
		return
	fi
	case "$format" in
	deb)
		found=$(command -v "$APP_COMMAND" 2>/dev/null || true)
		[ -n "$found" ] || fail "the package was installed but $APP_COMMAND is not on PATH"
		say "installed TimbreBox ${version#v} (deb) as $found"
		;;
	tar)
		[ -x "$install_dir/$APP_COMMAND" ] || fail "the archive was not installed"
		say "installed TimbreBox ${version#v} (tar) as $install_dir/$APP_COMMAND"
		;;
	esac
	say "done. Start it from your applications menu or with: $APP_COMMAND"
}

cleanup() {
	if [ "${mounted:-0}" = 1 ]; then hdiutil detach -quiet -force "$mount" 2>/dev/null || true; fi
	rm -rf "$tmp"
}

main() {
	parse_args "$@"
	detect_platform
	detect_tools
	[ "$os" = linux ] && choose_format
	[ -n "$version" ] || version=$(latest_version)
	tmp=$(mktemp -d 2>/dev/null || mktemp -d -t timbrebox)
	mounted=0
	trap cleanup EXIT INT TERM
	fetch_and_verify
	if [ "$os" = darwin ]; then
		install_mac
	else
		case "$format" in
		deb) install_deb ;;
		tar) install_tar ;;
		esac
	fi
	check_installed
}

main "$@"
