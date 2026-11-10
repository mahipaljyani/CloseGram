#!/bin/zsh
# Builds CloseGram and installs it on a connected iPhone.
#   ./install.sh                 uses the first connected iPhone
#   DEVICE=<id> ./install.sh     picks one (see: xcrun devicectl list devices)
# Build output stays in ./build, so a custom global Xcode build location does not get in the way.
set -e
cd "$(dirname "$0")"
B="$PWD/build"

if [[ -z "$DEVICE" ]]; then
  DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /available/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-/) {print $i; exit}}')
fi
[[ -n "$DEVICE" ]] || { echo "No connected iPhone found. Plug it in, unlock it, and turn on Developer Mode."; exit 1; }

xcodegen generate
xcodebuild -project CloseGram.xcodeproj -scheme CloseGram \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  -derivedDataPath "$B" SYMROOT="$B/Products" OBJROOT="$B/Intermediates" \
  build | grep -E "error|BUILD"

APP=build/Products/Debug-iphoneos/CloseGram.app
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")"
