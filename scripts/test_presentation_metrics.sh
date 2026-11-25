#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
/usr/bin/swiftc -swift-version 5 App/DesignSystem/Presentation/PresentationMetrics.swift scripts/test_presentation_metrics.swift -o "$tmp/presentation-test"
"$tmp/presentation-test"
