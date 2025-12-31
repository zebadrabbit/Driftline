# Changelog

This project didn’t previously have a formal changelog. The entries below were reconstructed from recent development session notes and may be incomplete.

## Unreleased

### Added

- Authoritative server + client architecture with deterministic shared simulation in `shared/`.
- New shared ship simulation script (`shared/drift_ship.gd`) used by both server and client-side prediction.
- Map editor quality-of-life features:
  - Tile palette popup (toggle `Q`) built from the first `TileSetAtlasSource`.
  - Palette blocks map editing while open; click-to-select sets `selected_atlas_coords` and closes.
  - Favorite tile cycling moved to `Shift+Q` / `Shift+E`.
  - New Map dialog (`Ctrl+N`) with size presets and custom width/height.
  - Load Map picker (`Ctrl+O`) for selecting among many saved maps.
  - Save copies map JSON to clipboard for easy paste.
  - Paste/import map JSON from clipboard (`Ctrl+V`) with safe validation and visible error messages.
  - Entity layer editing mode (`F`) with basic entity placement/removal and persistence in map JSON.
  - Rectangle fill tool with preview; `Shift` for outline.
  - Mouse-only cursor selection and WASD camera navigation decoupled.
  - Translucent tile cursor rendering (auto texture fallback if missing).
  - Starfield background in the editor scene.
- Client connection UI (client does not silently run “solo”).
- In-game non-blocking ESC menu with "Back to Menu".
- Reverse thrust input propagated through shared input types and packet serialization.
- Deterministic map validation + canonical SHA-256 checksum (shared) and welcome-handshake verification.
- Map format spec: `docs/map_format_v1.md`.

### Changed

- Default map content restored/created with boundary walls and basic obstacles, plus a safezone area.
- Client scene wiring corrected so the intended main scene is used.
- Server spawn selection now prefers map `entities` with `type="spawn"` when present.
- Collision handling in the shared world simulation iterated to address wall-phasing and bounce feel.
- UI polish: connection/menu screen centered and map visuals hidden underneath while the overlay is visible.

### Fixed

- Server crash on missing ship data ("Invalid access to property 'ships' on Nil") by introducing shared ship logic and tightening types.
- Server exits cleanly if the listen port is already in use.
- Map editor keybind conflicts where `Ctrl+S` / `Ctrl+O` could also trigger movement.
- Tile palette tileset scanning compatibility by using `TileSet.get_source_count()` + `get_source_id(i)` (instead of `get_source_ids()`).
- Client-side map load logging and collision-layer parsing (aligning with LevelIO return values).
- Wall bounce sound triggering again when collisions are resolved by the shared simulation.
