# Contract tests (headless)

This directory contains **dependency-free** contract tests for Driftline’s versioned JSON formats.

## Run

```bash
godot --headless --quit --script res://tests/run_contract_tests.gd
```

CI expectation: the GitHub Actions job `contract-tests` must pass before merging.

## Test vector naming

Under `res://tests/contracts/`, JSON files are discovered recursively.

- Files prefixed `valid_` are expected to PASS validation.
- Files prefixed `invalid_` are expected to FAIL validation.

Parse errors count as:

- FAIL for `valid_*.json`
- PASS for `invalid_*.json`
