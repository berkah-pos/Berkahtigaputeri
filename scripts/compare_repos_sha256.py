#!/usr/bin/env python3
"""Compare exact checked-out repository snapshots using per-file SHA-256.

The CSV includes every file in the union of both snapshots; identical files are
auditable as well as differences. This script never mutates either source.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
from typing import Any

IGNORED_DIRECTORY_NAMES = {".git", "__pycache__", "build", "node_modules"}


def sha256_path(path: Path) -> tuple[str, int]:
    """Hash file payload; for symlinks hash the stored link target text."""
    if path.is_symlink():
        payload = os.readlink(path).encode("utf-8", errors="surrogateescape")
        return hashlib.sha256(payload).hexdigest(), len(payload)
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
            size += len(chunk)
    return digest.hexdigest(), size


def inventory(root: Path) -> dict[str, tuple[str, int]]:
    root = root.resolve(strict=True)
    if not root.is_dir():
        raise ValueError(f"source is not a directory: {root}")
    result: dict[str, tuple[str, int]] = {}
    for current, dirs, names in os.walk(root, topdown=True, followlinks=False):
        dirs[:] = sorted(name for name in dirs if name not in IGNORED_DIRECTORY_NAMES)
        current_path = Path(current)
        for name in sorted(names):
            path = current_path / name
            relative = path.relative_to(root).as_posix()
            if any(part in IGNORED_DIRECTORY_NAMES for part in Path(relative).parts):
                continue
            if not path.is_file() and not path.is_symlink():
                continue
            result[relative] = sha256_path(path)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--main-dir", type=Path, required=True)
    parser.add_argument("--fork-dir", type=Path, required=True)
    parser.add_argument("--main-commit", required=True)
    parser.add_argument("--fork-commit", required=True)
    parser.add_argument("--output-csv", type=Path, required=True)
    parser.add_argument("--output-summary", type=Path, required=True)
    args = parser.parse_args()

    main_files = inventory(args.main_dir)
    fork_files = inventory(args.fork_dir)
    all_paths = sorted(set(main_files) | set(fork_files))
    counts = {"ONLY_IN_MAIN": 0, "ONLY_IN_FORK": 0, "MODIFIED": 0, "IDENTICAL": 0}

    args.output_csv.parent.mkdir(parents=True, exist_ok=True)
    with args.output_csv.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "path", "status", "main_sha256", "fork_sha256",
                "main_bytes", "fork_bytes",
            ],
        )
        writer.writeheader()
        for path in all_paths:
            main_item = main_files.get(path)
            fork_item = fork_files.get(path)
            if main_item is None:
                status = "ONLY_IN_FORK"
            elif fork_item is None:
                status = "ONLY_IN_MAIN"
            elif main_item[0] != fork_item[0]:
                status = "MODIFIED"
            else:
                status = "IDENTICAL"
            counts[status] += 1
            writer.writerow({
                "path": path,
                "status": status,
                "main_sha256": main_item[0] if main_item else "",
                "fork_sha256": fork_item[0] if fork_item else "",
                "main_bytes": main_item[1] if main_item else "",
                "fork_bytes": fork_item[1] if fork_item else "",
            })

    summary: dict[str, Any] = {
        "schema_version": 1,
        "main_repository": "berkah-pos/Berkahtigaputeri",
        "main_commit": args.main_commit,
        "fork_repository": "Andisatriawan/Berkahtigaputeri",
        "fork_commit": args.fork_commit,
        "ignored_directory_names": sorted(IGNORED_DIRECTORY_NAMES),
        "main_file_count": len(main_files),
        "fork_file_count": len(fork_files),
        "union_path_count": len(all_paths),
        "comparison_counts": counts,
        "status": "PASS",
        "note": (
            "Per-file SHA-256 comparison of exact source snapshots. Git metadata "
            "excluded; symlinks hashed by their stored target text."
        ),
    }
    args.output_summary.parent.mkdir(parents=True, exist_ok=True)
    args.output_summary.write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, indent=2, sort_keys=True))
    print(f"PASS: wrote {len(all_paths)} per-path records to {args.output_csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
