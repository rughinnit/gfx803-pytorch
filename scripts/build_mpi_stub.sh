#!/usr/bin/env bash
# Build the libmpi_cxx.so.40 stub.
#
# Usage:
#   bash scripts/build_mpi_stub.sh [output-dir]
#
# Default output: $GFX803_PREFIX/sysroot/usr/lib
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-${GFX803_PREFIX:-$HOME/gfx803}/sysroot/usr/lib}"

mkdir -p "$OUT"

CXX="${CXX:-g++}"
if ! command -v "$CXX" >/dev/null 2>&1; then
    echo "error: $CXX not found (install gcc)" >&2
    exit 1
fi

"$CXX" -shared -fPIC -O2 -o "$OUT/libmpi_cxx.so.40" "$HERE/mpi_cxx_stub.cpp"
ln -sfn libmpi_cxx.so.40 "$OUT/libmpi_cxx.so"

echo "built $OUT/libmpi_cxx.so.40"
echo "symbols:"
nm -D --defined-only "$OUT/libmpi_cxx.so.40" | grep -E 'MPI|ompi' || true
