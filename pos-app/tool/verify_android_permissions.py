#!/usr/bin/env python3
"""Enforce the active Android runtime permission contract for pos-app."""

from pathlib import Path
import sys
import xml.etree.ElementTree as ET

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
EXPECTED_PERMISSIONS = {"android.permission.INTERNET"}
UNIMPLEMENTED_HARDWARE_FEATURES = {
    "android.hardware.camera",
    "android.hardware.bluetooth",
}

manifest_path = Path(__file__).resolve().parents[1] / "android/app/src/main/AndroidManifest.xml"
if not manifest_path.is_file():
    print(f"ERROR: Android manifest not found: {manifest_path}", file=sys.stderr)
    raise SystemExit(1)

try:
    root = ET.parse(manifest_path).getroot()
except (ET.ParseError, OSError) as error:
    print(f"ERROR: Could not parse Android manifest: {error}", file=sys.stderr)
    raise SystemExit(1)

actual_permissions = {
    node.attrib.get(ANDROID_NS + "name", "")
    for node in root.findall("uses-permission")
}
if actual_permissions != EXPECTED_PERMISSIONS:
    unexpected = sorted(actual_permissions - EXPECTED_PERMISSIONS)
    missing = sorted(EXPECTED_PERMISSIONS - actual_permissions)
    details = []
    if unexpected:
        details.append("unexpected permissions: " + ", ".join(unexpected))
    if missing:
        details.append("missing permissions: " + ", ".join(missing))
    print("ERROR: Android runtime permission contract failed (" + "; ".join(details) + ").", file=sys.stderr)
    raise SystemExit(1)

declared_features = {
    node.attrib.get(ANDROID_NS + "name", "")
    for node in root.findall("uses-feature")
}
unexpected_features = sorted(declared_features & UNIMPLEMENTED_HARDWARE_FEATURES)
if unexpected_features:
    print(
        "ERROR: Hardware features without an active implementation are declared: "
        + ", ".join(unexpected_features),
        file=sys.stderr,
    )
    raise SystemExit(1)

print("Android runtime permission check: PASS (INTERNET only; no unimplemented camera/Bluetooth features).")
