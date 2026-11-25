#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
/usr/bin/python3 scripts/cloudkit/launch_ui_review_simulator.py
