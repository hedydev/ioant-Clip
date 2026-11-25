#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash scripts/cloudkit/run_signed_smoke_mac.sh --clip-cloudkit-account-check
