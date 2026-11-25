#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
/usr/bin/python3 scripts/run_ios_visible_device.py
