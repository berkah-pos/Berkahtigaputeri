#!/usr/bin/env python3
"""Emit Gitleaks finding metadata without any matched secret material.

The input report may contain sensitive Secret/Match fields. Only an allowlist
of metadata is copied into stdout/the optional output file.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

SAFE_FIELDS = (
    "RuleID",
    "Description",
    "File",
    "SymlinkFile",
    "StartLine",
    "EndLine",
    "StartColumn",
    "EndColumn",
    "Commit",
    "Entropy",
    "Tags",
    "Fingerprint",
)


def sanitize_findings(payload: Any) -> list[dict[str, Any]]:
    if not isinstance(payload, list):
        raise ValueError("Gitleaks JSON report must be a list")
    result: list[dict[str, Any]] = []
    for finding in payload:
        if not isinstance(finding, dict):
            continue
        safe = {key: finding[key] for key in SAFE_FIELDS if key in finding}
        if safe:
            result.append(safe)
    return result


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print("Usage: sanitize_gitleaks_report.py INPUT.json [OUTPUT.json]", file=sys.stderr)
        return 2
    source = Path(sys.argv[1])
    try:
        data = json.loads(source.read_text(encoding="utf-8"))
        sanitized = json.dumps(sanitize_findings(data), indent=2, sort_keys=True)
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
        print("Unable to sanitize Gitleaks report; raw report was not printed.", file=sys.stderr)
        return 2
    if len(sys.argv) == 3:
        Path(sys.argv[2]).write_text(sanitized + "\n", encoding="utf-8")
    else:
        print(sanitized)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
