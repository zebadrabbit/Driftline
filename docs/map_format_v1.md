# Map Format v1 (JSON)

This document describes the current on-disk / clipboard JSON map format used by driftline.

## See also (schema docs)

For the normative, structured schema documentation:

- `docs/formats/map.schema.md` — full map container schema (`format`, `schema_version`, `meta`, `layers`, `entities`) and canonicalization/checksum rules
- `docs/formats/tilemap.schema.md` — the `layers` tilemap portion (`bg|solid|fg` arrays of `[x,y,ax,ay]`)
- `docs/formats/tiles_def.schema.md` — tileset behavior source-of-truth (`tiles_def.json`: `solid`, `door`, `safe_zone`, render layer)

## Start here (recommended reading order)

If you're learning Godot and want the “mental model” first:

1. `docs/formats/map.schema.md` — what the full map JSON contains
2. `docs/formats/tilemap.schema.md` — how tile placements are encoded (`[x,y,ax,ay]`)
3. `docs/formats/tiles_def.schema.md` — where tile behavior is defined (`solid`, doors, render layers)

## Overview

- Format: JSON object
- Coordinate system: **tile coordinates** (`x`,`y`) where each tile is `tile_size` pixels (currently 16).
- Boundary: the outermost tile ring is **generated** (walls) and should not be stored.
- Layers: stored sparsely (only used tiles are listed).
- Entities: optional gameplay markers stored as tile coordinates.

Note: tile behavior (collision and intended render layer) is defined by the tileset's `tiles_def.json`. The on-disk map still stores `bg`/`solid`/`fg` arrays, but the game may re-route tiles to their declared `render_layer` on load.

## Schema

Top-level object:

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
    "bg":    [[x, y, ax, ay], ...],
    "solid": [[x, y, ax, ay], ...],
    "fg":    [[x, y, ax, ay], ...]
  },
  "entities": [
    {"type": "spawn", "x": 10, "y": 10, "team": 0},
    {"type": "flag",  "x": 32, "y": 32, "team": 0},
    {"type": "base",  "x": 50, "y": 50, "team": 0}
  ]
}
```

### Header

- `format` must be `"driftline.map"`.
- `schema_version` must be `1`.
- Loaders refuse to load files missing these fields or with unknown values.

### `meta`

- `w` / `h` (required): map size in **tiles**.
- `tile_size`: size of a tile in pixels (currently 16).
- `tileset` (required): tileset name (non-empty).

### `layers.*` tile entries

Each entry is a 4-element array:

- `x`, `y`: tile coordinate (0-based)
- `ax`, `ay`: atlas coordinate inside the tileset atlas

Notes:

- Tiles on the boundary (where `x==0 || y==0 || x==w-1 || y==h-1`) are ignored/invalid for storage.
- Order is not semantically meaningful; canonicalization (below) defines a stable ordering for hashing.

Collision notes:

- The `layers.solid` array is treated as the set of *candidate* colliders.
- Actual collision is filtered by the tile's `solid` property from `tiles_def.json`.

### `entities`

Each entity is an object:

- `type`: one of `"spawn" | "flag" | "base"`
- `x`, `y`: tile coordinate
- `team`: integer (currently used as a placeholder; default 0)

## Legacy maps

Driftline does not perform permissive normalization. Older/legacy layouts (such as top-level `width`/`height`, missing `entities`, or missing headers) are rejected by validators.

## Canonicalization and checksum

To ensure client/server determinism, both sides compute a **canonical SHA-256 checksum** of a validated, canonical map.

Canonicalization rules (implemented in `shared/drift_map.gd`):

- Only these fields contribute to the checksum:
  - `format`, `schema_version`, `meta`, `layers.{bg,solid,fg}`, `entities`
- Boundary tiles are rejected.
- Invalid/out-of-bounds entries are rejected.
- Duplicate tiles at the same `(x,y)` within a layer are rejected.
- Duplicate entities at the same `(type,x,y)` are rejected.
- Sorting:
  - Each layer is sorted by `(x, y, ax, ay)`.
  - Entities are sorted by `(type, x, y)`.
- The canonical JSON string is emitted with a fixed key order and no extra whitespace.
- The checksum is computed as `sha256(UTF8(canonical_json_string))`.

## Network handshake

On connect, the server sends its map checksum in the welcome packet. The client computes its own checksum from the currently loaded map and verifies it matches. If it does not match, the client disconnects and shows a "Map mismatch" message.
