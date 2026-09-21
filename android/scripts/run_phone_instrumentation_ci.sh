#!/usr/bin/env bash
# Run only prebuilt QA APKs on the disposable CI emulator; never build beside an emulator.
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ "${CI:-}" != "true" ]]; then
  echo "This runner is restricted to disposable CI emulators." >&2
  exit 2
fi
PIYAK_SERIAL="emulator-${EMULATOR_PORT:-5554}"
PIYAK_PACKAGE="com.minseo.piyakbank.uitest"
PIYAK_REPORTS="app/build/reports/minimum-api26"
mkdir -p "$PIYAK_REPORTS"

collect_evidence() {
  local result=$?
  trap - EXIT
  set +e
  timeout 20s adb -s "$PIYAK_SERIAL" logcat -d -t 3000 > "$PIYAK_REPORTS/logcat.txt" 2>&1
  if timeout 10s adb -s "$PIYAK_SERIAL" shell run-as "$PIYAK_PACKAGE" test -d files/scene-gpu-qa; then
    timeout 30s adb -s "$PIYAK_SERIAL" exec-out run-as "$PIYAK_PACKAGE" tar -cf - files/scene-gpu-qa > "$PIYAK_REPORTS/scene-gpu-qa.tar"
  fi
  exit "$result"
}
trap collect_evidence EXIT

PIYAK_API="$(adb -s "$PIYAK_SERIAL" shell getprop ro.build.version.sdk | tr -d '\r')"
if [[ "$PIYAK_API" != "26" ]]; then
  echo "Expected API 26, received $PIYAK_API; refusing to claim minimum-version coverage." >&2
  exit 2
fi
adb -s "$PIYAK_SERIAL" shell getprop > "$PIYAK_REPORTS/device-properties.txt"
adb -s "$PIYAK_SERIAL" install -r -t app/build/outputs/apk/uiTest/app-uiTest.apk
adb -s "$PIYAK_SERIAL" install -r -t app/build/outputs/apk/androidTest/uiTest/app-uiTest-androidTest.apk
adb -s "$PIYAK_SERIAL" logcat -c

# adb/am may return zero for a failing test suite: both transport and structured results matter.
timeout --signal=TERM 12m adb -s "$PIYAK_SERIAL" shell am instrument -w -r \
  "$PIYAK_PACKAGE.test/androidx.test.runner.AndroidJUnitRunner" \
  | tee "$PIYAK_REPORTS/instrumentation.txt"
python3 scripts/verify_instrumentation.py "$PIYAK_REPORTS/instrumentation.txt" \
  --summary "$PIYAK_REPORTS/summary.json"
