#!/usr/bin/env python3
"""Reclaim logically duplicated files in site-packages.

The CUDA wheels ship versioned aliases as real files rather than symlinks
(libcupti.so, libcupti.so.13 and libcupti.so.2026.2.0 are three identical 6MB
files), and triton bundles its own CUPTI/nvperf next to the copies already in
nvidia/. Hardlinking byte-identical files keeps every path working while storing
the bytes once.

Usage: dedupe.py [LIB_DIR ...]   (defaults to /usr/local/lib)

Must run in the same layer as the install: layers are additive, so reclaiming
space in a later layer reclaims nothing.
"""
import collections
import glob
import hashlib
import os
import sys

MIN_SIZE = 1024 * 1024


def main() -> int:
    if len(sys.argv) > 1:
        roots = sorted(
            d
            for base in sys.argv[1:]
            for d in glob.glob(os.path.join(base, "python3.*", "site-packages"))
        ) or [d for d in sys.argv[1:] if os.path.isdir(d)]
    else:
        roots = sorted(glob.glob("/usr/local/lib/python3.*/site-packages"))
    if not roots:
        print("dedupe: no site-packages found", file=sys.stderr)
        return 0

    by_size = collections.defaultdict(list)
    for root in roots:
        for dirpath, _, filenames in os.walk(root):
            for name in filenames:
                path = os.path.join(dirpath, name)
                if os.path.islink(path):
                    continue
                try:
                    st = os.stat(path)
                except OSError:
                    continue
                if st.st_size >= MIN_SIZE:
                    by_size[st.st_size].append((path, st))

    saved = 0
    for size, entries in by_size.items():
        if len(entries) < 2:
            continue
        by_hash = collections.defaultdict(list)
        for path, st in entries:
            try:
                with open(path, "rb") as fh:
                    digest = hashlib.sha256(fh.read()).hexdigest()
            except OSError:
                continue
            by_hash[digest].append((path, st))

        for group in by_hash.values():
            if len(group) < 2:
                continue
            keep, keep_st = group[0]
            for path, st in group[1:]:
                if st.st_ino == keep_st.st_ino:
                    continue  # already hardlinked
                tmp = path + ".dedupe-tmp"
                try:
                    os.link(keep, tmp)
                    os.replace(tmp, path)
                    saved += size
                except OSError:
                    try:
                        os.unlink(tmp)
                    except OSError:
                        pass

    print(f"dedupe: reclaimed {saved / 2**20:.0f} MB via hardlinks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
