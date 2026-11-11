#!/bin/bash
# Builds Stoker.app into ./build. Usage: ./build.sh [--run] [--install]
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Stoker"

APP="build/Stoker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Stoker"
cp Support/Info.plist "$APP/Contents/Info.plist"
[ -f Support/AppIcon.icns ] && cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

for arg in "$@"; do
  case "$arg" in
    --install)
      rm -rf /Applications/Stoker.app
      cp -R "$APP" /Applications/Stoker.app
      APP=/Applications/Stoker.app
      echo "Installed to $APP" ;;
  esac
done
for arg in "$@"; do
  if [ "$arg" = "--run" ]; then
    pkill -x Stoker 2>/dev/null || true
    open "$APP"
  fi
done
