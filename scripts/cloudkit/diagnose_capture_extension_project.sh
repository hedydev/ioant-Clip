#!/bin/bash
set -u
cd "$(dirname "$0")/../.."
cache=/Volumes/LunaDrive/DeveloperCache
if [ -d "$cache" ] && [ -w "$cache" ]; then derived="$cache/projects/ioant-clip/DerivedData/CloudKitCaptureExtensions"; else derived="$PWD/DerivedData/CloudKitCaptureExtensions"; fi
echo "Build diagnostics:"
tail -n 40 "$derived/macOS.log"
echo "Project syntax:"
/usr/bin/plutil -lint ioant-Clip.xcodeproj/project.pbxproj || true
echo "Project parse:"
/usr/bin/xcodebuild -project ioant-Clip.xcodeproj -list 2>&1 | head -n 60
echo "Generated project sizes:"
ls -l ioant-Clip.xcodeproj/project.pbxproj GeneratedExtensions/project.yml
