#!/bin/sh
# Optional local-test components only. Never download or relax app entitlements.
set -eu
CONTENTS="${TARGET_BUILD_DIR:?}/${CONTENTS_FOLDER_PATH:?}"
case "$CONTENTS" in */TimbreBox.app/Contents) ;; *) exit 1 ;; esac
HELPER="$CONTENTS/Helpers/TimbreBoxMedia.app"
RESOURCES="$CONTENTS/Resources/TimbreBoxMedia"
SOURCE="${TIMBREBOX_PREPARED_MEDIA_BUNDLE:-}"
# Only our own generated build artifacts, never app support/user data.
rm -rf "$CONTENTS/Helpers/TimbreBoxMedia"
if [ -z "$SOURCE" ]; then
  rm -rf "$HELPER" "$RESOURCES"
  exit 0
fi
if [ "${CONFIGURATION:-}" != Debug ]; then
  echo 'Local-test media components are not approved for release distribution.' >&2
  exit 1
fi
[ -f "$SOURCE/Resources/manifest.json" ]
[ -x "$SOURCE/TimbreBoxMedia.app/Contents/MacOS/media-supervisor" ]
[ -x "$SOURCE/Resources/Extractor/yt-dlp" ]
[ -x "$SOURCE/Resources/Runtime/deno" ]
rm -rf "$HELPER" "$RESOURCES"
mkdir -p "$CONTENTS/Helpers" "$CONTENTS/Resources"
/usr/bin/ditto "$SOURCE/TimbreBoxMedia.app" "$HELPER"
/usr/bin/ditto "$SOURCE/Resources" "$RESOURCES"
