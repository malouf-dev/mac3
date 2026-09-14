#!/bin/bash
# Build the single mac3.app product. Its Launcher owns setup, updates, rebuilds,
# and game start; licensed GTA III data is imported only at first launch.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/mac3.app"
CONTENTS="$APP/Contents"

[ ! -e "$APP" ] || {
  echo "Refusing to overwrite existing mac3.app: $APP" >&2
  echo 'Move or rename it, then build again.' >&2
  exit 1
}
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
swiftc -framework SwiftUI -framework AppKit \
  -parse-as-library \
  "$ROOT/Sources/Mac3Launcher.swift" \
  -o "$CONTENTS/MacOS/Mac3Launcher"
ditto "$ROOT/Mac3-Info.plist" "$CONTENTS/Info.plist"
ditto "$ROOT/mac3-macos-arm64.tar.gz" "$CONTENTS/Resources/mac3-macos-arm64.tar.gz"
ditto "$ROOT/DistributionManifest.json" "$CONTENTS/Resources/DistributionManifest.json"
# The Launcher and engine use the exact same icon.
tar -xOf "$ROOT/mac3-macos-arm64.tar.gz" ./mac3.app/Contents/Resources/mac3.icns \
  > "$CONTENTS/Resources/mac3.icns"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built the single mac3 app: %s\n' "$APP"
