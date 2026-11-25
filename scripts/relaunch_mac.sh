#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -d /Volumes/LunaDrive/DeveloperCache ] && [ -w /Volumes/LunaDrive/DeveloperCache ]; then
  derived="/Volumes/LunaDrive/DeveloperCache/projects/ioant-note/DerivedData"
else
  derived="$PWD/DerivedData"
fi
app="$derived/macOS/Build/Products/Debug/ioant-Note-macOS.app"
test -d "$app"
/usr/bin/swift scripts/relaunch_mac.swift "$app"
