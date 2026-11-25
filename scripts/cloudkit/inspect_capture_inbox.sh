#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
/usr/bin/python3 scripts/cloudkit/inspect_capture_inbox.py
