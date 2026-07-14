#!/bin/bash
# Run the PicotimeCore test suite with LLVM source-based coverage and print a
# per-file report. Command Line Tools only — no Xcode / `swift test` needed.
#
#   ./coverage.sh            # run tests, print the coverage report
#   ./coverage.sh --html DIR # also emit an HTML report into DIR
#
# How it works: the test executable and PicotimeCore are compiled with Swift's
# coverage instrumentation, the binary is run to emit a raw profile, and
# llvm-profdata / llvm-cov (both in the CLT) turn that into a report.
set -euo pipefail

cd "$(dirname "$0")"

PRODUCT="PicotimeCoreTests"
COV_DIR=".build/coverage"
mkdir -p "${COV_DIR}"

echo "Building ${PRODUCT} with coverage instrumentation..."
swift build --product "${PRODUCT}" \
  -Xswiftc -profile-generate -Xswiftc -profile-coverage-mapping

BIN_DIR="$(swift build --product "${PRODUCT}" \
  -Xswiftc -profile-generate -Xswiftc -profile-coverage-mapping --show-bin-path)"
TEST_BIN="${BIN_DIR}/${PRODUCT}"

echo "Running tests..."
# LLVM_PROFILE_FILE tells the instrumented binary where to write its raw profile.
LLVM_PROFILE_FILE="${COV_DIR}/tests.profraw" "${TEST_BIN}"

echo "Merging profile..."
xcrun llvm-profdata merge -sparse "${COV_DIR}/tests.profraw" -o "${COV_DIR}/tests.profdata"

# Report coverage for the library sources only (ignore the test files and any
# build artifacts).
IGNORE='(PicotimeCoreTests/|\.build/)'

echo
echo "=== Coverage report (PicotimeCore) ==="
xcrun llvm-cov report "${TEST_BIN}" \
  -instr-profile "${COV_DIR}/tests.profdata" \
  -ignore-filename-regex="${IGNORE}"

if [ "${1:-}" = "--html" ] && [ -n "${2:-}" ]; then
  echo
  echo "Writing HTML report to ${2}..."
  xcrun llvm-cov show "${TEST_BIN}" \
    -instr-profile "${COV_DIR}/tests.profdata" \
    -ignore-filename-regex="${IGNORE}" \
    -format=html -output-dir="${2}"
  echo "Open ${2}/index.html"
fi
