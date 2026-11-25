#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash scripts/relaunch_mac.sh first-capture-extensions
bash scripts/install_dev_host.sh
