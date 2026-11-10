#!/usr/bin/env python3
"""Verify that PyTorch can see gfx803 and gives CPU-equivalent results.

Run after `source scripts/env.sh`:
    python scripts/verify_gfx803.py
"""
import sys

import torch


def main():
    print("torch", torch.__version__, "hip", torch.version.hip)

    available = torch.cuda.is_available()
    arch = torch.cuda.get_arch_list()
    print("available", available, arch)

    if not available:
        sys.exit("torch cannot see the GPU — did you `source scripts/env.sh`?")
    if "gfx803" not in arch:
        sys.exit(f"this build has no gfx803 kernels (arch list: {arch})")

    print("GPU", torch.cuda.get_device_name(0))

    torch.manual_seed(0)
    dev = "cuda"

    # GEMM
    a = torch.randn(512, 512)
    b = torch.randn(512, 512)
    gemm = ((a.to(dev) @ b.to(dev)).cpu() - (a @ b)).abs().max().item()

    # conv2d
    x = torch.randn(2, 3, 64, 64)
    w = torch.randn(8, 3, 3, 3)
    conv = (
        torch.nn.functional.conv2d(x.to(dev), w.to(dev), padding=1).cpu()
        - torch.nn.functional.conv2d(x, w, padding=1)
    ).abs().max().item()

    # LayerNorm (the known gfx803 bug is absent in this ROCm build)
    x = torch.randn(64, 128)
    gamma = torch.randn(128)
    beta = torch.randn(128)
    ln = (
        torch.nn.functional.layer_norm(x.to(dev), (128,), gamma.to(dev), beta.to(dev)).cpu()
        - torch.nn.functional.layer_norm(x, (128,), gamma, beta)
    ).abs().max().item()

    print(f"GEMM max err      {gemm:.2e}")
    print(f"conv2d max err    {conv:.2e}")
    print(f"LayerNorm max err {ln:.2e}")

    worst = max(gemm, conv, ln)
    if worst > 1e-3:
        sys.exit(f"numerics differ from CPU by {worst:.2e} (> 1e-3)")

    print("OK — gfx803 PyTorch is working")


if __name__ == "__main__":
    main()
