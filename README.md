# gfx803-pytorch

**PyTorch 1.13.1 + ROCm 5.4.3 for AMD gfx803 (Polaris) GPUs** — RX 470 / 480 / 570 / 580 / 590 —
with **no root, no Docker, and no 16 GB ROCm image**.

AMD dropped Polaris (gfx803) support after ROCm 6.1.5, and no official PyTorch ROCm wheel ships
gfx803 kernels. This repository pins the last known-working combination and automates the three
non-obvious fixes required on a modern Arch Linux userland:

1. **exec-stack flag** — glibc ≥ 2.41 refuses to `dlopen` ROCm 5.4.3's `libamdhip64` / `libhiprtc`.
2. **`libmpi_cxx.so.40` stub** — OpenMPI 5 removed the C++ bindings that torch 1.13 links against.
3. **`numpy<2`** — torch 1.13 was compiled against the NumPy 1.x ABI.

Everything is installed under a single prefix (`~/.local` style), so it can be removed by deleting
one directory.

---

## Tested configuration

| Component | Version |
|---|---|
| OS | Arch Linux, kernel 7.2.11 |
| GPU | AMD Radeon RX 570 4 GB (gfx803 / Polaris) |
| ROCm user-space | 5.4.3 (`repo.radeon.com/rocm/apt/5.4.3`, Ubuntu 20.04 debs) |
| HIP | 5.4.22804-474e8620 |
| PyTorch | 1.13.1 (community wheel, `tsl0922/pytorch-gfx803`) |
| torchvision | 0.14.1 |
| Python | 3.10 |
| NumPy | 1.26.4 (`<2`) |
| glibc | ≥ 2.41 (the exec-stack fix exists for this) |
| OpenMPI | 5.x (the stub exists for this) |

Also expected to work on RX 470 / 480 / 580 / 590 — they are the same `gfx803` architecture.

---

## Provenance & trust (read this)

