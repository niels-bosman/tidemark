#!/usr/bin/env bash
# Builds build/Tidemark.app (needs the Xcode Command Line Tools).
# With --install it also copies the app to /Applications and opens it.
set -euo pipefail
cd "$(dirname "$0")"
APP=build/Tidemark.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O Sources/main.swift -o "$APP/Contents/MacOS/Tidemark"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign -s - --force "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Tidemark || true
  rm -rf /Applications/Tidemark.app
  cp -R "$APP" /Applications/
  open /Applications/Tidemark.app
  echo "Installed to /Applications/Tidemark.app"
fi
