#!/usr/bin/env bash
# Source this file:  source scripts/env.sh
#
#   GFX803_PREFIX  install root (default: $HOME/gfx803)
#   VENV           virtualenv path (default: $GFX803_PREFIX/venv)
#
# Everything is relative to GFX803_PREFIX, so the whole stack can be moved or
# deleted by changing one variable.

if [ -z "${GFX803_PREFIX:-}" ]; then
  export GFX803_PREFIX="$HOME/gfx803"
fi

export ROCM_PATH="$GFX803_PREFIX/rocm54/root/opt/rocm"
export ROCM_HOME="$ROCM_PATH"
export HIP_PATH="$ROCM_PATH"
export HSA_PATH="$ROCM_PATH"

export PATH="$ROCM_PATH/bin:$PATH"
export LD_LIBRARY_PATH="$ROCM_PATH/lib:$ROCM_PATH/lib64:$GFX803_PREFIX/sysroot/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# rocBLAS / MIOpen kernel databases
export ROCBLAS_TENSILE_LIBPATH="$ROCM_PATH/lib/rocblas/library"
export MIOPEN_SYSTEM_DB_PATH="$ROCM_PATH/share/miopen/db"
export MIOPEN_FIND_MODE=normal

export VENV="${VENV:-$GFX803_PREFIX/venv}"

# HSA_OVERRIDE_GFX_VERSION is intentionally NOT set:
# ROCm 5.4.3 ships native gfx803 kernels and detects the card correctly.
