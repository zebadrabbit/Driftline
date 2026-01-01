# Tileset Definition Schema (`tiles_def.json`)

This document specifies `tiles_def.json`, the **source of truth for per-tile behavior**.

It is consumed by shared runtime code (client + server) to interpret the map tilemap:

- Whether a placed tile collides (`solid`)
- Which render layer it belongs to (`render_layer` / `layer`)
- Special tags/behaviors (e.g. `safe_zone`, `door`)

The map tilemap (`layers.*`) stores only tile placements `[x,y,ax,ay]`. The behavior of `(ax,ay)` comes from this file.

Navigation:

- `docs/formats/map.schema.md` — full map container schema
- `docs/formats/tilemap.schema.md` — how maps store placements (`[x,y,ax,ay]`)
- `docs/map_format_v1.md` — overview + rationale

## Quick mental model (for Godot learners)

Think of `tiles_def.json` as the **rulebook for your tileset**:

- The map says: “At map cell `(x,y)` place atlas tile `(ax,ay)`.”
- The tileset definition says: “Atlas tile `(ax,ay)` is solid / not solid, renders in bg/fg, is a door, is a safe zone, etc.”

This separation is important:

- It keeps maps small and easy to diff.
- It lets you reuse the same tileset behavior across many maps.

### Where this file lives

In this repo you may see tileset definitions in two places:

- `assets/tilesets/<tileset_name>/tiles_def.json` (tileset package)
- `client/graphics/tilesets/<tileset_name>/tiles_def.json` (legacy/runtime layout)

At runtime, the shared loader prefers the packaged path when present.

### Glossary

- **Defaults**: the baseline properties every tile has unless overridden.
- **Override**: a small per-tile object that changes one or two fields.
- **Atlas key**: the string form of `(ax,ay)`, written as `"ax,ay"` (example: `"18,8"`).

## Purpose (what this file is)

`tiles_def.json` is a **tileset-level registry** mapping atlas coordinates to gameplay/render properties.

- Scope: **one tileset atlas** (e.g. `subspace_base`)
- Key: atlas coordinate string `"ax,ay"`
- Value: a small object that overrides `defaults`

This file is designed to be stable and diff-friendly: overrides should stay small and omit keys equal to defaults.

## Compatibility rules (what changes are allowed)

### Dialects: `layer` vs `render_layer`

There are two compatible ways to express render intent:

- Editor/package dialect: `layer` in `{"bg","mid","fg"}`
- Runtime dialect: `render_layer` in `{"bg","solid","fg"}`

Compatibility mapping:

- `layer = "mid"` maps to `render_layer = "solid"`
- `layer = "bg"|"fg"` maps to the same string in `render_layer`

If both are present, runtime callers typically treat `render_layer` as authoritative.

### Allowed changes (backward compatible)

- Adding new optional keys under `defaults` and/or per-tile overrides is allowed.
	- Unknown keys should be ignored by older runtimes.
	- Tools should preserve unknown keys when saving.

- Adding new tiles (new `"ax,ay"` entries) is allowed.

### Changes that require coordination

- Changing the meaning of existing keys (`solid`, `door`, etc.)
- Renaming/removing keys that runtime code depends on (`solid`, `render_layer`/`layer`, `door`, `safe_zone`)
- Changing the key format from `"ax,ay"`

## Required fields + defaults

Top-level object:

```json
{
	"version": 1,
	"defaults": { /* optional */ },
	"tiles": { /* optional */ },
	"reserved": { /* optional, editor conventions */ },
	"meta": { /* optional, informational */ }
}
```

### `version` (optional)

- Integer.
- Not currently required by the runtime loader, but used by tools/exporters.
- Default: `1`.

### `defaults` (optional, but strongly recommended)

An object describing the default properties for any tile that does not have an override entry.

Runtime defaults (used when the file is missing or invalid):

```json
{
	"solid": true,
	"safe_zone": false,
	"render_layer": "solid",
	"restitution": 0.90,
	"door": false
}
```

Editor/package defaults (used by tileset packaging tools when creating new tilesets):

```json
{
	"layer": "mid",
	"solid": false
}
```

Notes:

- Both dialects are allowed: you may use either `layer` or `render_layer`.
- If you provide `layer` but not `render_layer`, loaders may derive `render_layer` via the mapping above.

### `tiles` (optional)

A dictionary mapping `"ax,ay"` strings to per-tile override objects.

Key requirements:

- Key must be a string of the form `"<int>,<int>"` (e.g. `"18,8"`).

Value requirements:

- Must be an object.
- Any missing field falls back to `defaults`.

Common override keys (all optional):

- `solid` (bool)
- `safe_zone` (bool)
- `layer` (string: `bg|mid|fg`) or `render_layer` (string: `bg|solid|fg`)
- `restitution` (number)
- `door` (bool)

Unknown keys are allowed.

Beginner tip: keep overrides tiny. If a tile only needs to be “not solid”, the override can be `{ "solid": false }`.

### `reserved` (optional)

Reserved conventions used by the editor/tooling. Current known structure:

```json
{
	"doors": {
		"comment": "...",
		"frames": ["9,8", "10,8", "11,8", "12,8", "13,8", "14,8", "15,8", "16,8"],
		"solid_when_closed": true
	}
}
```

Runtime note: gameplay logic should not depend on `reserved` metadata; it should depend on per-tile `door` flags.

## Semantics (how the runtime uses these fields)

- `solid`:
	- Determines whether a tile placement is treated as colliding.
	- The map’s `layers.solid` is only a *candidate list*; per-tile `solid` is the final gate.

- `door`:
	- Marks tiles that represent doors (dynamic). Doors are excluded from static solids so the simulation can toggle them.

- `render_layer` / `layer`:
	- Determines where the tile is rendered.
	- Even if the map stored a tile under `layers.solid`, it may be re-routed to `bg`/`fg` based on this value.

## Forbidden coupling (what this file must NOT contain)

`tiles_def.json` describes tile behavior independent of any specific map.

Forbidden / out of scope:

- Map placements, coordinates, or per-map overrides.
- Entity spawns, flags, bases.
- Any client/server runtime state (e.g. “this door is currently open”).

If behavior is map-specific, it belongs in the map format (or entities), not here.

## Canonical examples

### Example A: Minimal valid file

```json
{
	"version": 1,
	"defaults": {
		"layer": "mid",
		"solid": false
	},
	"tiles": {}
}
```

### Example B: Override a background, non-solid tile (package dialect)

```json
{
	"defaults": { "layer": "mid", "solid": true },
	"tiles": {
		"0,8": { "layer": "bg", "solid": false }
	}
}
```

### Example C: Same idea using runtime dialect (`render_layer`)

```json
{
	"defaults": { "render_layer": "solid", "solid": true },
	"tiles": {
		"0,8": { "render_layer": "bg", "solid": false }
	}
}
```

### Example D: Door tiles

```json
{
	"defaults": { "render_layer": "solid", "solid": true, "door": false },
	"tiles": {
		"9,8": { "door": true },
		"10,8": { "door": true }
	}
}
```

### Example E: Safe zone tile

```json
{
	"defaults": { "render_layer": "solid", "solid": true, "safe_zone": false },
	"tiles": {
		"18,8": { "render_layer": "bg", "solid": false, "safe_zone": true }
	}
}
```

