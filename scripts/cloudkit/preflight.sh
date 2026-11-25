#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 scripts/cloudkit/test_profile_inventory.py
/usr/bin/python3 scripts/cloudkit/profile_inventory.py
