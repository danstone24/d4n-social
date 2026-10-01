#!/bin/sh
# Archive, sign (cloud-managed via the App Store Connect API key) and upload
# to TestFlight, all from the command line. No Xcode GUI or Apple ID login.
#
#   ios/scripts/testflight.sh [build-number]
#
# ASC_KEY_ID and ASC_ISSUER_ID come from the repo's gitignored .env (or the
# environment).
# The build number defaults to the current UTC minute so every upload is
# unique; MARKETING_VERSION lives in project.yml. The app record (bundle id
# uk.d4n.social) must already exist in App Store Connect.
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
[ -f ../.env ] && . ../.env
KEY_ID="${ASC_KEY_ID:?set ASC_KEY_ID}"
ISSUER="${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_$KEY_ID.p8}"
BUILD="${1:-$(date -u +%Y%m%d%H%M)}"
ARCHIVE=build/D4NSocial.xcarchive
EXPORT=build/export

xcodegen generate >/dev/null

echo "== archive (build $BUILD)"
rm -rf "$ARCHIVE"
xcodebuild -project D4NSocial.xcodeproj -scheme D4NSocial -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER" \
  CURRENT_PROJECT_VERSION="$BUILD" archive | grep -E "error:|warning: [^:]*\.swift|ARCHIVE (SUCCEEDED|FAILED)" || true
test -d "$ARCHIVE"

mkdir -p build
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>FFT4Y887VQ</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST

echo "== export + upload"
rm -rf "$EXPORT"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist build/ExportOptions.plist \
  -allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER" 2>&1 \
  | tee build/export.log | grep -E "error|EXPORT (SUCCEEDED|FAILED)|Upload" || true
# xcodebuild can exit 0 on a failed upload, so go by what it printed.
grep -q "EXPORT SUCCEEDED" build/export.log || { echo "== upload failed, see ios/build/export.log"; exit 1; }
echo "== done: build $BUILD uploaded (processing takes ~10 min before TestFlight shows it)"
