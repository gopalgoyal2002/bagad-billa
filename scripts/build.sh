#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Bagad Billi.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/build/swift-cache"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/Resources/frames" "$APP/Contents/Resources/"
cp "$ROOT/integrations/claude/bridge.py" "$APP/Contents/Resources/claude-bridge.py"
xcrun swiftc "$ROOT/Sources/main.swift" -o "$APP/Contents/MacOS/BagadBilli" -framework AppKit -framework ApplicationServices -framework CoreAudio -module-cache-path "$ROOT/build/swift-cache"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built: %s\n' "$APP"
