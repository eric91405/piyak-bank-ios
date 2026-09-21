#!/usr/bin/env python3
"""Exercise a genuine c70a8be SwiftData store upgrade in isolated processes.

No simulator, signing, app-container access or user data is involved. Builds run
serially at lower priority with one Swift compiler job. Requires Xcode on macOS.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import sqlite3
import subprocess
import tempfile


REPOSITORY = Path(__file__).resolve().parents[1]
FIXTURES = REPOSITORY / "scripts" / "legacy_schema"
LEGACY_COMMIT = "c70a8befb9474e30188793d792bc0a86062ddf85"
LEGACY_FILES = (
    "PiyakBank/Shared/Economy.swift",
    "PiyakBank/Shared/AppConfig.swift",
    "PiyakBank/Services/NotificationScheduler.swift",
)
CURRENT_FILES = (
    "Shared/AppConfig.swift",
    "Shared/EarningsCalculator.swift",
    "Shared/Economy.swift",
    "Shared/PiyakActivityPlan.swift",
    "Shared/RewardPolicy.swift",
    "Shared/RewardTracking.swift",
    "Shared/StoreMigration.swift",
    "Shared/ReminderScheduling.swift",
    "Shared/WatchState.swift",
    "Services/WorkSession.swift",
    "Services/SessionController.swift",
)


def run(arguments: list[str], *, capture: bool = False) -> str:
    result = subprocess.run(
        arguments, cwd=REPOSITORY, check=True, text=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return result.stdout.strip() if capture else ""


def inspect_schema(path: Path, *, old: bool) -> dict:
    with sqlite3.connect(f"{path.as_uri()}?mode=ro", uri=True) as database:
        tables = {row[0].upper() for row in database.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        columns = {row[1].upper() for row in database.execute("PRAGMA table_info(ZWORKSESSION)")}
        metadata = plistlib.loads(database.execute("SELECT Z_PLIST FROM Z_METADATA").fetchone()[0])
        entities = set(metadata["NSStoreModelVersionHashes"])
        expected = {"CatalogItem", "OwnedItem", "PointTransaction", "WorkSession"}
        if not old:
            expected.add("RewardReceipt")
        assert entities == expected, f"Unexpected model entities: {sorted(entities)}"
        assert ("ZREWARDRECEIPT" in tables) is not old, "Receipt table does not match the expected schema version"
        assert ("ZREWARDTRACKINGDATA" in columns) is not old, "Reward tracking column does not match schema version"
        assert database.execute("PRAGMA quick_check").fetchone()[0] == "ok"
        return {"entities": sorted(entities), "workSessionColumns": sorted(columns)}


def file_hashes(root: Path) -> dict[str, str]:
    return {
        path.name: hashlib.sha256(path.read_bytes()).hexdigest()
        # SQLite's shared-memory lock/read marks may change on a read-only open;
        # the actual database and committed WAL payload must not change.
        for path in sorted(root.iterdir()) if path.is_file() and not path.name.endswith("-shm")
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, help="New or empty scratch directory; all synthetic stores and reports stay here")
    arguments = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("SwiftData requires macOS and the installed Xcode toolchain")
    root = arguments.work_dir.expanduser().resolve() if arguments.work_dir else Path(tempfile.mkdtemp(prefix="piyak-legacy-schema-"))
    root.mkdir(parents=True, exist_ok=True)
    if any(root.iterdir()):
        parser.error("--work-dir must be empty to prevent touching existing data")
    print(f"Synthetic migration workspace: {root}", flush=True)
    extracted = root / "old-sources"
    extracted.mkdir()
    source_hashes = {}
    for relative in LEGACY_FILES:
        # Extract the actual original source, never a current model with selected
        # fields omitted. Only the unrelated notification service is left out.
        source = run(["git", "show", f"{LEGACY_COMMIT}:{relative}"], capture=True) + "\n"
        source_hashes[relative] = hashlib.sha256(source.encode()).hexdigest()
        if relative.endswith("NotificationScheduler.swift"):
            boundary = "// MARK: - 알림 스케줄러"
            if source.count(boundary) != 1:
                raise RuntimeError("Pinned original model boundary has changed")
            source = source.split(boundary)[0]
            source = source.replace("import UserNotifications\n", "")
            assert "rewardTrackingData" not in source
            destination = extracted / "WorkSession.swift"
        else:
            destination = extracted / Path(relative).name
        destination.write_text(source)

    sdk = run(["xcrun", "--sdk", "macosx", "--show-sdk-path"], capture=True)
    architecture = platform.machine()
    if architecture not in {"arm64", "x86_64"}:
        raise RuntimeError(f"Unsupported host architecture: {architecture}")
    compile_prefix = [
        "nice", "-n", "15", "xcrun", "swiftc", "-j1", "-swift-version", "5",
        "-parse-as-library", "-module-name", "PiyakBank", "-sdk", sdk,
        "-target", f"{architecture}-apple-macos15.0", "-module-cache-path", str(root / "module-cache"),
    ]
    old_executable = root / "legacy-writer"
    new_executable = root / "current-verifier"
    print("Compiling original model fixture (one job)", flush=True)
    run(compile_prefix + [str(path) for path in sorted(extracted.glob("*.swift"))]
        + [str(FIXTURES / "Fixture.swift"), str(FIXTURES / "LegacyWriter.swift"), "-o", str(old_executable)])
    print("Compiling current migration verifier (one job)", flush=True)
    run(compile_prefix + [str(REPOSITORY / "PiyakBank" / path) for path in CURRENT_FILES]
        + [str(FIXTURES / "Fixture.swift"), str(FIXTURES / "CurrentVerifier.swift"), "-o", str(new_executable)])

    run(["nice", "-n", "15", str(old_executable), "seed", str(root)])
    original_schema = inspect_schema(root / "legacy/default.store", old=True)
    original_hashes = file_hashes(root / "legacy")
    run(["nice", "-n", "15", str(new_executable), "migrate", str(root)])
    current_schema = inspect_schema(root / "group/PiyakBank.store", old=False)
    run(["nice", "-n", "15", str(new_executable), "reopen", str(root)])
    run(["nice", "-n", "15", str(new_executable), "verify-settled", str(root)])
    # CoreData may checkpoint/recreate sidecars on opening. Assert content using
    # the old model too; do not confuse benign file layout changes with data loss.
    source_unchanged_before_old_reopen = file_hashes(root / "legacy") == original_hashes
    assert source_unchanged_before_old_reopen, "The migration wrote to the original database or WAL"
    run(["nice", "-n", "15", str(old_executable), "verify", str(root)])
    inspect_schema(root / "legacy/default.store", old=True)
    result = {
        "status": "passed",
        "originalCommit": LEGACY_COMMIT,
        "currentCommit": run(["git", "rev-parse", "HEAD"], capture=True),
        "currentWorkingTree": run(["git", "status", "--short"], capture=True),
        "moduleNameForBothProcesses": "PiyakBank",
        "oldSourceSHA256": source_hashes,
        "oldSchema": original_schema,
        "newSchema": current_schema,
        "checks": [
            "real original model has no RewardReceipt entity or rewardTrackingData column",
            "StoreMigration relocation followed by current ModelContainer schema upgrade",
            "3 records including pauses, midnight, fractional pay and an active session preserved",
            "segment JSON bytes, record IDs/times, 6 ownerships and equipped slots preserved",
            "4 original transactions archived with original amounts, identifiers and metadata",
            "63997 old points convert once to 3199 points, excluding legacy growth",
            "catalog prices update and former IAP ownership survives",
            "new process recovers active work without any old UserDefaults",
            "only 10 newly measured minutes award 100 points; old/new active pay totals 20000 won",
            "fresh process preserves final 3299 points and exactly 2 reward receipts",
            "source bytes unchanged by migration and original schema still reads the original content",
        ],
        "limits": [
            "macOS SwiftData runtime with original source schema; not an archived iOS 17 binary/store",
            "synthetic directory stands in for App Group; signing/entitlements are validated separately",
        ],
    }
    report = root / "legacy-migration-report.json"
    report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(f"PASS true old-schema migration. Report: {report}", flush=True)


if __name__ == "__main__":
    main()
