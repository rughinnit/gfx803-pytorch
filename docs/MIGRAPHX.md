# MIGraphX on gfx803

MIGraphX 2.4.0 is the last release that ships `gfx803` code objects. It is **optional** — the
PyTorch stack works without it — but it is the fastest inference path on a Polaris card:

| Runtime | yolo11n forward |
|---|---|
| PyTorch + ROCm 5.4.3 | 13.26 ms |
| ncnn + Vulkan (RADV) | 12.33 ms |
| **MIGraphX 2.4** | **7.85 ms** (~127 img/s) |

## Install

```bash
export GFX803_PREFIX="$HOME/gfx803"
bash scripts/setup-rocm.sh --extras
```

`--extras` adds:

| Package | Why |
|---|---|
| `migraphx5.4.3` | the runtime + `migraphx-driver` |
| `rocm-llvm5.4.3` | device JIT (~800 MiB) |
| `hip-dev5.4.3` | headers |
| `roctracer-dev5.4.3` | profiling support |

## The `/opt/rocm` problem

MIGraphX hard-codes `/opt/rocm` and `/opt/rocm-5.4.3`. Without root, bind them with `bwrap`:

```bash
bwrap --dev-bind / / --tmpfs /opt \
  --bind "$GFX803_PREFIX/rocm54/root/opt/rocm-5.4.3" /opt/rocm-5.4.3 \
  --bind "$GFX803_PREFIX/rocm54/root/opt/rocm-5.4.3" /opt/rocm \
  "$GFX803_PREFIX/rocm54/root/opt/rocm/bin/migraphx-driver" perf model.onnx
```

## ONNX export

MIGraphX 2.4.0's parser rejects the opset-13 `Split` form. Export with **opset 12**:

```python
torch.onnx.export(
    model, dummy, "model.onnx",
    opset_version=12,
    input_names=["images"], output_names=["output"],
    dynamic_axes=None,
)
```

## Python bindings

The `migraphx` Python bindings in ROCm 5.4.3 are built for **Python 3.8**; this stack uses
**3.10**. Use the CLI (`migraphx-driver`) or a small C++ helper. Everything in the reference
workflow used the CLI.

## Compiling against ROCm (optional)

ROCm's clang 15 cannot parse Arch's GCC 16 headers. Use the GCC 13 header tree via the wrapper:

```bash
source scripts/env.sh
scripts/clangxx-wrap.sh -shared -fPIC -O2 foo.cpp -o foo.so \
  -I"$ROCM_PATH/include"
```

Override the header path with `GCC_INCLUDE_DIR` if needed.
