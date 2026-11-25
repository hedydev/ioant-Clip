#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# Reconcile the exact prior synthetic zone; never create a replacement.
bash scripts/cloudkit/run_signed_smoke_mac.sh --clip-cloudkit-resume ioantClipSmoke-25CD4088-61CC-4D56-9D83-0E0641B8737F
