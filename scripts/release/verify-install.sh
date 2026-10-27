#!/bin/sh
# Installs freshly built packages with the real install.sh, from a local stand-in for the GitHub release,
# then starts the installed app and checks it keeps running. Used by the release workflow on each build
# machine before anything is published.
#
# usage: scripts/release/verify-install.sh <tag> <folder with the release files> macos|deb|tar
set -eu

tag=${1:?usage: verify-install.sh <tag> <dist> <mode>}
dist=${2:?dist}
mode=${3:?mode}
version=${tag#v}
RUN_SECONDS=15
PORT=8765
# The oldest macOS the app supports (MACOSX_DEPLOYMENT_TARGET of the Xcode project and the Podfile).
MACOS_MIN=10.15

work=$(mktemp -d)
server=""
cleanup() {
	[ -z "$server" ] || kill "$server" 2>/dev/null || true
	rm -rf "$work"
}
trap cleanup EXIT INT TERM
say() { echo "verify-install: $*"; }
fail() {
	echo "verify-install: FAILED: $*" >&2
	exit 1
}

# The release as install.sh sees it: <base>/download/<tag>/<file> and checksums.txt.
mkdir -p "$work/release/download/$tag"
cp "$dist"/timbrebox_* "$work/release/download/$tag/"
(cd "$work/release/download/$tag" && { sha256sum timbrebox_* 2>/dev/null || shasum -a 256 timbrebox_*; } >checksums.txt)
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$work/release" >/dev/null 2>&1 &
server=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
	curl -fs -o /dev/null "http://127.0.0.1:$PORT/download/$tag/checksums.txt" && break
	sleep 1
done
export TIMBREBOX_BASE_URL="http://127.0.0.1:$PORT"

# runs keeps the app running for RUN_SECONDS; it must not exit before.
runs() {
	"$@" >"$work/app.log" 2>&1 &
	app=$!
	sleep "$RUN_SECONDS"
	if kill -0 "$app" 2>/dev/null; then
		kill "$app" 2>/dev/null || true
		say "the app started and kept running for ${RUN_SECONDS}s"
	else
		cat "$work/app.log" >&2
		fail "the app exited within ${RUN_SECONDS}s"
	fi
}

case "$mode" in
macos)
	apps="$work/Applications"
	sh ./install.sh --version "$tag" --dir "$apps"
	app="$apps/TimbreBox.app"
	archs=$(lipo -archs "$app/Contents/MacOS/TimbreBox")
	for want in x86_64 arm64; do
		case " $archs " in *" $want "*) ;; *) fail "not universal: $archs (no $want)" ;; esac
	done
	minos=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$app/Contents/Info.plist")
	[ "$minos" = "$MACOS_MIN" ] || fail "LSMinimumSystemVersion is $minos, expected $MACOS_MIN"
	[ -z "$(xattr -p com.apple.quarantine "$app" 2>/dev/null || true)" ] || fail "the quarantine flag is still set"
	say "TimbreBox.app is universal ($archs), needs macOS $minos, no quarantine flag"
	runs "$app/Contents/MacOS/TimbreBox"
	;;
deb)
	sh ./install.sh --version "$tag" --format deb
	dpkg -s timbrebox | grep -q "^Version: ${version%%-*}" || fail "dpkg does not list timbrebox ${version%%-*}"
	missing=$(ldd /opt/timbrebox/timbrebox_app | grep "not found" || true)
	[ -z "$missing" ] || fail "missing libraries: $missing"
	ldconfig -p | grep -Eq 'libmpv\.so\.[12] ' || fail "the package did not bring libmpv"
	runs dbus-run-session -- xvfb-run -a timbrebox-app
	;;
tar)
	sh ./install.sh --version "$tag" --format tar --no-modify-path
	# Where install.sh puts it: for root /usr/local, otherwise the user's own folders.
	if [ "$(id -u)" = 0 ]; then
		bin=/usr/local/bin/timbrebox-app share=/usr/local/share
	else
		bin="$HOME/.local/bin/timbrebox-app" share="${XDG_DATA_HOME:-$HOME/.local/share}"
	fi
	[ -x "$bin" ] || fail "$bin was not installed"
	grep -q "^Icon=timbrebox$" "$share/applications/timbrebox.desktop" || fail "the menu entry has no icon"
	grep -q "^Exec=$bin$" "$share/applications/timbrebox.desktop" || fail "the menu entry does not start $bin"
	runs dbus-run-session -- xvfb-run -a "$bin"
	;;
*) fail "unknown mode $mode (macos, deb or tar)" ;;
esac
say "$mode OK for $tag"
