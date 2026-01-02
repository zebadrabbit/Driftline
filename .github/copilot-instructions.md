You are working on Driftline.

Driftline treats maps and tiles as versioned data contracts, not ad-hoc JSON.
These rules are non-negotiable and must be enforced in code.

GENERAL
- All persistent JSON artifacts MUST include:
  - "format": a stable identifier string
  - "schema_version": an integer
- Loaders MUST refuse to load files missing these fields.
- Unknown formats or schema_versions MUST fail loudly (no silent fallback).

FORMAT IDENTITIES
- tile set manifest:      "driftline.tileset"
- tile definitions:       "driftline.tiles_def"
- map files:              "driftline.map"

SCHEMA VERSIONING
- schema_version only increments.
- Minor-compatible changes: adding optional fields with defaults.
- Breaking changes REQUIRE schema_version increment.
- Renaming, reinterpreting, or removing fields is always breaking.
- Coordinate system changes are always breaking.

SEPARATION OF CONCERNS (MANDATORY)
- tileset.json:
  - Visual identity only (atlas, tile ids, layout metadata).
  - NO physics, NO gameplay behavior.
- tiles_def.json:
  - Declarative tile properties ONLY.
  - Examples: solid, bounce, damage, friction, semantic tags.
  - Tiles NEVER contain logic, scripts, or control flow.
- map.json:
  - Tile placement and map-level metadata ONLY.
  - NO physics, NO tile behavior definitions.
  - References tiles by id or atlas coordinates only.

LOGIC OWNERSHIP
- Engine owns all behavior.
- Tiles declare properties; the engine interprets them.
- If logic leaks into tiles, this is a design error.

SEMANTIC TAGS
- Tags such as: safe_zone, goal, door_frame are declarative labels.
- Tags never execute logic directly.
- Engine systems decide how tags affect gameplay.

RESERVED COORDINATES / TILES
- Certain tile coordinates (e.g. door frames) are engine-reserved.
- Reserved meanings are documented and versioned.
- User tiles MUST NOT override reserved tiles unless schema explicitly allows it.

VALIDATION
- All loaders MUST validate:
  - format
  - schema_version
  - required fields
  - tile references
  - coordinate bounds
- Invalid data MUST produce explicit errors.

TESTING POLICY (MANDATORY)
- Two layers:
  1) Required dependency-free headless contract tests for all versioned JSON formats.
  2) Optional unit/integration tests (GUT/GdUnit4) only when gameplay complexity demands it.
- Contract tests live under: `res://tests/contracts/<format_name>/`
  - `valid_*.json` MUST validate successfully
  - `invalid_*.json` MUST fail validation
  - Parse errors count as FAIL for `valid_*` and PASS for `invalid_*`
- Headless runner command:
  - `godot --headless --quit --script res://tests/run_contract_tests.gd`
- CI expectation:
  - GitHub Actions job `contract-tests` must pass before merging.
- Do not commit `.godot/` artifacts.

CANONICALIZATION
- Saved JSON must be canonical:
  - stable key ordering
  - no derived or cached data
- Canonical output enables diffing, hashing, and migrations.

CHECKSUMS (WHEN PRESENT)
- content_hash applies only to gameplay-relevant payload.
- Metadata such as author, notes, timestamps are excluded.

MIGRATIONS
- Schema upgrades occur via explicit migration functions.
- v1 → v2 migrations must be deliberate and reversible when possible.
- Do not silently mutate data on load.

EDITOR RULES
- Editors generate data that conforms to schemas.
- Editors must not auto-correct invalid data silently.
- Warnings are allowed; hidden fixes are not.

When generating code:
- Prefer explicit validation over permissive parsing.
- Prefer failure with explanation over guessing.
- Do not add new fields or behaviors without updating schema docs.
