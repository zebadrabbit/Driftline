# Map Schema (driftline.map v1)

This document specifies Driftline's JSON **map container format**.

- It is the on-disk format in `maps/*.json` and is also used for copy/paste / editor interchange.
- It is validated + canonicalized by shared code (`shared/drift_map.gd`) on both client and server.

Related schema docs:

- `docs/formats/tilemap.schema.md` — the `layers` tilemap portion
- `docs/formats/tiles_def.schema.md` — tileset behavior source-of-truth (`tiles_def.json`)

Navigation:

- `docs/formats/tilemap.schema.md` — the `layers` tilemap portion
- `docs/formats/tiles_def.schema.md` — where tile behavior is defined
- `docs/map_format_v1.md` — overview + rationale

## Quick mental model (for Godot learners)

This map JSON is a **data-only map** (not a `.tscn`).

- `meta` answers: “How big is the map, and what tileset is it using?”
- `layers` answers: “Which atlas tile is painted at each map grid cell?”
- `entities` answers: “Where are spawns/flags/bases on the grid?”

If you’re new to Godot: you can think of it like a custom, lightweight export of a TileMap—designed to be deterministic and easy for both server and client to validate.

## Purpose (what this file is)

This file describes a playable arena map:

- **Geometry** via a sparse tilemap (`layers.bg|solid|fg`), referencing a tileset atlas (`ax,ay`).
- **Gameplay markers** via `entities` (spawn/flag/base) stored in tile coordinates.
- **Metadata** via `meta` (dimensions, tile size, tileset hint).

The map intentionally does not embed per-tile physics or render behavior; those come from the tileset definition (`tiles_def.json`).

## Top-level schema

Canonical top-level object:

```json
{
	"format": "driftline.map",
	"schema_version": 1,
	"meta": {
		"w": 64,
		"h": 64,
		"tile_size": 16,
		"tileset": "subspace_base"
	},
	"layers": {
		"bg": [],
		"solid": [],
		"fg": []
	},
	"entities": []
}
```

Notes:

- Loaders **refuse to load** maps missing `format` / `schema_version`.
- Unknown `format` or unsupported `schema_version` **fails loudly**.
- Top-level keys are strict: `format`, `schema_version`, `meta`, `layers`, `entities`.

## Required fields + defaults

There is no permissive “normalization” step. Missing/invalid required fields are errors.

### `format` and `schema_version`

- `format` must be exactly `"driftline.map"`.
- `schema_version` must be exactly `1`.

### `meta`

Canonical `meta`:

- `meta.w` (int, required): width in tiles
- `meta.h` (int, required): height in tiles
- `meta.tile_size` (int, required): must be `16`
- `meta.tileset` (string, required): must be non-empty (e.g. `"subspace_base"`)

Validation constraints:

- `meta.w` and `meta.h` must be `>= 2` (smaller values are treated as errors).
- `meta.tile_size` must be `16`.

### `layers` (tilemap)

See `docs/formats/tilemap.schema.md` for the full tilemap schema.

Minimum requirements:

- `layers` must be an object.
- `layers.bg`, `layers.solid`, `layers.fg` must exist and be arrays.

Each tile placement is a 4-tuple:

```text
[x, y, ax, ay]
```

### `entities`

`entities` is an Array of objects.

Allowed entity types:

- `"spawn"`
- `"flag"`
- `"base"`

Entity object shape:

- `type` (string, required)
- `x` (int, required)
- `y` (int, required)
- `team` (int, optional): default `0`

## Compatibility rules (what changes are allowed)

### Allowed changes (backward compatible)

- Adding new **top-level** keys is tolerated, but they will not affect checksum unless the canonicalizer is updated.
- Adding new **entity fields** is tolerated in input, but canonical output will currently keep only `type,x,y,team`.
- Adding new tileset definition fields in `tiles_def.json` is generally safe (unknown keys ignored).

### Changes that require coordination / a format bump

Any change that impacts canonical output or simulation determinism requires updating both client and server:

