#!/bin/sh
# Packages what `flutter build <platform> --release` produced on this machine into a folder, under the
# release's file names:
#   timbrebox_<version>_darwin_universal.dmg                       (macOS)
#   timbrebox_<version>_linux_amd64.deb, _linux_amd64.tar.gz       (Linux x86_64)
#   timbrebox_<version>_windows_amd64.zip                          (Windows x64)
# Fails when the build output is missing, or when the macOS app is not universal.
#
# usage: scripts/release/package-bundles.sh <version> <out>
#   e.g. package-bundles.sh 0.1.0 dist
set -eu

version=${1:?usage: package-bundles.sh <version> <out>}
out=${2:?usage: package-bundles.sh <version> <out>}

cd "$(git rev-parse --show-toplevel)"
readonly APP_DIR=apps/timbrebox_app
readonly ICON="$APP_DIR/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png"
readonly DESKTOP_FILE=packaging/linux/timbrebox.desktop

mkdir -p "$out"
out=$(cd "$out" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

say() { echo "package-bundles: $*"; }
fail() {
	echo "package-bundles: $*" >&2
	exit 1
}

package_macos() {
	app="$APP_DIR/build/macos/Build/Products/Release/TimbreBox.app"
	[ -d "$app" ] || fail "$app is missing; run: cd $APP_DIR && flutter build macos --release"
	archs=$(lipo -archs "$app/Contents/MacOS/TimbreBox")
	for want in x86_64 arm64; do
		case " $archs " in *" $want "*) ;; *) fail "TimbreBox.app is not universal: $archs (no $want)" ;; esac
	done
	mkdir -p "$work/dmg"
	ditto "$app" "$work/dmg/TimbreBox.app"
	ln -s /Applications "$work/dmg/Applications"
	name="timbrebox_${version}_darwin_universal.dmg"
	hdiutil create -quiet -volname TimbreBox -srcfolder "$work/dmg" -ov -format UDZO "$out/$name"
	say "$app -> $out/$name ($archs)"
}

linux_bundle() {
	bundle="$APP_DIR/build/linux/x64/release/bundle"
	[ -x "$bundle/timbrebox_app" ] || fail "$bundle is missing; run: cd $APP_DIR && flutter build linux --release"
	printf '%s\n' "$bundle"
}

# package_deb installs the bundle into /opt/timbrebox, with timbrebox-app on PATH and a menu entry.
# libmpv is loaded at run time (libmpv.so.2 or .so.1), so either package satisfies it.
package_deb() {
	root="$work/deb"
	mkdir -p "$root/DEBIAN" "$root/opt/timbrebox" "$root/usr/bin" "$root/usr/share/applications" \
		"$root/usr/share/icons/hicolor/512x512/apps"
	cp -R "$1/." "$root/opt/timbrebox/"
	ln -s /opt/timbrebox/timbrebox_app "$root/usr/bin/timbrebox-app"
	cp "$DESKTOP_FILE" "$root/usr/share/applications/timbrebox.desktop"
	cp "$ICON" "$root/usr/share/icons/hicolor/512x512/apps/timbrebox.png"
	find "$root" -type d -exec chmod 755 {} +
	find "$root" -type f -exec chmod 644 {} +
	chmod 755 "$root/opt/timbrebox/timbrebox_app"
	size=$(du -sk "$root" | awk '{ print $1 }')
	# A pre-release 0.2.0-rc.1 becomes 0.2.0~rc.1, which Debian sorts before 0.2.0.
	deb_version=$(printf '%s\n' "$version" | sed 's/-/~/')
	cat >"$root/DEBIAN/control" <<EOF
Package: timbrebox
Version: $deb_version
Architecture: amd64
Maintainer: Weikxs <weikxs.dev@gmail.com>
Installed-Size: $size
Depends: libgtk-3-0, libmpv2 | libmpv1
Recommends: zenity
Section: sound
Priority: optional
Homepage: https://github.com/weikxs/timbrebox
Description: Lightweight music player for public music sources
 TimbreBox brings public and open music sources into one calm player,
 with no account and no login flow.
EOF
	name="timbrebox_${version}_linux_amd64.deb"
	dpkg-deb --root-owner-group --build "$root" "$out/$name" >/dev/null
	say "$1 -> $out/$name"
}

# package_tarball keeps the bundle as it is, in a timbrebox folder with the icon and menu entry beside it.
package_tarball() {
	mkdir -p "$work/tar/timbrebox"
	cp -R "$1/." "$work/tar/timbrebox/"
	cp "$ICON" "$work/tar/timbrebox/timbrebox.png"
	cp "$DESKTOP_FILE" "$work/tar/timbrebox/timbrebox.desktop"
	name="timbrebox_${version}_linux_amd64.tar.gz"
	tar -C "$work/tar" -czf "$out/$name" timbrebox
	say "$1 -> $out/$name"
}

package_windows() {
	release="$APP_DIR/build/windows/x64/runner/Release"
	[ -f "$release/timbrebox_app.exe" ] || fail "$release is missing; run: cd $APP_DIR && flutter build windows --release"
	mkdir -p "$work/zip"
	cp -R "$release" "$work/zip/TimbreBox"
	name="timbrebox_${version}_windows_amd64.zip"
	(cd "$work/zip" && pwsh -NoProfile -Command "Compress-Archive -Path TimbreBox -DestinationPath '$name'")
	mv "$work/zip/$name" "$out/$name"
	say "$release -> $out/$name"
}

case "$(uname -s)" in
Darwin) package_macos ;;
Linux)
	[ "$(uname -m)" = x86_64 ] || fail "Linux packages are built on x86_64 only (flutter_js ships no other QuickJS library)"
	bundle=$(linux_bundle)
	package_deb "$bundle"
	package_tarball "$bundle"
	;;
MINGW* | MSYS* | CYGWIN*) package_windows ;;
*) fail "unsupported system $(uname -s)" ;;
esac
