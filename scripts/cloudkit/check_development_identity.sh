#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 scripts/cloudkit/test_development_identity.py
/usr/bin/python3 scripts/cloudkit/check_development_identity.py --team 64RS366WKG
