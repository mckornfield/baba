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
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
  echo "    (ad-hoc signing failed; the app will still run)"
echo "==> Built $APP"

if [ "${1:-}" = "--dist" ]; then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
  ZIP="dist/Baba-$VERSION-arm64.zip"
  rm -f "$ZIP"
  # ditto preserves the signature and resource forks; `zip` does not.
  ditto -c -k --keepParent --sequesterRsrc "$APP" "$ZIP"
  echo "==> Packaged $ZIP ($(du -h "$ZIP" | cut -f1))"
  cat <<'NOTE'

    Apple silicon only, signed ad-hoc — Gatekeeper will not recognise it.
    Copy it with scp or a USB drive (no quarantine flag), or clear the flag:

        unzip Baba-*-arm64.zip -d /Applications
        xattr -dr com.apple.quarantine /Applications/Baba.app
        open /Applications/Baba.app

    The templates are not bundled: click Download 1000 memes on first run, or
    copy ~/Library/Application Support/Baba across.

NOTE
  exit 0
fi

if [ "${1:-}" = "--install" ]; then
  pkill -x Baba || true
  rm -rf /Applications/Baba.app
  cp -R "$APP" /Applications/Baba.app
  echo "==> Installed to /Applications/Baba.app"
  open /Applications/Baba.app
fi
