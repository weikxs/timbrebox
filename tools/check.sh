#!/usr/bin/env bash
# Everything CI's `check` job runs: for each Dart package, dependencies,
# static analysis, formatting and tests. Run it from any directory with
# Flutter on PATH (CI uses the ghcr.io/cirruslabs/flutter image).
#
#   tools/check.sh                  analyze, format and test every package
#   tools/check.sh analyze test     only these steps (analyze, format, test)
#
# On Linux the plugin tests load QuickJS from flutter_js's prebuilt x86_64
# library; LIBQUICKJSC_TEST_PATH points there unless already set.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

readonly PACKAGES=(packages/timbrebox_core packages/timbrebox_sources packages/timbrebox_playback packages/timbrebox_cli apps/timbrebox_app)
readonly ALL_STEPS=(analyze format test)

steps=("$@")
[[ ${#steps[@]} -gt 0 ]] || steps=("${ALL_STEPS[@]}")
for step in "${steps[@]}"; do
  case "$step" in
    analyze | format | test) ;;
    *)
      echo "check: unknown step '$step' (expected: ${ALL_STEPS[*]})" >&2
      exit 64
      ;;
  esac
done

wants() {
  local step
  for step in "${steps[@]}"; do
    [[ "$step" == "$1" ]] && return 0
  done
  return 1
}

is_flutter() {
  grep -q 'sdk: flutter' pubspec.yaml
}

dependencies() {
  if is_flutter; then flutter pub get; else dart pub get; fi
}

analyze() {
  if is_flutter; then flutter analyze --no-pub; else dart analyze --fatal-infos; fi
}

format() {
  local dirs=() dir
  for dir in bin lib test; do
    [[ -d "$dir" ]] && dirs+=("$dir")
  done
  dart format --output=none --set-exit-if-changed "${dirs[@]}"
}

run_tests() {
  if [[ "$(uname -s)" == Linux && -z "${LIBQUICKJSC_TEST_PATH:-}" ]]; then
    local pub_cache="${PUB_CACHE:-$HOME/.pub-cache}" library
    library=$(find "$pub_cache/hosted/pub.dev" -path '*flutter_js-*/linux/shared/libquickjs_c_bridge_plugin.so' | sort | tail -1)
    [[ -n "$library" ]] && export LIBQUICKJSC_TEST_PATH="$library"
  fi
  if is_flutter; then flutter test --no-pub; else dart test; fi
}

for package in "${PACKAGES[@]}"; do
  echo "== $package"
  (
    cd "$package"
    if wants analyze || wants test; then dependencies; fi
    if wants analyze; then analyze; fi
    if wants format; then format; fi
    if wants test; then run_tests; fi
  )
done
echo "all checks passed (${steps[*]})"
