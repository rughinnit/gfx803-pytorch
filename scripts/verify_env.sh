#!/usr/bin/env bash
# One-shot environment check: rocminfo + torch numerics.
#
# Usage:
#   bash scripts/verify_env.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/env.sh"

echo "ROCM_PATH=$ROCM_PATH"
echo "VENV=$VENV"
echo

echo "=== rocminfo ==="
"$ROCM_PATH/bin/rocminfo" 2>/dev/null | grep -E "Name:|gfx|Marketing Name" | head -12
echo

echo "=== torch ==="
"$VENV/bin/python" "$HERE/verify_gfx803.py"
