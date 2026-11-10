# Troubleshooting

## `import torch` fails: `cannot enable executable stack as shared object requires`

glibc ≥ 2.41 refuses to `dlopen` ROCm 5.4.3's `libamdhip64.so.5` and `libhiprtc.so.5` because
their `PT_GNU_STACK` header is marked executable.

Fix (already done by `setup-rocm.sh`):

```bash
python3 scripts/fix_execstack.py \
  "$GFX803_PREFIX"/rocm54/root/opt/rocm/lib/libamdhip64.so.* \
  "$GFX803_PREFIX"/rocm54/root/opt/rocm/lib/libhiprtc.so.*
```

The script keeps `.execstack.orig` backups. Verify:

```bash
readelf -lW "$GFX803_PREFIX"/rocm54/root/opt/rocm/lib/libamdhip64.so.5 | grep GNU_STACK
# want: GNU_STACK ... RW    (not RWE)
```

## `libmpi_cxx.so.40: cannot open shared object file`

torch 1.13 links OpenMPI's C++ bindings; OpenMPI 5 removed them.

Fix:

```bash
bash scripts/build_mpi_stub.sh "$GFX803_PREFIX/sysroot/usr/lib"
# make sure it is on LD_LIBRARY_PATH:
source scripts/env.sh
ldd "$VENV/lib/python3.10/site-packages/torch/lib/libtorch_cpu.so" | grep mpi
```

The stub defines `MPI::Comm::Comm`, `MPI::Datatype::Free`, `MPI::Win::Free`,
`ompi_mpi_cxx_op_intercept`, and `ompi_op_set_cxx_callback`. MPI is never initialised.

## NumPy ABI error

```
numpy.core.multiarray failed to import
A module that was compiled using NumPy 1.x cannot be run in NumPy 2.x
```

torch 1.13 was compiled against NumPy 1.x:

```bash
uv pip install --python "$VENV/bin/python" "numpy<2"
```

## `torch.cuda.is_available()` is `False`

1. Did you `source scripts/env.sh`? `LD_LIBRARY_PATH` must include `$ROCM_PATH/lib` and the
   sysroot.
2. Does the runtime see the card?

   ```bash
   "$ROCM_PATH/bin/rocminfo" | grep -E 'Name:|gfx'
   # Name: gfx803
   # Marketing Name: AMD Radeon RX 570 Series
   ```

3. Check the user is in the `video` / `render` groups:

   ```bash
   id -nG
   sudo usermod -aG video,render "$USER"   # then log out and back in
   ```

4. Check `dmesg` for `amdgpu` errors.

## `Invalid device function` / `no kernel image is available`

The installed torch wheel does not contain gfx803 kernels. You probably installed a stock
PyPI/ROCm wheel. Reinstall the pinned one:

```bash
bash scripts/install-python.sh
python -c "import torch; print(torch.cuda.get_arch_list())"
# ['gfx803']
```

Do **not** set `HSA_OVERRIDE_GFX_VERSION`: ROCm 5.4.3 has native gfx803 kernels, and overriding
can select the wrong code objects.

## `rocminfo` works but PyTorch segfaults / aborts

Check the basics first:

```bash
dmesg -T | grep -iE 'amdgpu|kfd' | tail -20
```

A known gfx803 issue with **multi-model PyTorch inference** produces a GPU virtual-memory fault:

```
amdgpu 0000:26:00.0: GPU fault detected: 147 0x........
amdgpu 0000:26:00.0: VM fault (... read from 'TC4' ...)
```

The process aborts (SIGABRT + coredump). This is a ROCm/PyTorch bug, not a hardware failure.
Workarounds:

- run that job on CPU (it usually works), or
- split it into one model per process and fuse the results in a separate CPU pass.

## Machine powers off / reboots under GPU load, or AER errors flood the log

On the reference machine this was caused by a **loose PCIe power connector**, not the driver.

Symptoms seen in `dmesg`:

```
pcieport 0000:00:03.1: PCIe Bus Error: severity=Correctable, type=Data Link Layer
  error status/mask=00001040/00002000   # Bad TLP + Replay Timer Timeout
```

- All errors were **correctable** (self-healing, no data corruption).
- They were **load-correlated** (≈0 at idle, 1–7/s under GPU compute).
- The link was healthy: Gen3 x16, ASPM disabled.
- The boot that died had **no shutdown sequence and no kernel trace** — abrupt power loss.

**Fix: power off, reseat the GPU in its slot and reseat the 8-pin PCIe power connector (both
ends).** After that the AER storm stopped and the machine has been stable.

If it recurs:

1. Use a **dedicated** PCIe cable (do not daisy-chain one cable into two connectors).
2. Try another PSU rail/cable and another wall outlet.
3. Watch the +12 V rail under load (multimeter on a Molex/SATA yellow wire, or the BIOS/Windows
   sensor; Linux `nct6775` does not expose this board's divider).
4. Swap in a known-good PSU.

## MIGraphX cannot find `/opt/rocm`

MIGraphX 2.4.0 hard-codes `/opt/rocm`. Without root, bind-mount it with `bwrap`:

```bash
bwrap --dev-bind / / --tmpfs /opt \
  --bind "$GFX803_PREFIX/rocm54/root/opt/rocm-5.4.3" /opt/rocm-5.4.3 \
  --bind "$GFX803_PREFIX/rocm54/root/opt/rocm-5.4.3" /opt/rocm \
  "$GFX803_PREFIX/rocm54/root/opt/rocm/bin/migraphx-driver" perf model.onnx
```

## MIGraphX rejects an ONNX `Split` node

MIGraphX 2.4.0's ONNX parser does not accept the opset-13 `Split` form. Export with **opset 12**:

```python
torch.onnx.export(model, x, "model.onnx", opset_version=12)
```

## ROCm's clang cannot find C++ headers

ROCm 5.4.3's clang 15 cannot parse Arch's GCC 16 libstdc++ headers. Use the GCC 13 header tree:

```bash
source scripts/env.sh
scripts/clangxx-wrap.sh -shared -fPIC foo.cpp -o foo.so
```

Set `GCC_INCLUDE_DIR` if your GCC 13 headers live elsewhere.

## Everything works but `pip install ultralytics` upgraded torch

Install torch first and then pin the YOLO stack without pulling a new torch:

```bash
uv pip install --python "$VENV/bin/python" --no-deps ultralytics==8.4.199
uv pip install --python "$VENV/bin/python" \
  opencv-python pyyaml requests scipy matplotlib tqdm psutil py-cpuinfo pandas seaborn \
  ultralytics-thop ensemble-boxes ncnn pycocotools
python -c "import torch; print(torch.__version__)"   # must still be 1.13.1
```