`torch` and `torchvision` are **not** official PyTorch or AMD artifacts. They are community
rebuilds from [`tsl0922/pytorch-gfx803`](https://github.com/tsl0922/pytorch-gfx803), release
**`pytorch-1.13.1`** (commit `9640437`), built against ROCm 5.4.3 for gfx803.

| Wheel | SHA-256 |
|---|---|
| `torch-1.13.1-cp310-cp310-linux_x86_64.whl` | `e6b19c8b2172eee7540739c1f3b612dae3b2712ce30755fa047a6831ee7bc253` |
| `torchvision-0.14.1-cp310-cp310-linux_x86_64.whl` | `ae4d55a8dcc7fa520688bd1438082dc869d92d43642e9ead6e7b8dac64d1ccbd` |

`scripts/install-python.sh` verifies these hashes against **`scripts/checksums.txt`** and refuses
to install a mismatch. The build reports GCC 11.3, HIP 5.4.22804, MIOpen 2.19.0, arch `['gfx803']`.

**Why not an official wheel?** No official PyTorch ROCm wheel contains gfx803 kernels — they
target gfx900 / gfx906 / gfx908 / gfx90a / gfx1030 — and AMD dropped Polaris after ROCm 6.1.5.
A community rebuild is the only prebuilt option.

**If you don't want to trust a third-party binary**, build it yourself against the same runtime:

```bash
bash scripts/setup-rocm.sh --dev
bash scripts/build-torch-from-source.sh
```

That compiles PyTorch 1.13.1 + torchvision 0.14.1 (~1–3 h, 30–50 GiB). See
[docs/BUILD-FROM-SOURCE.md](docs/BUILD-FROM-SOURCE.md).

---

## Quick start

```bash
git clone git@github.com:rughinnit/gfx803-pytorch.git
cd gfx803-pytorch

export GFX803_PREFIX="$HOME/gfx803"          # change if you want another location

bash scripts/setup-rocm.sh                   # download + extract ROCm, patch, build MPI stub
bash scripts/install-python.sh               # uv venv + torch 1.13.1 + torchvision + numpy<2

source scripts/env.sh
python scripts/verify_gfx803.py
```

Expected output:

```
torch 1.13.1 hip 5.4.22804-474e8620
available True ['gfx803']
GPU AMD Radeon RX 570 Series
GEMM max err ...
conv2d max err ...
LayerNorm max err ...
OK — gfx803 PyTorch is working
```

Total download is roughly **570 MiB** (401 MiB of ROCm debs + 165 MiB of wheels), and about
**9 GiB** on disk after extraction. The optional MIGraphX/LLVM extras add ~1.2 GiB of downloads
and ~4 GiB extracted, for ~14 GiB total.

---

## What the scripts do

| Script | Purpose |
|---|---|
| `scripts/setup-rocm.sh` | Downloads ROCm 5.4.3 debs, extracts them with `dpkg-deb` (or `ar`+`tar`), symlinks `opt/rocm`, applies the exec-stack patch, builds the MPI stub, writes `env.sh` |
| `scripts/dl-rocm.py` | The downloader (parallel, checksum-verified) |
| `scripts/fix_execstack.py` | Clears `PF_X` from `PT_GNU_STACK` on `libamdhip64` / `libhiprtc` |
| `scripts/mpi_cxx_stub.cpp` | Source for the 5-symbol `libmpi_cxx.so.40` shim |
| `scripts/build_mpi_stub.sh` | Compiles the stub |
| `scripts/install-python.sh` | Creates the venv and installs the gfx803 wheels + `numpy<2` |
| `scripts/checksums.txt` | Pinned SHA-256 for the third-party wheels |
| `scripts/build-torch-from-source.sh` | Trustless alternative: compiles torch + torchvision locally |
| `scripts/env.sh` | The environment (`ROCM_PATH`, `LD_LIBRARY_PATH`, `VENV`) |
| `scripts/verify_gfx803.py` | Numerics check against CPU (GEMM, conv2d, LayerNorm) |
| `scripts/verify_env.sh` | `rocminfo` + the Python check in one shot |

The scripts are idempotent: re-running them skips existing downloads and already-patched files.

---

## Manual setup (what the scripts do, step by step)

### 1. Fetch and extract ROCm 5.4.3

```bash
PREFIX="$HOME/gfx803/rocm54"
mkdir -p "$PREFIX/debs" "$PREFIX/root"

# package index
curl -fL -o "$PREFIX/Packages.gz" \
  https://repo.radeon.com/rocm/apt/5.4.3/dists/focal/main/binary-amd64/Packages.gz

# download the debs (see scripts/dl-rocm.py for the full list)
python3 scripts/dl-rocm.py --prefix "$PREFIX"

# extract without root
for deb in "$PREFIX"/debs/*.deb; do
  dpkg-deb -x "$deb" "$PREFIX/root"
done

# the packages install to opt/rocm-5.4.3; create the conventional symlink
ln -sfn rocm-5.4.3 "$PREFIX/root/opt/rocm"
```

If `dpkg-deb` is unavailable (it is not in Arch's base):

```bash
for deb in "$PREFIX"/debs/*.deb; do
  d=$(mktemp -d)
  ( cd "$d" && ar x "$deb" && tar -xf data.tar.* -C "$PREFIX/root" )
  rm -rf "$d"
done
```

### 2. Clear the executable-stack flag

```bash
python3 scripts/fix_execstack.py \
  "$PREFIX"/root/opt/rocm/lib/libamdhip64.so.* \
  "$PREFIX"/root/opt/rocm/lib/libhiprtc.so.*
```

Without this, `import torch` fails with
`cannot enable executable stack as shared object requires: libamdhip64.so.5`.

### 3. Build the MPI C++ stub

```bash
bash scripts/build_mpi_stub.sh "$HOME/gfx803/sysroot/usr/lib"
```

torch 1.13 links `libmpi_cxx.so.40` (OpenMPI's C++ bindings). OpenMPI 5 removed them. The stub
defines exactly the five symbols the loader needs:

```
MPI::Comm::Comm()        MPI::Datatype::Free()
MPI::Win::Free()         ompi_mpi_cxx_op_intercept
ompi_op_set_cxx_callback
```

MPI is never initialised; the symbols only need to resolve.

### 4. Create the Python environment

```bash
PREFIX="$HOME/gfx803"
mkdir -p "$PREFIX/wheels"

curl -fL -o "$PREFIX/wheels/torch-1.13.1-cp310-cp310-linux_x86_64.whl" \
  https://github.com/tsl0922/pytorch-gfx803/releases/download/pytorch-1.13.1/torch-1.13.1-cp310-cp310-linux_x86_64.whl
curl -fL -o "$PREFIX/wheels/torchvision-0.14.1-cp310-cp310-linux_x86_64.whl" \
  https://github.com/tsl0922/pytorch-gfx803/releases/download/pytorch-1.13.1/torchvision-0.14.1-cp310-cp310-linux_x86_64.whl

uv venv --python 3.10 "$PREFIX/venv"
uv pip install --python "$PREFIX/venv/bin/python" \
  "$PREFIX/wheels/torch-1.13.1-cp310-cp310-linux_x86_64.whl" \
  "$PREFIX/wheels/torchvision-0.14.1-cp310-cp310-linux_x86_64.whl"

uv pip install --python "$PREFIX/venv/bin/python" "numpy<2"
```

### 5. Activate

```bash
source scripts/env.sh
python -c "import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_arch_list())"
# 1.13.1 True ['gfx803']
```

---

## Environment variables

`scripts/env.sh` sets:

| Variable | Value |
|---|---|
| `ROCM_PATH` / `ROCM_HOME` / `HIP_PATH` / `HSA_PATH` | `$GFX803_PREFIX/rocm54/root/opt/rocm` |
| `LD_LIBRARY_PATH` | ROCm `lib` + `lib64` + the sysroot (MPI stub) |
| `ROCBLAS_TENSILE_LIBPATH` | `$ROCM_PATH/lib/rocblas/library` |
| `MIOPEN_SYSTEM_DB_PATH` | `$ROCM_PATH/share/miopen/db` |
| `VENV` | `$GFX803_PREFIX/venv` |

`HSA_OVERRIDE_GFX_VERSION` is **not** needed: this ROCm build detects native `gfx803`.

---

## Optional: YOLO / ultralytics stack

The PyTorch core above is enough for training. For the object-detection stack used in
`BCCD-Next`, install on top (order matters — install torch first so pip does not pull a newer one):

```bash
uv pip install --python "$VENV/bin/python" \
  ultralytics==8.4.199 opencv-python pyyaml ensemble-boxes ncnn pycocotools
```

With this environment, the BCCD models trained on the RX 570 and the export path is documented in
`BCCD-Next`.

---

## Optional: MIGraphX (faster inference)

MIGraphX 2.4.0 runs inference graphs at ~7.85 ms for yolo11n on an RX 570. It needs
`/opt/rocm` and `/opt/rocm-5.4.3` to exist, which is done with `bwrap` when running unprivileged:

```bash
bash scripts/setup-rocm.sh --extras        # adds migraphx + rocm-llvm + hip-dev + roctracer
bwrap --dev-bind / / --tmpfs /opt \
  --bind "$GFX803_PREFIX/rocm54/root/opt/rocm-5.4.3" /opt/rocm-5.4.3 \
  --bind "$GFX803_PREFIX/rocm54/root/opt/rocm-5.4.3" /opt/rocm \
  "$GFX803_PREFIX/rocm54/root/opt/rocm/bin/migraphx-driver" perf model.onnx
```

See [docs/MIGRAPHX.md](docs/MIGRAPHX.md) for the opset and clang-wrapper details.

---

## Troubleshooting

Common failures and fixes are in **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)**. The
short version:

| Symptom | Cause / fix |
|---|---|
| `cannot enable executable stack` | exec-stack fix not applied — run `fix_execstack.py` |
| `libmpi_cxx.so.40: cannot open shared object file` | stub not built or not on `LD_LIBRARY_PATH` |
| `numpy.core.multiarray failed to import` / ABI error | `numpy>=2` installed — `pip install "numpy<2"` |
| `torch.cuda.is_available() == False` | `source scripts/env.sh` first; check `rocminfo` sees `gfx803` |
| `Invalid device function` / no kernel image | a wheel without gfx803 kernels — use the pinned wheel |
| GPU disappears / machine reboots under load | **reseat the PCIe power connector** — a loose connector caused AER storms and power-offs on the reference machine (see TROUBLESHOOTING) |

---

## Repository layout

```
.
├── README.md
├── LICENSE                     MIT (scripts/docs; ROCm is AMD's, wheels are their authors')
├── requirements.txt
├── scripts/
│   ├── setup-rocm.sh
│   ├── dl-rocm.py
│   ├── fix_execstack.py
│   ├── mpi_cxx_stub.cpp
│   ├── build_mpi_stub.sh
│   ├── install-python.sh
│   ├── checksums.txt
│   ├── build-torch-from-source.sh
│   ├── env.sh
│   ├── verify_gfx803.py
│   ├── verify_env.sh
│   └── clangxx-wrap.sh
└── docs/
    ├── TROUBLESHOOTING.md
    ├── MIGRAPHX.md
    └── BUILD-FROM-SOURCE.md
```

---

## Notes and caveats

- **gfx803 is end-of-life.** This is a frozen 2023-era stack. It works, but do not expect modern
  PyTorch features (e.g. `torch.compile`, newer SDPA paths) to be supported.
- The ROCm debs are Ubuntu 20.04 builds. They run on Arch because the ABI is compatible; the
  scripts do not install anything system-wide.
- **`rocminfo` and `rocblas` must see `gfx803`** — verify before training.
- Numerics: GEMM/conv/LayerNorm were checked against CPU in `verify_gfx803.py`.
- A rare **GPU VM page fault** has been observed with multi-model PyTorch inference on gfx803
  (`GPU fault detected: 147 ...`). It is a ROCm/PyTorch bug, not a hardware fault; run the job on
  CPU or split it into one model per process.

---

## License

The scripts and documentation in this repository are **MIT** (see `LICENSE`). ROCm is
copyright AMD and distributed under its own licenses; the PyTorch gfx803 wheels are built and
distributed by their authors. This repository only automates fetching and configuring them.
