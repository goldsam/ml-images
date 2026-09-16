#!/usr/bin/env python3
"""Strip CUDA wheel dependencies from torch's installed metadata.

torch is installed with --no-deps so it links the CUDA that the image already
provides as system libraries. But its dist-info still declares
`Requires-Dist: nvidia-cublas-cu13`, `nvidia-cudnn-cu13`, `cuda-toolkit`, and so
on. Any later `pip install` that pulls torch into the resolution graph sees
those as missing and installs them -- silently restoring the multi-GB duplicate
CUDA stack this image exists to avoid.

Pinning them out via a constraints file does not work: pip then backtracks
through every torch release looking for one that needs no CUDA wheels, and dies
with `resolution-too-deep`.

So instead we make the metadata accurate. In this image torch really does not
depend on those distributions, and after this runs pip agrees.

triton is deliberately preserved -- it is a real pip dependency (the kernel
compiler behind torch.compile), not a system library.
"""
import argparse
import glob
import os
import re
import sys

# Distributions that ship CUDA runtime libraries the image already provides.
CUDA_DIST = re.compile(
    r"^(nvidia[-_].*|cuda[-_](toolkit|bindings|pathfinder).*)$",
    re.IGNORECASE,
)


def strip(metadata_path: str) -> list[str]:
    with open(metadata_path, encoding="utf-8") as fh:
        lines = fh.readlines()

    kept, removed = [], []
    for line in lines:
        if line.startswith("Requires-Dist:"):
            spec = line.split(":", 1)[1].strip()
            name = re.split(r"[\s\[<>=!;(]", spec, maxsplit=1)[0].strip()
            if CUDA_DIST.match(name):
                removed.append(spec)
                continue
        kept.append(line)

    if removed:
        with open(metadata_path, "w", encoding="utf-8") as fh:
            fh.writelines(kept)
    return removed


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("site_packages_glob", nargs="?",
                    default="/opt/venv/lib/python3.*/site-packages")
    args = ap.parse_args()

    targets = []
    for sp in glob.glob(args.site_packages_glob):
        targets += glob.glob(os.path.join(sp, "torch-*.dist-info", "METADATA"))

    if not targets:
        print("unbundle-cuda: no torch dist-info found", file=sys.stderr)
        return 1

    total = 0
    for path in targets:
        removed = strip(path)
        total += len(removed)
        print(f"unbundle-cuda: {os.path.basename(os.path.dirname(path))}")
        for spec in removed:
            print(f"  dropped Requires-Dist: {spec}")

    if total == 0:
        print("unbundle-cuda: nothing to strip (already clean?)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
