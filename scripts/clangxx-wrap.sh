#!/usr/bin/env bash
# clang++ wrapper for ROCm 5.4.3's clang (only needed for MIGraphX / extensions).
#
# ROCm's clang 15 cannot parse Arch's GCC 16 libstdc++ headers, so this adds
# -isystem paths to a GCC 13 header tree (the one that was current when ROCm
# 5.4.3 shipped).
#
# Usage:
#   export GFX803_PREFIX="$HOME/gfx803"
#   source scripts/env.sh
#   scripts/clangxx-wrap.sh -shared -fPIC foo.cpp -o foo.so
set -euo pipefail

G="${GCC_INCLUDE_DIR:-${GFX803_PREFIX:-$HOME/gfx803}/sysroot/usr/lib/gcc/x86_64-pc-linux-gnu/13.3.0}"

exec "${ROCM_PATH:?source scripts/env.sh first}/llvm/bin/clang" \
    -isystem "$G/include/c++" \
    -isystem "$G/include/c++/x86_64-pc-linux-gnu" \
    -isystem "$G/include" \
    "$@"
