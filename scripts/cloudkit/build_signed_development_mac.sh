#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash scripts/cloudkit/build_signed_review.sh macOS development
