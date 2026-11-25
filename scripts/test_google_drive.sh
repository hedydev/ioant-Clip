#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cache=/Volumes/LunaDrive/DeveloperCache
if [ -d "$cache" ] && [ -w "$cache" ]; then
  scratch="$cache/projects/ioant-clip/SwiftPM"
else
  scratch="$PWD/.build"
fi
swift test --scratch-path "$scratch" --filter GoogleDriveRevisionTransportTests
