# driftline

A small Godot 4 project with an authoritative server tick, a client with prediction/reconciliation, and a built-in tile map editor.

## Project Layout

- `client/`: Godot client scenes and scripts
- `server/`: headless/host server scripts and run scripts
- `shared/`: deterministic shared simulation + network packet types
- `tools/`: one-off utility scripts
- `assets/tilesets/`: runtime tileset packages (image + defs + manifest)

## Versioning

Project version is stored in `VERSION` as:

- `MAJOR.MINOR.REVISION`

Rules:

- **REVISION**: small changes/fixes
- **MINOR**: large feature additions
- **MAJOR**: huge milestones

Bump helper:

- `powershell -NoProfile -ExecutionPolicy Bypass -File tools/bump_version.ps1 -Part revision`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools/bump_version.ps1 -Part minor`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools/bump_version.ps1 -Part major`

## Tile Definitions (Source of Truth)

Tile behavior is defined in `tiles_def.json`.

Preferred location (tileset packages):

- `assets/tilesets/<tileset_name>/tiles_def.json`

Legacy location (still supported):

- `client/graphics/tilesets/<tileset_name>/tiles_def.json`

Key properties:

- `solid`: whether the tile should be collidable.
- `layer` (tileset packages) / `render_layer` (legacy): where the tile should draw (`bg`/`mid`/`fg` vs `bg`/`solid`/`fg`).
- `safe_zone`: marker used for gameplay rules (non-colliding by default).
- `door`: marker for door animation frames.

On load, map tiles are routed into the correct render layer based on `render_layer`, and collision is derived from the map's `solid` candidates filtered by `solid` from `tiles_def.json`.

Format docs (recommended for learning):

- `docs/map_format_v1.md` (overview)
- `docs/formats/map.schema.md` (full schema + checksum rules)
- `docs/formats/tilemap.schema.md` (what `[x,y,ax,ay]` means)
- `docs/formats/tiles_def.schema.md` (tile behavior: `solid`, doors, render layers)

## Tilemap Editor (Runtime Tool)

There is a separate runtime tool scene for editing tileset metadata:

- `tools/tilemap_editor/TilemapEditor.tscn`

It can import a PNG, display a zoomable grid, edit per-tile metadata, and save/load tileset packages under `assets/tilesets/<tileset_name>/`.

## Running

### Server

Server reads boot configuration from `user://server_config.json` first; if missing, it falls back to `res://server_config.json`.

This file is a strict, versioned JSON contract (no silent defaults).

Example:

```json
{
	"format": "driftline.server_config",
	"schema_version": 2,
	"default_map": "res://maps/default.json",
	"ruleset": "res://rulesets/base.json"
}
```

See schema docs:

- `docs/formats/server_config.schema.md`
- `docs/formats/ruleset.schema.md`

From VS Code you can run the provided task:

- `run server (ctrl+c to stop)`

Or directly:

- `server/run_server.ps1`
- `server/run_server.cmd`

### Client

Open the project in the Godot editor and run.

In-game:

- `Esc`: toggle the in-game menu (non-blocking)
- In the menu: "Back to Menu" returns to the connection screen

Abilities (default bindings):

- `Shift` (hold) + thrust: afterburner (drains energy)
- `Z`: toggle stealth
- `X`: toggle cloak
- `C`: toggle XRadar
- `V`: toggle AntiWarp

## Map Editor

Open the in-project map editor with `M` from the client.

Controls (editor):

- Mouse: move cursor (tile under mouse)
- `LMB` drag: rectangle fill
- `Shift` + `LMB` drag: rectangle outline
- `Space`: place tile at cursor
- `RMB` or `Backspace`: erase tile at cursor
- `WASD`: move camera (cursor remains mouse-controlled)
- Mouse wheel or `+`/`-`: zoom
- `1` / `2` / `3`: zoom presets
- `MMB` drag or `Space`+`LMB` drag: pan
- `Tab`: cycle layer (`bg` / `solid` / `fg`)
- `Q`: open tile palette (click a tile to select; `Esc` closes)
- `Shift+Q` / `Shift+E`: cycle favorite tiles
- `Ctrl+N`: new map (choose size presets or custom size)
- `Ctrl+S`: save map JSON to `user://maps` and copy the JSON to clipboard (hold `Shift` to also print it)
- `Ctrl+O`: load map (shows a picker if there are multiple)
- `Ctrl+Shift+O`: load newest map directly
- `Ctrl+T`: cycle tileset packages under `assets/tilesets/`

Tile metadata (editor):

- The right-side Tile Properties panel edits per-atlas tile metadata in the tileset package `tiles_def.json` when available (fallback: `client/graphics/tilesets/<tileset>/tiles_meta.json`).
- Changes apply immediately (collision cache, overlays, and test puck).
- `T`: toggle test puck mode. In test mode: click to shoot; right click resets.

Map sizes in the editor UI are in pixels (multiples of 16). Internally the map is stored in tiles.

## Networking / Simulation Notes

- Server runs an authoritative fixed tick.
- Client sends input commands; server broadcasts snapshots.
- Core simulation logic lives in `shared/` so both sides agree on movement/collisions.
- Server spawn locations can come from map `entities` with `type="spawn"`.
- Wall-bounce sound is triggered from shared collision events (client-side audio).

## Bots (Headless Clients)

Driftline includes a headless bot client script:

- `res://client/bot_client.gd`

Bots connect to the server as normal clients and generate input locally. They **do not** bypass authoritative rules:

- Safe zones are enforced by shared action validation. Bots may still press fire in safe zones to trigger the existing “brake” behavior, but offensive output is still rejected.

Bot AI is intentionally *not* perfect information:

- Targeting uses a perception layer with periodic updates, limited FOV/range, short memory, LOS uncertainty, and brief pursuit of last-known positions.

Bots have deterministic per-bot “personality” constants derived from `bot_id` / `ship_id`:

- Reaction timing, aim error baseline, braking style, aggression/chase persistence, and disengage thresholds.

This makes each bot’s style consistent across runs/replays for a given `ship_id`, while keeping the authoritative simulation deterministic and unchanged.

## Prizes (Server Authoritative)

Driftline includes server-authoritative "greens" (prizes): spawn/despawn/pickup are
deterministic on the server and replicated to clients via snapshots.

Config lives in `server.cfg`:

- `[Prize]`: spawn timing and limits (seconds; converted to ticks on load)
- `[PrizeWeight]`: relative probability weights per prize kind

Config precedence is layered (defaults then overrides): `res://server.cfg` then `user://server.cfg`.

On pickup, the client plays `res://client/audio/prize.wav`.

## License

No license specified yet. Add one if/when you want to open-source the project.

## Testing policy

Driftline uses two testing layers:

1) **Required** dependency-free headless contract tests for all versioned JSON formats.
2) Optional future unit/integration tests (GUT/GdUnit4) only if gameplay complexity demands it.

Run contract tests:

```bash
godot --headless --quit --path . --script res://tests/run_contract_tests.gd
```

Run smoke (sanity) tests:

```bash
godot --headless --quit --path . --script res://tests/run_smoke_tests.gd
```

CI runs both contract tests and smoke tests on push and pull requests.
