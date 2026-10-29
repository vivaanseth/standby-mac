#!/bin/bash
# Builds Standby.app into ./build.
#   ./build.sh           build only
#   ./build.sh install   build, copy to /Applications (or ~/Applications) and launch
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Standby"

APP="build/Standby.app"
rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset
cp "$BIN" "$APP/Contents/MacOS/Standby"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Render the app icon with the app's own drawing code.
"$BIN" --icon build/icon-1024.png
for size in 16 32 128 256 512; do
  sips -z $size $size build/icon-1024.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double build/icon-1024.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "install" ]; then
  DEST="/Applications"
  [ -w "$DEST" ] || DEST="$HOME/Applications"
  mkdir -p "$DEST"
  pkill -x Standby 2>/dev/null || true
  rm -rf "$DEST/Standby.app"
  cp -R "$APP" "$DEST/"
  open "$DEST/Standby.app"
  echo "Installed to $DEST/Standby.app"
fi
