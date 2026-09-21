# Android domain model

This pure Kotlin/JVM module owns wage calculations, active timer transitions, point receipts, purchases, equipment, and record revisions. Android persistence, UI, notifications, and clocks live in the app module.

## Persistence contract

- Pass `ClockSample(wallMillis, elapsedMillis, bootId)` from wall time, `SystemClock.elapsedRealtime()`, and a stable boot identifier. When a boot identifier cannot be established, use a process-scoped identifier and conservatively discard time across process restarts.
- Keep one serialized repository as the state authority. Inside a SQLite transaction, load and validate the latest state, run a transition, persist the entire new state, and then publish it. Never publish before the database commit succeeds.
- Treat `DomainException(CORRUPT_STATE)` or an unsupported persisted schema as a recovery screen. Preserve the original database; never silently replace it with a fresh state.
- `fresh()` is for first installation and an explicit, confirmed whole-data reset. Deleting a work record must use `deleteRecord()`, which retains its reward receipt and ledger entries.
- Editors capture a record ID and revision. Saving or deleting with a stale revision fails without changing the current record. Storage must not apply a mutation against an old UI snapshot.
- A failed save can retry the same transition against the last committed state. A committed `finish` retried against its resulting state grants nothing again.

## Monetary and clock rules

- Wage calculations multiply integer milliseconds and integer wages using `BigInteger`, then floor once. Daily wage allocations carry fractions over pauses and local midnight and support daylight-saving time.
- Points use only measured timer time: 1 point per 6 seconds, at most 4,800 points per Korean calendar day. An individual work session can capture at most 24 hours of eligible time. Pause time, manually entered records, and wage edits cannot create points.
- Immutable reward intervals are united before daily rounding and capping. Duplicate or overlapping receipts cannot credit the same instant twice. Sub-point fractions carry between sessions within one Korean day.
- A persisted reward calendar advances by the monotonic clock during the same boot. Changing wall time or device time zone does not reopen a daily cap.
- Wage display follows the user's civil time. Only the active record is translated after a clock correction; its relative work/pause durations remain unchanged. Completed records do not move.
- A boot change or decreasing elapsed clock discards the unmeasurable interval for both wages and rewards, while retaining checkpointed time. The calendar resumes from the later of its prior anchor and the new wall time.
- Completely offline software cannot attest the correct wall date across a device reboot or prevent database modification on a compromised device. These points have no monetary value and are neither transferable nor purchasable. Account/server verification would be required for stronger fraud guarantees.

`EarningsCalculator.maximumSessionMillis` limits manual record entry to seven days. Timed session wages are based on elapsed time; the independent reward limit remains 24 hours.

## Validation

Run `:core:test` from the Android Gradle project. The tests exercise monetary boundaries, Korean midnight, daylight-saving transitions, clock changes, recovery, save failure retries, immutable rewards, stale editors, and purchases. `python3 core/verify_catalog.py` compares all 81 IDs, slots, names, prices, and default ownership flags against the iOS catalog without building either app.
