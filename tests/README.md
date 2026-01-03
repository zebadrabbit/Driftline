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
