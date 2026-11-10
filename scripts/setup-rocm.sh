#!/usr/bin/env bash
# Download and prepare ROCm 5.4.3 user-space for gfx803 — no root, no Docker.
#
# Usage:
#   export GFX803_PREFIX="$HOME/gfx803"
#   bash scripts/setup-rocm.sh            # core packages
#   bash scripts/setup-rocm.sh --extras   # + hip-dev, roctracer, migraphx, rocm-llvm
#   bash scripts/setup-rocm.sh --dev      # + headers/clang to build PyTorch from source
#
# Result:
#   $GFX803_PREFIX/rocm54/root/opt/rocm   (the runtime)
#   $GFX803_PREFIX/sysroot/usr/lib/libmpi_cxx.so.40
set -euo pipefail

EXTRAS=0
DEV=0
for arg in "$@"; do
    case "$arg" in
        --extras) EXTRAS=1 ;;
        --dev) DEV=1 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GFX803_PREFIX="${GFX803_PREFIX:-$HOME/gfx803}"
PREFIX="$GFX803_PREFIX/rocm54"
SYSROOT="$GFX803_PREFIX/sysroot/usr/lib"

echo "==> prefix: $GFX803_PREFIX"
mkdir -p "$PREFIX/debs" "$PREFIX/root" "$SYSROOT"

echo "==> ROCm package index"
IDX="$PREFIX/Packages.gz"
if [ ! -s "$IDX" ]; then
    curl -fL -o "$IDX" \
        "https://repo.radeon.com/rocm/apt/5.4.3/dists/focal/main/binary-amd64/Packages.gz"
fi

echo "==> downloading debs"
DL_ARGS=(--prefix "$PREFIX")
if [ "$EXTRAS" = 1 ]; then
    DL_ARGS+=(--extras)
fi
if [ "$DEV" = 1 ]; then
    DL_ARGS+=(--dev)
fi
python3 "$HERE/dl-rocm.py" "${DL_ARGS[@]}"

echo "==> extracting debs"
if command -v dpkg-deb >/dev/null 2>&1; then
    for deb in "$PREFIX"/debs/*.deb; do
        dpkg-deb -x "$deb" "$PREFIX/root"
    done
else
    # Arch/base systems do not ship dpkg; a .deb is an ar archive containing
    # data.tar.{xz,zst,gz}.
    for deb in "$PREFIX"/debs/*.deb; do
        tmp="$(mktemp -d)"
        ( cd "$tmp" && ar x "$deb" && tar -xf data.tar.* -C "$PREFIX/root" )
        rm -rf "$tmp"
    done
fi

echo "==> symlink opt/rocm -> opt/rocm-5.4.3"
ln -sfn rocm-5.4.3 "$PREFIX/root/opt/rocm"

echo "==> clearing executable-stack flags (glibc >= 2.41)"
python3 "$HERE/fix_execstack.py" \
    "$PREFIX"/root/opt/rocm/lib/libamdhip64.so.* \
    "$PREFIX"/root/opt/rocm/lib/libhiprtc.so.*

echo "==> building libmpi_cxx.so.40 stub (OpenMPI 5)"
bash "$HERE/build_mpi_stub.sh" "$SYSROOT"

echo
echo "ROCm 5.4.3 is ready under $PREFIX"
echo "next:"
echo "  bash scripts/install-python.sh"
echo "  source scripts/env.sh"
echo "  python scripts/verify_gfx803.py"
