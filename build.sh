#!/bin/bash
# Build Picotime.app — compile main.swift and assemble a proper .app bundle.
# No Xcode project required; uses the Command Line Tools swiftc.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Picotime"
BUNDLE="${APP_NAME}.app"
CONTENTS="${BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
BIN="${MACOS}/${APP_NAME}"

echo "Cleaning old bundle..."
rm -rf "${BUNDLE}"

echo "Creating bundle layout..."
mkdir -p "${MACOS}"
cp Info.plist "${CONTENTS}/Info.plist"

# Date-based (CalVer) versioning, stamped at build time so it's zero-maintenance
# and always reflects the build date. The repo Info.plist holds placeholders;
# these lines overwrite the copy inside the bundle.
#   CFBundleShortVersionString = yyyymmdd      (human-facing marketing version)
#   CFBundleVersion            = yyyymmddHHMM   (monotonic + unique within a day)
SHORT_VERSION="$(date +%Y%m%d)"
BUILD_VERSION="$(date +%Y%m%d%H%M)"
echo "Stamping version ${SHORT_VERSION} (build ${BUILD_VERSION})..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${SHORT_VERSION}" "${CONTENTS}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_VERSION}" "${CONTENTS}/Info.plist"

# Copy bundled assets (the hourly chime, etc.) into Contents/Resources so
# Bundle.main.url(forResource:…) can find them at runtime.
if [ -d Resources ]; then
  echo "Copying resources..."
  mkdir -p "${CONTENTS}/Resources"
  find Resources -type f ! -name '.DS_Store' -exec cp {} "${CONTENTS}/Resources/" \;
fi

echo "Compiling (universal arm64 + x86_64)..."
# Compile the app entry (App/main.swift) together with the PicotimeCore sources
# as a single module, once per arch, then lipo into a universal binary so the
# same .app runs on Apple Silicon and Intel. swiftc + Command Line Tools only —
# no Xcode. (SwiftPM's --arch universal build needs Xcode's xcbuild; PicotimeCore
# is factored out as an SPM module only for the tests, see Package.swift.)
APP_SOURCES=(App/main.swift Sources/PicotimeCore/*.swift)
swiftc -O -target arm64-apple-macosx13.0  -module-name Picotime -o "${BIN}.arm64"  "${APP_SOURCES[@]}"
swiftc -O -target x86_64-apple-macosx13.0 -module-name Picotime -o "${BIN}.x86_64" "${APP_SOURCES[@]}"
lipo -create -output "${BIN}" "${BIN}.arm64" "${BIN}.x86_64"
rm -f "${BIN}.arm64" "${BIN}.x86_64"

echo "Ad-hoc code signing..."
codesign --force --sign - "${BUNDLE}"

echo "Done: ${PWD}/${BUNDLE} (version ${SHORT_VERSION}, build ${BUILD_VERSION})"
