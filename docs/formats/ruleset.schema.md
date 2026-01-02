# Ruleset Schema (`rulesets/*.json`)

This document specifies the **ruleset contract** used by Driftline to hold gameplay tuning values.

- Format identity: `"driftline.ruleset"`
- Schema version: `1`

Rulesets are **data only**. They declare parameters; the engine interprets them. Unknown keys are rejected.

## Non-negotiable rules

- All persistent JSON artifacts MUST include `format` and `schema_version`.
- Loaders MUST refuse to load files missing these fields.
- Unknown `format` or `schema_version` MUST fail loudly.
- Unknown keys MUST fail loudly at all levels (top-level and nested objects).
- No normalization, auto-fill, or silent defaults.

## Schema

Top-level object:

```json
{
  "format": "driftline.ruleset",
  "schema_version": 1,
  "physics": {
    "wall_restitution": 0.6
  }
}
```

### `format` (required)

- Type: string
- Must equal `"driftline.ruleset"`

### `schema_version` (required)

- Type: integer
- Must equal `1`

### `physics` (required)

- Type: object
- Unknown keys are rejected.

#### `physics.wall_restitution` (required)

- Type: number
- Range: `0.0..2.0`

Used for wall bounce response in the shared deterministic simulation. Values:

- `0.0` = no bounce (normal component is fully killed)
- `1.0` = perfect elastic reflection (normal speed preserved)
- `> 1.0` = energy gain (allowed for arcade tuning)
