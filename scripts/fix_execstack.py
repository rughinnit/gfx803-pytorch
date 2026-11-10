#!/usr/bin/env python3
"""Clear PF_X from PT_GNU_STACK so glibc >= 2.41 can dlopen the library.

ROCm 5.4.3 ships libamdhip64.so.5 and libhiprtc.so.5 with an executable-stack
program header. glibc 2.41+ refuses to load such objects, and `import torch`
fails with:

    cannot enable executable stack as shared object requires

This edits the PT_GNU_STACK program header in place, keeping a .orig backup.

Usage:
    python3 fix_execstack.py path/to/libamdhip64.so.5 path/to/libhiprtc.so.5
"""
import glob
import os
import shutil
import struct
import sys

PT_GNU_STACK = 0x6474E551
PF_X = 0x1


def patch(path):
    with open(path, "rb") as fh:
        data = bytearray(fh.read())

    if data[:4] != b"\x7fELF":
        return "not ELF"
    if data[4] != 2 or data[5] != 1:
        return "not ELF64 little-endian"

    e_phoff, = struct.unpack_from("<Q", data, 0x20)
    e_phentsize, e_phnum = struct.unpack_from("<HH", data, 0x36)

    changed = False
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type, p_flags = struct.unpack_from("<II", data, off)
        if p_type == PT_GNU_STACK and (p_flags & PF_X):
            struct.pack_into("<I", data, off + 4, p_flags & ~PF_X)
            changed = True

    if not changed:
        return "no PF_X (unchanged)"

    shutil.copy2(path, path + ".execstack.orig")
    with open(path, "wb") as fh:
        fh.write(data)
    return "patched"


def expand(args):
    for arg in args:
        matches = glob.glob(arg)
        if not matches:
            print(f"{arg:50s} MISSING")
            continue
        for path in matches:
            print(f"{os.path.basename(path):50s} {patch(path)}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    expand(sys.argv[1:])
