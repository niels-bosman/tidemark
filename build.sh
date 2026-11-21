#!/usr/bin/env bash
# Builds a universal (Apple silicon + Intel) build/Tidemark.app. Needs the Xcode Command Line Tools.
# With --install it also copies the app to /Applications and opens it.
set -euo pipefail
cd "$(dirname "$0")"
APP=build/Tidemark.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos13.0" Sources/main.swift -o "build/Tidemark-$arch"
done
lipo -create build/Tidemark-arm64 build/Tidemark-x86_64 -output "$APP/Contents/MacOS/Tidemark"
rm build/Tidemark-arm64 build/Tidemark-x86_64
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
