#!/bin/sh
# Checks a release tag before anything is built: the tag's version matches the app's version in
# apps/timbrebox_app/pubspec.yaml (without its +build number), and the release notes
# .github/release-notes/<tag>.md exist and have no TODO left (draft them with scripts/release-notes.sh).
# Writes version, base and prerelease to $GITHUB_OUTPUT when set.
#
# usage: scripts/release/check-release.sh v0.1.0 | v0.1.0-rc.1
set -eu

tag=${1:?usage: check-release.sh <tag>}
fail() {
	echo "check-release: $*" >&2
	exit 1
}

version=${tag#v}
case "$tag" in
v[0-9]*.[0-9]*.[0-9]*-rc.[0-9]*) prerelease=true ;;
v[0-9]*.[0-9]*.[0-9]*) prerelease=false ;;
*) fail "$tag is not a release tag (vX.Y.Z or vX.Y.Z-rc.N)" ;;
esac
base=${version%%-*}
printf '%s\n' "$base" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "$tag is not a release tag (vX.Y.Z or vX.Y.Z-rc.N)"

pubspec=apps/timbrebox_app/pubspec.yaml
app=$(sed -n 's/^version: *\([^+ ]*\).*/\1/p' "$pubspec")
[ "$app" = "$base" ] || fail "$pubspec has version '$app', the tag says $base"

notes=".github/release-notes/$tag.md"
[ -f "$notes" ] || fail "$notes is missing; draft it with scripts/release-notes.sh $tag > $notes"
if grep -n "TODO" "$notes" >&2; then fail "$notes still has TODO placeholders"; fi
head -n 1 "$notes" | grep -q "^# TimbreBox $tag — " || fail "$notes does not start with '# TimbreBox $tag — <theme>'"

echo "check-release: $tag OK (version $base, prerelease $prerelease)"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
	{
		echo "version=$version"
		echo "base=$base"
		echo "prerelease=$prerelease"
	} >>"$GITHUB_OUTPUT"
fi
