#!/bin/bash
# Build the app from a fresh source checkout. Does not change network settings.
set -euo pipefail
base=$(cd "$(dirname "$0")/.." && pwd)
app="$base/dist/Zoom Lag Lab.app"
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/zoom-lag-build.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
compiler=$(/usr/bin/xcrun --sdk macosx --find swiftc)
sdk=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
for arch in arm64 x86_64; do
  "$compiler" -sdk "$sdk" -target "$arch-apple-macosx26.0" \
    -module-cache-path "$build_dir/cache" "$base/source/App.swift" -o "$build_dir/$arch"
done
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/docs"
/usr/bin/lipo -create "$build_dir/arm64" "$build_dir/x86_64" -output "$app/Contents/MacOS/ZoomLagLab"
cp "$base/source/Info.plist" "$app/Contents/Info.plist"
cp "$base/lag.sh" "$base/Guide.md" "$base/Guide.html" "$base/source/RunPrivileged.applescript" "$app/Contents/Resources/"
cp "$base/docs/TESTING.md" "$app/Contents/Resources/docs/TESTING.md"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --verbose "$app"
printf 'Built: %s\n' "$app"
