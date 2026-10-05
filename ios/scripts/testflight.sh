#!/bin/bash
# Bouwt een TestFlight-versie van Newsticker.
#
#   ios/scripts/testflight.sh            archiveren + exporteren (lokaal, niets geüpload)
#   ios/scripts/testflight.sh --upload   idem, en daarna uploaden naar App Store Connect
#
# Vereist: de app is aangemaakt in App Store Connect (bundle ID com.mkdebie.newsticker)
# en Xcode is ingelogd met je Apple-account. Bij de eerste export maakt Xcode
# zo nodig een distributiecertificaat aan in je ontwikkelaarsaccount.
set -euo pipefail
cd "$(dirname "$0")/.."

# Elke upload heeft een uniek, hoger buildnummer nodig: datum + tijd.
BUILD=$(date +%Y%m%d%H%M)
OUT=build/testflight
rm -rf "$OUT" && mkdir -p "$OUT"

xcodegen generate >/dev/null
xcodebuild -project Newsticker.xcodeproj -scheme Newsticker -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/Newsticker.xcarchive" \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD" archive | grep -E "error:|ARCHIVE" || true
[ -d "$OUT/Newsticker.xcarchive" ] || { echo "Archiveren mislukt."; exit 1; }

DEST=export
[ "${1:-}" = "--upload" ] && DEST=upload
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$DEST</string>
  <key>teamID</key><string>SBB8YRNS5R</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
EOF

xcodebuild -exportArchive -archivePath "$OUT/Newsticker.xcarchive" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export" \
  -allowProvisioningUpdates | grep -E "error:|EXPORT|Upload" || true

if [ "$DEST" = upload ]; then
  echo "Build $BUILD is geüpload. Na verwerking (±15 min) staat hij in App Store Connect › TestFlight."
else
  echo "Build $BUILD staat klaar in ios/$OUT/export. Uploaden: ios/scripts/testflight.sh --upload"
fi
