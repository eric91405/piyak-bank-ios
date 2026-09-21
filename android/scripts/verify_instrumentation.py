#!/usr/bin/env python3
"""Fail closed on raw `am instrument -w -r` output; adb exit status is insufficient."""

import argparse
import json
import re
from pathlib import Path


# Each family must actually run, so a bad target/package guard cannot produce a green empty run.
REQUIRED_CLASSES = {
    "com.minseo.piyakbank.platform.BankDatabaseTest",
    "com.minseo.piyakbank.platform.ExceptionFlowsTest",
    "com.minseo.piyakbank.platform.ExportCoordinatorTest",
    "com.minseo.piyakbank.platform.SettingsRepositoryTest",
    "com.minseo.piyakbank.scene.SceneRenderingTest",
    "com.minseo.piyakbank.ui.AdaptiveAccessibilityTest",
    "com.minseo.piyakbank.ui.AdaptiveActivityRecreationTest",
    "com.minseo.piyakbank.ui.PiyakUserFlowsTest",
}
ALLOWED_API26_SKIPS = {
    "com.minseo.piyakbank.ui.AdaptiveAccessibilityTest#accessibilityFrameworkChecksHomeTabsSettingsAndRecordEditor",
}


def inspect(text: str) -> dict:
    text = text.replace("\r\n", "\n")
    pending = {}
    started, passed, skipped, failures = set(), set(), set(), []
    for line in text.splitlines():
        field = re.fullmatch(r"INSTRUMENTATION_STATUS: (class|test)=(.*)", line)
        if field:
            pending[field[1]] = field[2]
        status = re.fullmatch(r"INSTRUMENTATION_STATUS_CODE: (-?\d+)", line)
        if status:
            code = int(status[1])
            name = f"{pending.get('class', '?')}#{pending.get('test', '?')}"
            if code == 1:
                started.add(name)
            elif code == 0:
                passed.add(name)
            elif code in (-3, -4):
                skipped.add(name)
            else:
                failures.append(f"{name}: instrumentation status {code}")
            pending = {}

    if re.findall(r"^INSTRUMENTATION_CODE: (-?\d+)\s*$", text, re.M) != ["-1"]:
        failures.append("Missing successful instrumentation completion code")
    if not re.search(r"^OK \([1-9]\d* tests?\)\s*$", text, re.M):
        failures.append("Missing nonempty JUnit success summary")
    if re.search(r"^INSTRUMENTATION_(?:FAILED|ABORTED):|^FAILURES!!!|^INSTRUMENTATION_RESULT: (?:shortMsg|longMsg)=", text, re.M):
        failures.append("Runner reported a failure, abort, or crash")
    if any("?" in name for name in started | passed | skipped):
        failures.append("A test status is missing its class or method")
    for name in sorted(started - passed - skipped):
        failures.append(f"Test started without completing: {name}")
    for name in sorted(skipped - ALLOWED_API26_SKIPS):
        failures.append(f"Unexpected skipped/assumption-failed test: {name}")
    completed_classes = {name.split("#", 1)[0] for name in passed}
    for name in sorted(REQUIRED_CLASSES - completed_classes):
        failures.append(f"Required test family did not pass any test: {name}")
    return {"status": "failed" if failures else "passed", "passed": len(passed),
            "skipped": len(skipped), "tests": sorted(passed), "skipNames": sorted(skipped), "failures": failures}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--summary", type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.report.read_text(encoding="utf-8", errors="replace"))
    args.summary.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Instrumentation: {result['passed']} passed; {result['skipped']} explicitly skipped; {result['status']}")
    for failure in result["failures"]:
        print(f"ERROR: {failure}")
    raise SystemExit(0 if result["status"] == "passed" else 1)


if __name__ == "__main__":
    main()
