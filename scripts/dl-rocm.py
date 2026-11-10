#!/usr/bin/env python3
"""Download ROCm 5.4.3 .deb packages into <prefix>/debs.

Checksum-verified against the repo.radeon.com package index, with a small
thread pool. Existing files of the correct size are reused, so re-running is
cheap.

Usage:
    python3 dl-rocm.py --prefix ~/gfx803/rocm54
    python3 dl-rocm.py --prefix ~/gfx803/rocm54 --extras
"""
import argparse
import concurrent.futures
import gzip
import hashlib
import os
import sys
import urllib.request

BASE = "https://repo.radeon.com/rocm/apt/5.4.3"
DIST, COMP, ARCH = "focal", "main", "amd64"

# The minimum set to run PyTorch on gfx803.
CORE = [
    "rocm-core", "rocminfo", "hsa-rocr", "comgr", "rocm-device-libs",
    "rocm-smi-lib", "rocm-utils",
    "hip-runtime-amd",
    "rocblas", "rocfft", "rocrand", "rocsolver", "rocsparse",
    "hipblas", "hipfft", "hipsparse", "hipsolver",
    "miopen-hip", "miopengemm", "openmp-extras-runtime", "rccl",
]

# Only needed for MIGraphX / building extensions. rocm-llvm is ~800 MiB.
EXTRAS = [
    "hip-dev5.4.3",
    "roctracer-dev5.4.3",
    "migraphx5.4.3",
    "rocm-llvm5.4.3",
]


def parse_index(path):
    text = gzip.open(path, "rt", errors="replace").read()
    db = {}
    for block in text.split("\n\n"):
        entry = {}
        for line in block.splitlines():
            if line.startswith(" ") or ":" not in line:
                continue
            key, value = line.split(":", 1)
            entry[key.strip()] = value.strip()
        if "Package" in entry:
            db[entry["Package"]] = entry
    return db


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prefix", default=os.path.expanduser("~/gfx803/rocm54"))
    ap.add_argument("--extras", action="store_true",
                    help="also fetch hip-dev, roctracer-dev, migraphx, rocm-llvm")
    ap.add_argument("--list", action="store_true",
                    help="resolve and print the package list, then exit")
    args = ap.parse_args()

    prefix = os.path.abspath(os.path.expanduser(args.prefix))
    debs = os.path.join(prefix, "debs")
    os.makedirs(debs, exist_ok=True)

    index = os.path.join(prefix, "Packages.gz")
    if not os.path.exists(index):
        url = f"{BASE}/dists/{DIST}/{COMP}/binary-{ARCH}/Packages.gz"
        print(f"index: {url}")
        urllib.request.urlretrieve(url, index)

    db = parse_index(index)
    wanted = CORE + (EXTRAS if args.extras else [])
    missing = [p for p in wanted if p not in db]
    if missing:
        sys.exit("not in index: %s" % missing)

    if args.list:
        total = 0
        for pkg in wanted:
            meta = db[pkg]
            size = int(meta["Size"])
            total += size
            print(f"{pkg:28s} {size / 1048576:8.1f} MiB  {meta['Filename']}")
        print(f"{'TOTAL':28s} {total / 1048576:8.1f} MiB")
        return

    def fetch(pkg):
        meta = db[pkg]
        url = BASE + "/" + meta["Filename"]
        out = os.path.join(debs, os.path.basename(meta["Filename"]))
        size = int(meta["Size"])
        if os.path.exists(out) and os.path.getsize(out) == size:
            return pkg, "cached"
        last = None
        for _ in range(4):
            try:
                urllib.request.urlretrieve(url, out)
                if os.path.getsize(out) != size:
                    raise IOError("size mismatch")
                digest = hashlib.sha256(open(out, "rb").read()).hexdigest()
                if digest != meta["SHA256"]:
                    raise IOError("sha256 mismatch")
                return pkg, f"ok ({size / 1048576:.1f} MiB)"
            except Exception as exc:  # noqa: BLE001
                last = exc
        return pkg, f"FAIL {last}"

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for pkg, status in pool.map(fetch, wanted):
            print(f"{pkg:28s} {status}")

    print(f"\ndone — {len(wanted)} packages in {debs}")


if __name__ == "__main__":
    main()
