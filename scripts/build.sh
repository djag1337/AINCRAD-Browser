#!/bin/zsh
# Builds AINCRAD Browser (Release) outside iCloud-synced ~/Documents and installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
DERIVED="$HOME/Library/Caches/AINCRAD-Browser-build"
xcodebuild -project AINCRADBrowser.xcodeproj -scheme AINCRADBrowser -configuration Release -derivedDataPath "$DERIVED" build -quiet
rm -rf "/Applications/AINCRAD Browser.app"
ditto "$DERIVED/Build/Products/Release/AINCRAD Browser.app" "/Applications/AINCRAD Browser.app"
codesign --verify "/Applications/AINCRAD Browser.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/AINCRAD Browser.app"
echo "Installed /Applications/AINCRAD Browser.app"
