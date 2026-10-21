#!/usr/bin/env python3
"""Calculate evidence-weighted, global implementation progress for Berkah POS.

Progress is intentionally split equally between implementation coverage and
executed acceptance evidence. Writing a report or adding an unexecuted test
does not increase the verified half of a gate.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

DEFAULT_REGISTER = Path(__file__).resolve().parents[1] / "config/ci/implementation-progress.json"
IMPLEMENTATION_SCORE = {"missing": 0.0, "partial": 0.5, "present": 1.0}


def load_progress(path: Path = DEFAULT_REGISTER) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1:
        raise ValueError("Unsupported progress register schema_version")
    gates = data.get("gates")
    if not isinstance(gates, list) or not gates:
        raise ValueError("Progress register must contain a non-empty gates list")
    ids = [gate.get("id") for gate in gates]
    if any(not isinstance(gate_id, str) or not gate_id for gate_id in ids) or len(ids) != len(set(ids)):
        raise ValueError("Each progress gate must have a unique non-empty id")
    if any(not isinstance(gate.get("weight"), int) or gate["weight"] <= 0 for gate in gates):
        raise ValueError("Every gate must have a positive integer weight")
    if sum(gate["weight"] for gate in gates) != 100:
        raise ValueError("Progress gate weights must total exactly 100")
    for gate in gates:
        if gate.get("implementation") not in IMPLEMENTATION_SCORE:
            raise ValueError(f"{gate['id']}: invalid implementation status")
        if not isinstance(gate.get("verified"), bool):
            raise ValueError(f"{gate['id']}: verified must be a boolean")
        if gate["verified"] and (not gate.get("evidence_sha") or not gate.get("evidence_url")):
            raise ValueError(f"{gate['id']}: verified gate requires evidence_sha and evidence_url")
    return data


def calculate_progress(data: dict[str, Any]) -> dict[str, float]:
    gates = data["gates"]
    source_points = sum(gate["weight"] * IMPLEMENTATION_SCORE[gate["implementation"]] for gate in gates)
    verification_points = sum(gate["weight"] for gate in gates if gate["verified"])
    global_points = sum(
        gate["weight"] * (IMPLEMENTATION_SCORE[gate["implementation"]] + float(gate["verified"])) / 2
        for gate in gates
    )
    return {
        "global_delivery_percent": global_points,
        "source_coverage_percent": source_points,
        "verified_acceptance_percent": verification_points,
        "total_weight": sum(gate["weight"] for gate in gates),
    }


def render_markdown(data: dict[str, Any]) -> str:
    scores = calculate_progress(data)
    lines = [
        "## Berkah POS — Global Delivery Progress",
        "",
        f"**Global delivery: {scores['global_delivery_percent']:.2f}%**",
        "",
        f"- Source implementation coverage: {scores['source_coverage_percent']:.2f}%",
        f"- Verified acceptance coverage: {scores['verified_acceptance_percent']:.2f}%",
        "- Formula: each gate contributes half its weight for implementation coverage and half for executed, evidenced acceptance.",
        "",
        "| Gate | Weight | Implementation | Verified | Evidence |",
        "|---|---:|---|---|---|",
    ]
    for gate in data["gates"]:
        evidence = f"[{gate['evidence_sha'][:10]}]({gate['evidence_url']})" if gate.get("verified") else "Not yet executed"
        lines.append(f"| {gate['id']} — {gate['name']} | {gate['weight']}% | {gate['implementation']} | {'PASS' if gate['verified'] else 'NOT VERIFIED'} | {evidence} |")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--register", type=Path, default=DEFAULT_REGISTER)
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown")
    args = parser.parse_args()
    try:
        data = load_progress(args.register)
        if args.format == "json":
            print(json.dumps(calculate_progress(data), indent=2, sort_keys=True))
        else:
            print(render_markdown(data), end="")
        return 0
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        parser.exit(2, f"ERROR: {exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
