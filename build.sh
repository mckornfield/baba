#!/bin/bash
# Builds Baba.app into dist/ and (optionally) installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=${CONFIG:-release}

# With only the Command Line Tools installed, the newest SDK can lack the
# SwiftUI macro plugin that @State needs; an older SDK builds fine.
if [ -z "${SDKROOT:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] \
   && [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
APP="dist/Baba.app"

echo "==> Compiling ($CONFIG)"
swift build -c "$CONFIG"
BIN=$(swift build -c "$CONFIG" --show-bin-path)/Baba

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Baba"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
  echo "    (ad-hoc signing failed; the app will still run)"
echo "==> Built $APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x Baba || true
  rm -rf /Applications/Baba.app
  cp -R "$APP" /Applications/Baba.app
  echo "==> Installed to /Applications/Baba.app"
  open /Applications/Baba.app
fi
