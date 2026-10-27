#!/usr/bin/env bash
# Everything CI's `check` job runs: for each Dart package, dependencies,
# static analysis, formatting and tests. Run it from any directory with
# Flutter on PATH (CI uses the ghcr.io/cirruslabs/flutter image).
#
# On Linux the plugin tests load QuickJS from flutter_js's prebuilt x86_64
# library; LIBQUICKJSC_TEST_PATH points there unless already set.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

readonly PACKAGES=(packages/timbrebox_core packages/timbrebox_cli apps/timbrebox_app)

for package in "${PACKAGES[@]}"; do
  echo "== $package"
  (
    cd "$package"
    if grep -q 'sdk: flutter' pubspec.yaml; then
      flutter pub get
      flutter analyze --no-pub
    else
      dart pub get
      dart analyze --fatal-infos
    fi
    dirs=()
    for dir in bin lib test; do
      [[ -d "$dir" ]] && dirs+=("$dir")
    done
    dart format --output=none --set-exit-if-changed "${dirs[@]}"
    if [[ "$(uname -s)" == Linux && -z "${LIBQUICKJSC_TEST_PATH:-}" ]]; then
      pub_cache="${PUB_CACHE:-$HOME/.pub-cache}"
      library=$(find "$pub_cache/hosted/pub.dev" -path '*flutter_js-*/linux/shared/libquickjs_c_bridge_plugin.so' | sort | tail -1)
      [[ -n "$library" ]] && export LIBQUICKJSC_TEST_PATH="$library"
    fi
    if grep -q 'sdk: flutter' pubspec.yaml; then
      flutter test --no-pub
    else
      dart test
    fi
  )
done
echo "all checks passed"
