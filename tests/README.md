# Tests (headless)

This directory contains **dependency-free** headless tests.

## Contract tests

Contract tests validate Driftline’s versioned JSON formats.

Run:

```bash
godot --headless --quit --path . --script res://tests/run_contract_tests.gd
```

## Smoke tests (sanity)

Smoke tests assert higher-level runtime invariants (simulation behavior, packet semantics, etc.).

Run:

```bash
godot --headless --quit --path . --script res://tests/run_smoke_tests.gd
```

### Deterministic replay smoke test

Smoke tests include deterministic replay checks:

- `replay_deterministic_hash_stable`: records a short deterministic replay and verifies it twice in-process.
- `weaponized_deterministic_replay_scripted_inputs`: records two runs of the same scripted movement+fire input sequence and asserts per-tick hash equality.

An opt-in longer soak variant is available but not enabled by default:

- `replay_hash_stable_soak`: enable via `DRIFTLINE_SMOKE_SOAK_REPLAY_HASH=1`

If replay verification fails, the runner prints:

- mismatch tick
- expected vs got hash (when applicable)
- a `bugreport_replay_path` pointing at a saved replay bundle in the CI workspace

On replay verification failure, a best-effort artifact bundle is written under:

- `res://.ci_artifacts/replay_failures/<timestamp>_<context>/`
	- `replay.jsonl`
	- `mismatch.json`

Additional replay determinism tests may write artifacts under:

- `res://.ci_artifacts/weaponized_replay_verify/...` (verifier mismatch bundles)
- `res://.ci_artifacts/<testname>/<timestamp>/` (paired replays + summary on scripted-hash mismatch)

This folder is ignored by git via `.gitignore`.

## CI

CI expectation: the GitHub Actions job `contract-tests` must pass before merging.
The CI workflow runs both contract tests and smoke tests.

## Test vector naming

Under `res://tests/contracts/`, JSON files are discovered recursively.

- Files prefixed `valid_` are expected to PASS validation.
- Files prefixed `invalid_` are expected to FAIL validation.

Parse errors count as:

- FAIL for `valid_*.json`
- PASS for `invalid_*.json`
