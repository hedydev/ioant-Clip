#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
/usr/bin/swiftc -parse-as-library scripts/cloudkit/inspect_capture_runtime.swift -o "$tmp/probe"
"$tmp/probe"
