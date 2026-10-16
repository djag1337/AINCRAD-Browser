#!/bin/zsh
# Builds a Release app and zips it as dist/AINCRAD-Browser.zip, the file AINCRAD's installer downloads.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
DERIVED="$HOME/Library/Caches/AINCRAD-Browser-build"
xcodebuild -project AINCRADBrowser.xcodeproj -scheme AINCRADBrowser -configuration Release -derivedDataPath "$DERIVED" build -quiet
APP="$DERIVED/Build/Products/Release/AINCRAD Browser.app"
codesign --verify --deep --strict "$APP"
mkdir -p dist
rm -f dist/AINCRAD-Browser.zip
ditto -c -k --keepParent "$APP" dist/AINCRAD-Browser.zip
echo "Built dist/AINCRAD-Browser.zip ($(du -h dist/AINCRAD-Browser.zip | cut -f1))"
echo "Publish:  gh release create v\$(grep MARKETING_VERSION project.yml | head -1 | tr -dc '0-9.') dist/AINCRAD-Browser.zip --title 'AINCRAD Browser' --notes-file RELEASE_NOTES.md"
