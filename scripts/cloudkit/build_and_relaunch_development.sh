#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash scripts/cloudkit/build_signed_development_mac.sh
bash scripts/relaunch_mac.sh
bash scripts/install_dev_host.sh
