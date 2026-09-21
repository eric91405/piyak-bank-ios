# Original SwiftData schema migration probe

Run from the repository on macOS with Xcode installed:

```sh
python3 scripts/verify_legacy_schema_migration.py
```

Use `--work-dir /tmp/piyak-legacy-migration-run` to choose an **empty** scratch
directory. All stores are synthetic. The script never reads or writes the app's
real container, App Group or simulator data. It leaves its reports and temporary
executables in that directory for inspection.

The script extracts the actual model definitions from commit
`c70a8befb9474e30188793d792bc0a86062ddf85`. It builds an old writer and a current
verifier as two separate executables, both with module name `PiyakBank`, preserving
the app's original model/type names. It asserts the original SQLite model really
lacks `RewardReceipt` and `rewardTrackingData` before invoking the current
`StoreMigration.prepare` and `ModelContainer`, in the same order as `AppPersistence`.
This avoids testing the current schema against itself.

The fixture covers completed work crossing KST midnight, a pause, different wage
rates, fractional won, active work without timer proof, old point transactions,
equipped paid items, and a previously IAP-only outfit. Assertions cover exact
historical record/segment bytes, preserved ownership, 20:1 conversion exactly once,
catalog migration, fresh-process reopening, recovery with empty defaults, and
points for only newly measured work. A final old-process read verifies the source
still has its original schema and contents. `legacy-migration-report.json` records
the schemas, commits, source hashes, assertions and limitations.

Compilation is sequential, one job per compiler, at `nice -n 15`. No simulator is
started. The current host's macOS SwiftData runtime performs the test; this does
not replace upgrading an actual older iOS installation on a device or validating
App Group entitlements in a signed distribution build.
