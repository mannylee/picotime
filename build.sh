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

echo "Compiling (universal arm64 + x86_64)..."
# Compile each slice, then lipo into a universal binary so the same .app runs
# on Apple Silicon and Intel.
swiftc -O -target arm64-apple-macosx13.0  -o "${BIN}.arm64"  Sources/main.swift
swiftc -O -target x86_64-apple-macosx13.0 -o "${BIN}.x86_64" Sources/main.swift
lipo -create -output "${BIN}" "${BIN}.arm64" "${BIN}.x86_64"
rm -f "${BIN}.arm64" "${BIN}.x86_64"

echo "Ad-hoc code signing..."
codesign --force --sign - "${BUNDLE}"

echo "Done: ${PWD}/${BUNDLE}"
