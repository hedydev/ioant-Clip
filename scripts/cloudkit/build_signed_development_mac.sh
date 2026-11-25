#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash scripts/cloudkit/build_capture_extensions_mac.sh
