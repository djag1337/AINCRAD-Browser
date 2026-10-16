#!/bin/zsh
# Builds dist/AINCRAD-Browser.zip, the file AINCRAD's installer downloads.
#
# Without a "Developer ID Application" certificate this is signed with your Apple Development
# certificate, which is NOT notarised: other Macs may warn on first open (right-click > Open).
#
# To notarise (needs a paid Apple Developer Program membership):
#   1. Create a "Developer ID Application" certificate (Xcode > Settings > Accounts > Manage Certificates).
#   2. Store notary credentials once:
#        xcrun notarytool store-credentials AINCRAD-NOTARY --apple-id YOU --team-id TEAMID --password APP_SPECIFIC_PASSWORD
#   3. Run:  NOTARY_PROFILE=AINCRAD-NOTARY ./scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
DERIVED="$HOME/Library/Caches/AINCRAD-Browser-build"
DEVID="$(security find-identity -v -p codesigning | grep -o '"Developer ID Application[^"]*"' | head -1 | tr -d '"' || true)"
EXTRA=()
if [[ -n "$DEVID" && -n "${NOTARY_PROFILE:-}" ]]; then
  echo "Signing with: $DEVID (hardened runtime, will notarise)"
  EXTRA=(CODE_SIGN_IDENTITY="$DEVID" CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp CODE_SIGN_ENTITLEMENTS=Browser/AINCRADBrowser.entitlements)
fi
xcodebuild -project AINCRADBrowser.xcodeproj -scheme AINCRADBrowser -configuration Release -derivedDataPath "$DERIVED" build -quiet "${EXTRA[@]}"
APP="$DERIVED/Build/Products/Release/AINCRAD Browser.app"
codesign --verify --deep --strict "$APP"
mkdir -p dist; rm -f dist/AINCRAD-Browser.zip
ditto -c -k --keepParent "$APP" dist/AINCRAD-Browser.zip
if [[ ${#EXTRA[@]} -gt 0 ]]; then
  xcrun notarytool submit dist/AINCRAD-Browser.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f dist/AINCRAD-Browser.zip; ditto -c -k --keepParent "$APP" dist/AINCRAD-Browser.zip
  echo "Notarised and stapled."
else
  echo "Not notarised (no Developer ID certificate and NOTARY_PROFILE)."
fi
echo "Built dist/AINCRAD-Browser.zip ($(du -h dist/AINCRAD-Browser.zip | cut -f1))"
