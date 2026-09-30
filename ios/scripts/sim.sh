#!/bin/sh
# Build the debug app, put it on a simulator and launch it. Extra arguments are
# passed to the app, e.g.  scripts/sim.sh -startTab filters
# Set SHOT=name to save a screenshot to build/shots/name.png after WAIT seconds.
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SIM="${SIM:-843A8AF4-81B6-427A-B922-2295652564A2}"   # iPhone 17 Pro
BUNDLE=uk.d4n.social

xcodegen generate >/dev/null
xcodebuild -project D4NSocial.xcodeproj -scheme D4NSocial \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath build/DerivedData build \
  | grep -E "error:|\.swift:[0-9]+:[0-9]+: (error|warning)|BUILD (SUCCEEDED|FAILED)" | sort -u

xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" >/dev/null
xcrun simctl install "$SIM" build/DerivedData/Build/Products/Debug-iphonesimulator/D4NSocial.app
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl launch "$SIM" "$BUNDLE" "$@"

if [ -n "${SHOT:-}" ]; then
  sleep "${WAIT:-6}"
  mkdir -p build/shots
  xcrun simctl io "$SIM" screenshot "build/shots/$SHOT.png" 2>&1 | tail -1
fi
