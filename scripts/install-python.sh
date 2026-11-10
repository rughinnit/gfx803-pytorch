#!/usr/bin/env bash
# Create the Python 3.10 environment and install PyTorch 1.13.1 for gfx803.
#
# Requires: uv (https://docs.astral.sh/uv/)
#
# Usage:
#   export GFX803_PREFIX="$HOME/gfx803"
#   bash scripts/install-python.sh
set -euo pipefail

if ! command -v uv >/dev/null 2>&1; then
    echo "error: uv is required — https://docs.astral.sh/uv/getting-started/installation/" >&2
    exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export GFX803_PREFIX="${GFX803_PREFIX:-$HOME/gfx803}"
VENV="${VENV:-$GFX803_PREFIX/venv}"
WHEELS="$GFX803_PREFIX/wheels"
mkdir -p "$WHEELS"

TORCH_WHL="$WHEELS/torch-1.13.1-cp310-cp310-linux_x86_64.whl"
TV_WHL="$WHEELS/torchvision-0.14.1-cp310-cp310-linux_x86_64.whl"
TORCH_URL="https://github.com/tsl0922/pytorch-gfx803/releases/download/pytorch-1.13.1/torch-1.13.1-cp310-cp310-linux_x86_64.whl"
TV_URL="https://github.com/tsl0922/pytorch-gfx803/releases/download/pytorch-1.13.1/torchvision-0.14.1-cp310-cp310-linux_x86_64.whl"

echo "==> wheels"
[ -s "$TORCH_WHL" ] || curl -fL -o "$TORCH_WHL" "$TORCH_URL"
[ -s "$TV_WHL" ]    || curl -fL -o "$TV_WHL" "$TV_URL"

CHECKSUMS="$HERE/checksums.txt"
verify_wheel() {
    local file name expected actual
    file="$1"
    name="$(basename "$file")"
    if [ ! -f "$CHECKSUMS" ]; then
        echo "warning: $CHECKSUMS missing — cannot verify $name" >&2
        return 0
    fi
    expected="$(awk -v n="$name" '$2 == n { print $1 }' "$CHECKSUMS")"
    if [ -z "$expected" ]; then
        echo "warning: no checksum pinned for $name" >&2
        return 0
    fi
    actual="$(sha256sum "$file" | awk '{print $1}')"
    if [ "$actual" != "$expected" ]; then
        echo "ERROR: checksum mismatch for $name" >&2
        echo "  expected: $expected" >&2
        echo "  actual:   $actual" >&2
        echo "  refusing to install a wheel that does not match scripts/checksums.txt" >&2
        exit 1
    fi
    echo "verified $name"
}

verify_wheel "$TORCH_WHL"
verify_wheel "$TV_WHL"

echo "==> venv: $VENV (Python 3.10)"
uv venv --python 3.10 "$VENV"

echo "==> torch + torchvision (gfx803 wheels)"
uv pip install --python "$VENV/bin/python" "$TORCH_WHL" "$TV_WHL"

echo "==> numpy < 2 (torch 1.13 was built against the NumPy 1.x ABI)"
uv pip install --python "$VENV/bin/python" "numpy<2"

echo
echo "done. activate with:"
echo "  source scripts/env.sh"
echo "  python scripts/verify_gfx803.py"
echo
echo "optional YOLO stack (install AFTER torch, then re-check torch.__version__):"
echo "  uv pip install --python \"\$VENV/bin/python\" ultralytics==8.4.199 opencv-python pyyaml ensemble-boxes ncnn pycocotools"
