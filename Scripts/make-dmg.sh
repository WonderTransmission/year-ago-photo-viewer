#!/bin/bash
# Builds an unsigned (ad hoc signed) Release DMG of Year Ago Photo Viewer.
#
# Usage, from the root of a checkout:
#   Scripts/make-dmg.sh [extra xcodebuild settings…]
#
# Example, to build an older tag with a different bundle ID prefix:
#   Scripts/make-dmg.sh BUNDLE_ID_PREFIX=com.example
#
# Output: build/YearAgoPhotoViewer-<version>.dmg, plus its SHA-256.
# The app is not notarized, so macOS asks users to approve it once; see
# INSTALL.md.

set -euo pipefail

root=$(pwd)
build="$root/build"
derived="$build/DerivedData"
staging="$build/dmg-staging"
app_name="Year Ago Photo Viewer"

if [ ! -d "$root/YearAgoPhotoViewer.xcodeproj" ]; then
    echo "Run this from the repository root." >&2
    exit 1
fi

rm -rf "$derived" "$staging"
mkdir -p "$build"

echo "Building Release…"
xcodebuild -project YearAgoPhotoViewer.xcodeproj -scheme YearAgoPhotoViewer \
    -configuration Release -derivedDataPath "$derived" \
    DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    "$@" build >"$build/xcodebuild.log" 2>&1 \
    || { echo "Build failed; see $build/xcodebuild.log" >&2; exit 1; }

app="$derived/Build/Products/Release/$app_name.app"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist")
codesign --verify --deep --strict "$app"

echo "Packaging ${bundle_id} ${version}…"
mkdir -p "$staging"
ditto "$app" "$staging/$app_name.app"
ln -s /Applications "$staging/Applications"

dmg="$build/YearAgoPhotoViewer-$version.dmg"
rm -f "$dmg"
hdiutil create -volname "$app_name $version" -srcfolder "$staging" \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$dmg" >/dev/null
rm -rf "$staging"

shasum -a 256 "$dmg" | tee "$dmg.sha256"
echo "Done: $dmg"
