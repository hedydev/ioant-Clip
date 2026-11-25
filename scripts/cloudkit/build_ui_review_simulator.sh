#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash scripts/cloudkit/build_simulator_smoke.sh ui
