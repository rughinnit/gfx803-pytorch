#!/usr/bin/env bash
# Build PyTorch 1.13.1 + torchvision 0.14.1 from source for gfx803.
#
# This is the trustless alternative to the community wheels installed by
# scripts/install-python.sh. It compiles against the ROCm 5.4.3 runtime.
#
# Requirements:
#   - ROCm installed with dev headers:  bash scripts/setup-rocm.sh --dev
#   - ~30-50 GiB free disk, 1-3 hours, 8+ GiB RAM
#   - GCC <= 13 (PyTorch 1.13 does not support GCC 14+).
#     On Arch, install gcc12/gcc13 and export CC/CXX if the default is newer.
#
# Usage:
#   export GFX803_PREFIX="$HOME/gfx803"
#   bash scripts/setup-rocm.sh --dev
#   bash scripts/build-torch-from-source.sh [--jobs N] [--clean] [--skip-vision]
set -euo pipefail

JOBS="$(nproc)"
CLEAN=0
SKIP_VISION=0
while [ $# -gt 0 ]; do
    case "$1" in
        --jobs) JOBS="$2"; shift 2 ;;
        --clean) CLEAN=1; shift ;;
        --skip-vision) SKIP_VISION=1; shift ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GFX803_PREFIX="${GFX803_PREFIX:-$HOME/gfx803}"
# shellcheck disable=SC1091
source "$HERE/env.sh"

SRC="$GFX803_PREFIX/src"
VENV="${VENV:-$GFX803_PREFIX/venv}"

echo "==> prerequisites"
[ -x "$ROCM_PATH/bin/hipcc" ] || {
    echo "error: $ROCM_PATH/bin/hipcc not found" >&2
    echo "       run: bash scripts/setup-rocm.sh --dev" >&2
    exit 1
}
for header in \
    include/hip/hip_runtime.h \
    include/rocblas/rocblas.h \
    include/miopen/miopen.h \
    include/rccl/rccl.h
do
    [ -e "$ROCM_PATH/$header" ] || {
        echo "error: missing $ROCM_PATH/$header" >&2
        echo "       run: bash scripts/setup-rocm.sh --dev" >&2
        exit 1
    }
done
for tool in git uv; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "error: $tool is required" >&2
        exit 1
    }
done

AVAIL_GIB="$(df -Pk "$GFX803_PREFIX" | awk 'NR==2 { printf "%d", $4 / 1048576 }')"
echo "free disk: ${AVAIL_GIB} GiB"
if [ "$AVAIL_GIB" -lt 30 ]; then
    echo "warning: less than 30 GiB free — the build may run out of space" >&2
fi

GCC_MAJOR="$(gcc -dumpversion 2>/dev/null | cut -d. -f1 || echo 0)"
if [ "${GCC_MAJOR:-0}" -ge 14 ]; then
    echo "warning: GCC $GCC_MAJOR is newer than PyTorch 1.13 supports (<= 13)." >&2
    echo "         install gcc12 or gcc13 and re-run with CC/CXX set, e.g.:" >&2
    echo "           CC=gcc-12 CXX=g++-12 bash scripts/build-torch-from-source.sh" >&2
fi

echo "==> build tooling in the venv"
uv pip install --python "$VENV/bin/python" \
    "cmake<4" ninja wheel setuptools pyyaml requests pillow

if [ "$CLEAN" = 1 ]; then
    rm -rf "$SRC/pytorch" "$SRC/vision"
fi
mkdir -p "$SRC"

if [ ! -d "$SRC/pytorch/.git" ]; then
    echo "==> clone PyTorch v1.13.1"
    git clone --depth 1 --branch v1.13.1 \
        https://github.com/pytorch/pytorch "$SRC/pytorch"
fi
if [ "$SKIP_VISION" = 0 ] && [ ! -d "$SRC/vision/.git" ]; then
    echo "==> clone torchvision v0.14.1"
    git clone --depth 1 --branch v0.14.1 \
        https://github.com/pytorch/vision "$SRC/vision"
fi

export USE_ROCM=1
export PYTORCH_ROCM_ARCH=gfx803
export USE_CUDA=0
export USE_NCCL=0
export ROCM_HOME="$ROCM_PATH"
export HIP_PATH="$ROCM_PATH"
export PATH="$ROCM_PATH/bin:$ROCM_PATH/llvm/bin:$PATH"
export MAX_JOBS="$JOBS"
export CMAKE_PREFIX_PATH="$ROCM_PATH"

echo "==> building torch (MAX_JOBS=$JOBS, this takes 1-3 h)"
cd "$SRC/pytorch"
"$VENV/bin/python" setup.py bdist_wheel

TORCH_WHEEL="$(ls -t "$SRC"/pytorch/dist/torch-*.whl | head -1)"
echo "==> installing $TORCH_WHEEL"
uv pip install --python "$VENV/bin/python" --force-reinstall "$TORCH_WHEEL"
uv pip install --python "$VENV/bin/python" "numpy<2"

if [ "$SKIP_VISION" = 0 ]; then
    echo "==> building torchvision"
    cd "$SRC/vision"
    "$VENV/bin/python" setup.py bdist_wheel
    TV_WHEEL="$(ls -t "$SRC"/vision/dist/torchvision-*.whl | head -1)"
    echo "==> installing $TV_WHEEL"
    uv pip install --python "$VENV/bin/python" --force-reinstall "$TV_WHEEL"
fi

echo "==> verifying"
"$VENV/bin/python" "$HERE/verify_gfx803.py"

echo
echo "done — torch/torchvision were built locally and are not third-party binaries."
