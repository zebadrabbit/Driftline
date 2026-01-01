# Tilemap Schema (Driftline Map Format v1)

This document specifies the **tilemap portion** of Driftline's on-disk / clipboard JSON map format.

In the full map object, the tilemap lives at `layers`:

```json
{
	"layers": {
		"bg":    [[x, y, ax, ay], ...],
		"solid": [[x, y, ax, ay], ...],
		"fg":    [[x, y, ax, ay], ...]
	}
}
```

If you want the full container schema (version, meta, entities, checksum rules), see `docs/map_format_v1.md`.

Navigation:

- `docs/formats/map.schema.md` — full map container schema
- `docs/formats/tiles_def.schema.md` — tileset behavior source-of-truth
- `docs/map_format_v1.md` — overview + rationale

## Quick mental model (for Godot learners)

Think of the tilemap as “**painted tiles**”:

- `(x,y)` = *where on the map grid* you painted a tile.
- `(ax,ay)` = *which tile from the tileset atlas* you painted.

The map stores those pairs as `[x, y, ax, ay]`.

It does **not** store things like collision shapes or friction. Those come from the tileset definition (`tiles_def.json`).

### Glossary

- **Tile coordinates**: grid positions on the map. `(0,0)` is the top-left tile cell of the map.
- **Pixels vs tiles**: the map uses tiles. To convert to pixels: `pixel_x = x * tile_size`, `pixel_y = y * tile_size`.
- **Tileset atlas**: the tileset image is a grid of tiles (e.g. 16×16 pixels each). `(ax,ay)` refers to a cell in that atlas grid.
- **Sparse storage**: empty cells are not stored at all.
- **Boundary ring**: the outermost ring of tiles is reserved/generated; you don’t store it.

## Purpose (what this file is)

The tilemap is a **sparse set of tile placements**.

- It describes *which* tile is placed (`ax`,`ay` in the tileset atlas) and *where* it is placed (`x`,`y` in tile coordinates).
- It is used by both the editor and the game runtime (client + server) to:
	- render map geometry
	- derive colliders / special behaviors by looking up tile metadata in the tileset definition (`tiles_def.json`)
	- compute a deterministic canonical representation and checksum for client/server map-mismatch detection

The tilemap is intentionally **not** a dense 2D grid. Empty cells are simply absent from the arrays.

## Data model

### Coordinate system

- `x`, `y` are **tile coordinates**, 0-based.
- Valid ranges are determined by the full map's `meta.w` and `meta.h` (width/height in tiles).

### Tile reference

- `ax`, `ay` identify the tile inside the tileset atlas (also 0-based).
- The pair `(ax,ay)` is only an identifier; what it *means* (collision, render layer, tags, etc.) comes from the tileset definition (`tiles_def.json`).

#### How do I find `ax,ay` in Godot?

In Godot’s TileSet/atlas workflow, the tileset texture is divided into a grid.

- `ax` = the tile’s column index within the atlas grid
- `ay` = the tile’s row index within the atlas grid

In Driftline, these are stored as integers and used as keys into `tiles_def.json`.

### Layers

The tilemap contains three stored layers:

- `bg`: background tiles
- `solid`: mid/solid candidate tiles
- `fg`: foreground tiles

Important: the stored layer is a **hint / bucket**, not always the final render layer. On load, the game may re-route tiles to a layer based on the tile's `render_layer` in `tiles_def.json`.

Practical note: this lets the editor keep simple buckets (`bg|solid|fg`), while the tileset definition can declare “this tile should really render in bg/fg”.

## Required fields + defaults

The tilemap object is the `layers` dictionary.

Required keys:

- `layers.bg` (Array) — default: `[]`
- `layers.solid` (Array) — default: `[]`
- `layers.fg` (Array) — default: `[]`

Each element of a layer array is a **cell tuple**:

```text
[x, y, ax, ay]
```

Requirements:

- Must be an Array of length **exactly 4**.
- All four values are interpreted as integers.
- `ax` and `ay` must be **>= 0**.

Out-of-spec values are rejected during validation/canonicalization.

## Compatibility rules (what changes are allowed)

