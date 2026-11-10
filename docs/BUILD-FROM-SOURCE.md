# Building PyTorch 1.13.1 from source for gfx803

This is the **trustless alternative** to the community wheels installed by
`scripts/install-python.sh`. You compile PyTorch and torchvision yourself against the same
ROCm 5.4.3 runtime, so no third-party binary is involved.

It is also the slow path: expect **1–3 hours** and **30–50 GiB** of disk.

## Prerequisites

```bash
export GFX803_PREFIX="$HOME/gfx803"

# pyTorch core + dev headers + clang
bash scripts/setup-rocm.sh --dev

# Python environment (the build installs into this venv)
bash scripts/install-python.sh
```

`--dev` adds the `-dev` packages (rocBLAS, MIOpen, hipBLAS, hipFFT, hipSPARSE, hipSOLVER, RCCL,
rocFFT, rocRAND, rocSOLVER, rocSPARSE, hipCUB, rocPRIM, rocTHRUST, rocm-llvm, …) on top of the
core runtime.

Also required:

| Requirement | Notes |
|---|---|
| `git`, `uv` | present on the reference machine |
| **GCC ≤ 13** | PyTorch 1.13 rejects GCC 14+. On Arch, install `gcc12`/`gcc13` and set `CC`/`CXX`. |
| CMake | `scripts/build-torch-from-source.sh` installs `cmake<4` into the venv (PyTorch 1.13 is not CMake-4 clean) |
| Ninja | installed into the venv by the script |
| 8+ GiB RAM | the C++ build is hungry; add swap if you have less |

## One command

```bash
bash scripts/build-torch-from-source.sh
# or:
bash scripts/build-torch-from-source.sh --jobs 4
bash scripts/build-torch-from-source.sh --clean          # re-clone
bash scripts/build-torch-from-source.sh --skip-vision    # torch only
```

The script:

1. checks `hipcc` and the ROCm dev headers,
2. installs `cmake<4`, `ninja`, `wheel`, `setuptools`, `pyyaml`, `requests`, `pillow` into the venv,
3. clones `pytorch` at tag `v1.13.1` and `vision` at `v0.14.1` into `$GFX803_PREFIX/src`,
4. sets `USE_ROCM=1`, `PYTORCH_ROCM_ARCH=gfx803`, `USE_CUDA=0`, `MAX_JOBS`,
5. builds and installs the torch wheel, then the torchvision wheel,
6. runs `scripts/verify_gfx803.py`.

## Manual equivalent

```bash
source scripts/env.sh

export USE_ROCM=1
export PYTORCH_ROCM_ARCH=gfx803
export USE_CUDA=0
export USE_NCCL=0
export ROCM_HOME="$ROCM_PATH"
export HIP_PATH="$ROCM_PATH"
export PATH="$ROCM_PATH/bin:$ROCM_PATH/llvm/bin:$PATH"
export MAX_JOBS="$(nproc)"

SRC="$GFX803_PREFIX/src"
git clone --depth 1 --branch v1.13.1 https://github.com/pytorch/pytorch "$SRC/pytorch"
git clone --depth 1 --branch v0.14.1 https://github.com/pytorch/vision  "$SRC/vision"

cd "$SRC/pytorch"
"$VENV/bin/python" setup.py bdist_wheel
uv pip install --python "$VENV/bin/python" --force-reinstall dist/torch-*.whl
uv pip install --python "$VENV/bin/python" "numpy<2"

cd "$SRC/vision"
"$VENV/bin/python" setup.py bdist_wheel
uv pip install --python "$VENV/bin/python" --force-reinstall dist/torchvision-*.whl

"$VENV/bin/python" scripts/verify_gfx803.py
```

## Compiler notes

PyTorch 1.13 was tested with GCC 9–12. GCC 13 usually works; **GCC 14+ is rejected by the build
system**. On Arch, the default GCC is newer, so either:

```bash
# install gcc12 (AUR/extra) and build with it
CC=gcc-12 CXX=g++-12 bash scripts/build-torch-from-source.sh
```

or use the ROCm clang (15), if you have a GCC 13 libstdc++ header tree:

```bash
CC="$ROCM_PATH/llvm/bin/clang" \
CXX="$ROCM_PATH/llvm/bin/clang++" \
bash scripts/build-torch-from-source.sh
```

`scripts/clangxx-wrap.sh` adds `-isystem` paths to a GCC 13 header tree when one is available
(`GCC_INCLUDE_DIR`).

## CMake 4

Arch currently ships CMake 4.x, which removed compatibility with `cmake_minimum_required` values
below 3.5 — PyTorch 1.13 trips on this. The build script installs `cmake<4` into the venv and uses
that. If you build manually, do the same:

```bash
uv pip install --python "$VENV/bin/python" "cmake<4"
```

## Disk and time

| Step | Disk | Time (4 cores) |
|---|---|---|
| clone | ~1 GiB | minutes |
| torch build | ~25–40 GiB | 1–3 h |
| torchvision build | ~2 GiB | 5–15 min |
| final wheels | ~1 GiB | — |

Delete `$GFX803_PREFIX/src` afterwards to reclaim the build tree.

## Verification

```bash
source scripts/env.sh
python scripts/verify_gfx803.py
```

Expected:

```
torch 1.13.1 hip 5.4.22804-...
available True ['gfx803']
GPU AMD Radeon RX 570 Series
GEMM max err ...
conv2d max err ...
LayerNorm max err ...
OK — gfx803 PyTorch is working
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `hipcc: not found` | `bash scripts/setup-rocm.sh --dev`; source `scripts/env.sh` |
| `fatal error: rocblas/rocblas.h: No such file` | the `-dev` packages are missing |
| CMake error about `cmake_minimum_required` | use `cmake<4` (the script does) |
| `error: unrecognized command-line option` / GCC version error | use GCC ≤ 13 |
| build killed (OOM) | lower `--jobs` (e.g. `--jobs 2`) and/or add swap |
| `torch.cuda.is_available() == False` after install | `source scripts/env.sh`; check `rocminfo` |
