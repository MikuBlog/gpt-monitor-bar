#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product GPTMonitorBar
binary="$(swift build -c release --show-bin-path)/GPTMonitorBar"
destination="$PWD/dist/GPT Monitor Bar.app"
mkdir -p "$PWD/dist"
stage="$(mktemp -d "$PWD/.build/app.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

app="$stage/GPT Monitor Bar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
install -m 755 "$binary" "$app/Contents/MacOS/GPTMonitorBar"
install -m 644 Info.plist "$app/Contents/Info.plist"
install -m 644 Sources/GPTMonitorBar/Resources/ChatGPTMark.png "$app/Contents/Resources/ChatGPTMark.png"
codesign --force --sign - "$app"
ditto "$app" "$destination"
codesign --verify --strict "$destination"
printf '%s\n' "$destination"
