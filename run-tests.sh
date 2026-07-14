#!/bin/bash
# Build and run the PicotimeCore test suite (a plain SPM executable — no Xcode
# required). Exits non-zero if any check fails.
set -euo pipefail

cd "$(dirname "$0")"

swift run PicotimeCoreTests