- Changing coordinate systems or the meaning/order of `[x,y,ax,ay]`.
- Adding new authoritative tile layers beyond `bg|solid|fg`.
- Changing the set of allowed entity `type` values.
- Changing canonicalization rules (boundary handling, dupe rules, sorting).

## Canonicalization rules (determinism contract)

The canonical representation is used for stable hashing and client/server mismatch detection.

### Tile canonicalization

For each of `layers.bg|solid|fg`:

- Each entry must be an Array of length **exactly 4** (`[x,y,ax,ay]`).
- Bounds:
	- `0 <= x < meta.w`, `0 <= y < meta.h` (out of bounds is an error)
	- `ax >= 0` and `ay >= 0` (negative is an error)
- Boundary ring is reserved:
	- if `x==0 || y==0 || x==w-1 || y==h-1`, the tile is rejected (error; boundary is engine-generated)
- Duplicate placements in the same layer at the same `(x,y)` are rejected (error).
- Output is sorted by `(x, y, ax, ay)`.

### Entity canonicalization

- Each entry must be an object.
- `type` must be one of `spawn|flag|base` (invalid type is an error).
- Bounds:
	- `0 <= x < meta.w`, `0 <= y < meta.h` (out of bounds is an error)
	- boundary ring is reserved; entities on the boundary are rejected (error)
- Duplicate entities at the same `(type,x,y)` are rejected (error).
- Output is sorted by `(type, x, y)`.

### What contributes to checksum

Only canonical output contributes to checksum:

- `format`
- `schema_version`
- `meta` (including additional scalar keys)
- `layers.{bg,solid,fg}`
- `entities`

Notes:

- Unknown top-level keys are rejected by validation.
- Unknown `meta` keys are allowed only if scalar (string/number/bool) and are preserved in canonical output.

## Checksum

Checksum is:

$$\mathrm{sha256}(\mathrm{UTF8}(\mathrm{canonical\_json\_string}(\mathrm{canonical\_map})))$$

Where `canonical_json_string` emits JSON with:

- fixed key order
- no extra whitespace
- stable ordering of tiles/entities as described above

## Forbidden coupling (what maps must NOT store)

The map is not a tileset definition and not a runtime snapshot.

Forbidden / out of scope:

- Per-tile physics shapes or collision meshes
- Tile property overrides like `solid`, `door`, `restitution`, `render_layer` stored in the map
- Any runtime-only state (e.g. door open/closed, dynamic object state)
- Any client-only visual effects metadata that would affect determinism

If you need to change tile behavior, change the tileset’s `tiles_def.json` instead.

Common beginner pitfall: don’t add `solid` (or similar) to the map. If you do, the runtime will ignore it and different tools may disagree because it’s not part of the checksum.

## Canonical examples

### Example A: Minimal valid map

```json
{
	"format": "driftline.map",
	"schema_version": 1,
	"meta": {"w": 64, "h": 64, "tile_size": 16, "tileset": "subspace_base"},
	"layers": {"bg": [], "solid": [], "fg": []},
	"entities": []
}
```

### Example B: Legacy width/height (rejected)

```json
{
	"format": "driftline.map",
	"schema_version": 1,
	"width": 1024,
	"height": 1024,
	"meta": {"tile_size": 16, "tileset": "subspace_base"},
	"layers": {
		"bg": [[10, 10, 0, 8]],
		"solid": [[11, 10, 1, 2], [12, 10, 1, 2]],
		"fg": []
	},
	"entities": []
}
```

This is **not valid** Driftline map data: strict loaders reject unknown top-level keys like `width` and `height`.

### Example C: Entities

```json
{
	"format": "driftline.map",
	"schema_version": 1,
	"meta": {"w": 64, "h": 64, "tile_size": 16, "tileset": "subspace_base"},
	"layers": {"bg": [], "solid": [], "fg": []},
	"entities": [
		{"type": "spawn", "x": 10, "y": 10, "team": 0},
		{"type": "flag",  "x": 32, "y": 32, "team": 0},
		{"type": "base",  "x": 50, "y": 50, "team": 0}
	]
}
```

