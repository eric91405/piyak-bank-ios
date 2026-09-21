#!/usr/bin/env python3
"""Fail if the Android catalog diverges from iOS. Does not modify either source."""
from pathlib import Path
import re

core = Path(__file__).resolve().parent
repository = core.parent.parent
swift = (repository / "PiyakBank/Shared/Economy.swift").read_text()
kotlin = (core / "src/main/kotlin/com/minseo/piyakbank/core/Catalog.kt").read_text()
ios = re.findall(
    r'\.init\(id: "([^"]+)",\s*slot: \.(\w+),\s*name: "([^"]+)",\s*price: (\d+),\s*isIAP: false,\s*defaultOwned: (true|false)\)',
    swift,
)
android = re.findall(r'CatalogItem\("([^"]+)", DecorSlot\.(\w+), "([^"]+)", (\d+), (true|false)\)', kotlin)
if len(ios) != 81 or ios != android:
    raise SystemExit("Catalog parity failed: expected all 81 iOS entries in matching order and with matching metadata.")
print("Catalog parity verified: 81 matching IDs, slots, names, prices, and ownership flags.")