These rules are written for long-term stability of editor assets and client/server determinism.

### Allowed changes (backward compatible)

- **Adding new optional keys** elsewhere in the full map object is generally safe if:
	- both client and server ignore them for simulation and checksum, and
	- tools preserve or intentionally strip them.

- **Adding new fields to the tileset definition** (`tiles_def.json`) is generally safe, as long as defaults exist and old runtimes can ignore unknown keys.

### Changes that require a format bump / coordinated rollout

- Changing the meaning of `[x, y, ax, ay]` (order, type, coordinate system).
- Adding new stored tile layers beyond `bg|solid|fg` **that must affect gameplay or determinism**.
	- Current canonicalization/checksum only incorporates `layers.bg`, `layers.solid`, and `layers.fg`.
	- If a new layer must be authoritative, the canonicalizer and checksum inputs must be updated on **both client and server**.

- Changing boundary handling, duplicate handling, or sorting rules (see “Canonicalization”).

### Canonicalization rules (determinism contract)

When the map is normalized and canonicalized:

- Missing `layers.bg/solid/fg` are defaulted to empty arrays.
- Invalid cells are rejected.
- Boundary cells are excluded (see below).
- Duplicate placements in the same layer at the same `(x,y)`: **last wins**.
- Output cell arrays are sorted by `(x, y, ax, ay)`.

These rules exist so different tools can emit tiles in any order, but still converge on the same canonical representation and checksum.

## Boundary rules

The **outermost tile ring** is reserved and generated.

- Tiles where `x==0` or `y==0` or `x==w-1` or `y==h-1` are considered “on boundary”.
- Boundary tiles are **not stored** in canonical output.
- Tools should avoid writing boundary tiles; if present, they should be dropped during canonicalization.

## Forbidden coupling (what the tilemap must NOT contain)

The tilemap is deliberately minimal: it stores tile *identifiers*, not tile *behavior*.

Forbidden / out of scope for tilemap storage:

- Physics shapes, collision polygons, restitution/friction values, or any per-tile physics tuning.
- “This tile is solid” flags stored in the map.
- Render decisions beyond `bg|solid|fg` buckets.
- Any runtime-only state (e.g., door open/closed).

Source-of-truth rules:

- **Collision and special behavior come from the tileset definition** (`tiles_def.json`).
	- `layers.solid` is only the set of *candidate* solid tiles.
	- Whether a candidate actually collides is determined by the tile’s `solid` property.
	- Tiles marked as `door` are treated as dynamic and are excluded from static solids.

## Canonical examples

### Example A: Minimal tilemap (no tiles)

```json
{
	"layers": {
		"bg": [],
		"solid": [],
		"fg": []
	}
}
```

### Example B: Typical sparse placement

```json
{
	"layers": {
		"bg": [
			[10, 10, 0, 2]
		],
		"solid": [
			[11, 10, 1, 2],
			[12, 10, 1, 2]
		],
		"fg": []
	}
}
```

### Example C: Duplicate placement (“last wins” before sorting)

Input (two entries claim `(x,y)=(5,5)` in the same layer):

```json
{
	"layers": {
		"bg": [],
		"solid": [
			[5, 5, 1, 1],
			[5, 5, 9, 9]
		],
		"fg": []
	}
}
```

Canonical output contains only the last one at `(5,5)`:

```json
{
	"layers": {
		"bg": [],
		"solid": [
			[5, 5, 9, 9]
		],
		"fg": []
	}
}
```

### Example D: Boundary tiles are dropped

Given a 64x64 map (`w=64`, `h=64`), any tile at `x=0`/`y=0`/`x=63`/`y=63` is on the boundary and is excluded from canonical output.

```json
{
	"layers": {
		"bg": [],
		"solid": [
			[0, 10, 1, 2],
			[10, 0, 1, 2],
			[63, 10, 1, 2],
			[10, 63, 1, 2],
			[10, 10, 1, 2]
		],
		"fg": []
	}
}
```

Canonical output keeps only the non-boundary cell:

```json
{
	"layers": {
		"bg": [],
		"solid": [
			[10, 10, 1, 2]
		],
		"fg": []
	}
}
```

