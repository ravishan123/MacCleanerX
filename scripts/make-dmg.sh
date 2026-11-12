#!/usr/bin/env bash
# Builds a universal (Apple silicon + Intel), ad-hoc signed Mac Cleaner.app and
# packages it as build/MacCleaner-<version>.dmg with a SHA-256 checksum.
#
# Usage: scripts/make-dmg.sh [version]      e.g. scripts/make-dmg.sh 1.0.0
# Requires: Xcode, XcodeGen (brew install xcodegen)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.0.0-dev}"
BUILD="$ROOT/build"
DERIVED="$BUILD/DerivedData"
APP="$DERIVED/Build/Products/Release/Mac Cleaner.app"
DMG="$BUILD/MacCleaner-$VERSION.dmg"
STAGE="$BUILD/dmg-stage"

cd "$ROOT"
echo "==> Generating Xcode project"
xcodegen generate --quiet

echo "==> Building Mac Cleaner $VERSION (arm64 + x86_64)"
xcodebuild \
  -project MacCleaner.xcodeproj \
  -scheme MacCleaner \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$VERSION" \
  build | grep -E "error:|warning:|BUILD" || true
test -d "$APP" || { echo "Build failed: $APP not found" >&2; exit 1; }

echo "==> Ad-hoc signing"
codesign --force --deep --sign - --options runtime "$APP"
codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/Mac Cleaner"

echo "==> Creating disk image"
# Fresh staging folder inside build/ (never outside the project).
if [ -d "$STAGE" ]; then rm -r "$STAGE"; fi
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Mac Cleaner.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Mac Cleaner" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -r "$STAGE"

cd "$BUILD"
shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256"
echo "==> Done"
echo "    $DMG"
cat "$(basename "$DMG").sha256"
