# Server Boot Config Schema (`server_config.json`)

This document specifies the **server boot configuration contract** used by Driftline.

- Format identity: `"driftline.server_config"`
- Schema version: `1`

This file is consumed by the headless server bootstrap to decide which map to load at startup.

## Non-negotiable rules

- All persistent JSON artifacts MUST include `format` and `schema_version`.
- Loaders MUST refuse to load files missing these fields.
- Unknown `format` or `schema_version` MUST fail loudly.
- Missing required fields MUST fail loudly.
- No normalization, auto-fill, or silent defaults.

## Where this file lives

- `res://server_config.json`
- Optionally, a user override may be provided at `user://server_config.json`.

If neither file exists, server startup fails.

## Schema

Top-level object:

```json
{
  "format": "driftline.server_config",
  "schema_version": 1,
  "default_map": "res://maps/default.json",
  "default_tileset": "res://assets/tilesets/subspace_base/tileset.json"
}
```

### `format` (required)

- Type: string
- Must equal `"driftline.server_config"`

### `schema_version` (required)

- Type: integer
- Must equal `1`

### `default_map` (required)

- Type: string
- Must be non-empty.
- Must be a Godot resource path starting with `res://` or `user://`.

The server loads this map on startup. If the map is missing, invalid JSON, or fails map validation, startup aborts.

### `default_tileset` (optional)

- Type: string
- If present, must be non-empty.
- Must be a Godot resource path starting with `res://` or `user://`.

Note: map files still declare their own tileset via `map.meta.tileset` (by tileset name). This field exists as a server boot configuration knob and is validated strictly when present.

## Forbidden coupling

This file is a **boot selector**, not a gameplay or map schema extension.

It must NOT contain:

- Map data (`meta`, `layers`, `entities`)
- Tile behavior definitions
- Physics or gameplay tuning
- Control flow, scripts, or logic
