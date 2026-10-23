#!/usr/bin/env python3
"""Fail CI if the Flutter runtime or tests reintroduce Supabase dependencies."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "pos-app"
errors: list[str] = []

manifest = APP / "pubspec.yaml"
if "supabase_flutter" in manifest.read_text(encoding="utf-8").lower():
    errors.append("pos-app/pubspec.yaml: forbidden supabase_flutter dependency")

for subtree in (APP / "lib", APP / "test"):
    if not subtree.exists():
        continue
    for source in subtree.rglob("*.dart"):
        try:
            content = source.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            errors.append(f"{source.relative_to(ROOT)}: source is not UTF-8")
            continue
        if "supabase" in content.lower() or "get_effective_config" in content:
            errors.append(f"{source.relative_to(ROOT)}: legacy Supabase runtime/RPC reference")
if errors:
    print("Flutter no-Supabase runtime check: FAIL", file=sys.stderr)
    print("\n".join(f"- {item}" for item in errors), file=sys.stderr)
    sys.exit(1)
print("Flutter no-Supabase runtime check: PASS (manifest, lib/, and test/ are clean)")
