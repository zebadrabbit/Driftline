# Changelog

This project didn’t previously have a formal changelog. The entries below were reconstructed from recent development session notes and may be incomplete.

## 0.5.3 - 2025-12-31

### Added

- `tiles_def.json`-driven tile behavior via `shared/drift_tile_defs.gd` (render-layer routing + collision filtering).

### Changed

- Rendering now routes tiles to `bg`/`solid`/`fg` based on `render_layer` in `tiles_def.json` (not strictly the map JSON layer arrays).

### Fixed

- Server startup failures caused by malformed map layer entries in `maps/default.json`.
- `server.cfg` parsing by quoting string values for Godot `ConfigFile`.

## 0.5.4 - 2025-12-31

### Added

- Map editor tile metadata authoring (`tiles_meta.json`) with a right-side Tile Properties panel (layer/solid/restitution/friction).
- Editor overlays for solid cells and restitution visualization.
- Editor test puck sandbox (deterministic fixed-step) driven by the live collision cache.
- Zoom and pan controls for editing at high DPI.

## 0.5.5 - 2026-01-02

### Added

- Server-authoritative prize system (spawn/despawn/pickup) replicated to clients.
- Prize configuration via `server.cfg` (`[Prize]` + `[PrizeWeight]`) with layered defaults (`res://`) and overrides (`user://`).
- Rotating 10-frame prize sprite sheet rendering and pickup SFX (`res://client/audio/prize.wav`).
- Reliable prize pickup event packet (`PKT_PRIZE_EVENT`) to ensure client-side SFX/FX delivery.
- Headless smoke test: `prizes_spawn_walkable`.

### Changed

- Bullet ruleset supports optional bounce controls (`bounces`, `bounce_restitution`) and per-level profiles.
- Prize availability scales with player count (clamped) so larger matches don’t feel starved.

### Fixed

- Prize pickup SFX could be missed due to event timing; server now buffers prize events between snapshot sends.

## 0.5.6 - 2026-01-04

### Added

- Combat-only death (only when damage reduces energy to zero) with automatic respawn after a configurable delay.
- Deterministic snapshot replication for death state (dead ships cannot move/act/target until respawn).
- Bot imperfect-information targeting: periodic perception updates with FOV/range limits, short memory, LOS uncertainty, and brief pursuit of last-known positions.
- Per-bot personality constants (seeded from bot_id/ship_id) affecting reaction timing, aim error, braking style, aggression/persistence, and energy disengage thresholds.
- Bot “social” behaviors (small, occasional): safe-zone hesitation, circling instead of hard commits, and target-switch indecision under multi-threat pressure.

### Changed

- Bullet progression supports level-based tactical profiles (e.g. bounce/multishot/shrapnel/spread/cooldown) replicated deterministically.
- Safe-zone bot braking (“fire-to-stop”) is gated (cooldown + probability + speed threshold) to avoid robotic perfect braking.

## 0.5.7 - 2026-01-04

### Added

- Ruleset knob `zones.safe_zone_max_ms` enforcing a server-authoritative safe-zone time cap.
- Ruleset UI thresholds `ui.low_energy_frac` and `ui.critical_energy_frac` with strict validation and HUD warnings.
- Team/frequency support (`ship.freq`) replicated via snapshots; client friendliness rendering derives from `freq`.
- Friendly-fire control via `combat.friendly_fire` (safe-zone and spawn protection still take precedence).
- Set-frequency request feedback packet `PKT_SET_FREQ_RESULT` with stable enum reasons (client logs only; freq still authoritative via snapshots).
- Help ticker priority interrupts (client-only) triggered by authoritative state edges (safe-zone entry, first death, critical energy).
- Client team color helpers in `client/team_colors.gd`:
  - Role/condition flags with objective-carrier priority color override.
  - Radar/minimap mapping helpers (dot color + self shape hints).
- Headless smoke tests covering set-freq rejection reasons and team color mapping/overrides.

## Unreleased

### Added

- Client settings/options UI.
- Server CLI flags `--debug_combat` / `--debug_combat_verbose` for dev-only combat diagnostics.
- Deterministic replay support (client) and world-hash/determinism guardrails.
- Authoritative server + client architecture with deterministic shared simulation in `shared/`.
- Tileset packages under `assets/tilesets/<tileset_name>/` (`tiles.png`, `tileset.json`, `tiles_def.json`).
- Runtime Tilemap Editor tool scene: `tools/tilemap_editor/TilemapEditor.tscn`.
- Shared tileset modules: `shared/tileset/tileset_data.gd` and `shared/tileset/tileset_io.gd`.
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
  - `Ctrl+T` to cycle tileset packages from `assets/tilesets/`.
- Client connection UI (client does not silently run “solo”).
- In-game non-blocking ESC menu with "Back to Menu".
- Reverse thrust input propagated through shared input types and packet serialization.
- Deterministic map validation + canonical SHA-256 checksum (shared) and welcome-handshake verification.
- Map format spec: `docs/map_format_v1.md`.
- Server-driven map selection via `server.cfg` (single/rotation/random) using `ConfigFile`.
- MapManifest in welcome handshake (`map_path`, `map_hash`, optional `map_version`).
- Deterministic tick-based energy system (integer points + recharge delay) replicated in snapshots.
- Ruleset schema v2 requiring explicit energy/cost tuning keys (legacy v1 rulesets still supported).
- Smoke test: `energy_deterministic_recharge_and_costs`.

### Changed

- Additional client UX polish and determinism checks.
- Default map content restored/created with boundary walls and basic obstacles, plus a safezone area.
- Client scene wiring corrected so the intended main scene is used.
- Server spawn selection now prefers map `entities` with `type="spawn"` when present.
- Collision handling in the shared world simulation iterated to address wall-phasing and bounce feel.
- UI polish: connection/menu screen centered and map visuals hidden underneath while the overlay is visible.
- HUD energy readout now reports `energy_current/energy_max` and recharge wait ticks.
- Bullet tuning (Option A): default bullet speed is 760 px/s with 0.5s lifetime (30 ticks) to preserve ~380px range and improve readability.

### Fixed

- Boost thrust SFX (including Shift-chord behavior).
- Server crash on missing ship data ("Invalid access to property 'ships' on Nil") by introducing shared ship logic and tightening types.
- Server exits cleanly if the listen port is already in use.
- Map editor keybind conflicts where `Ctrl+S` / `Ctrl+O` could also trigger movement.
- Tile palette tileset scanning compatibility by using `TileSet.get_source_count()` + `get_source_id(i)` (instead of `get_source_ids()`).
- Client-side map load logging and collision-layer parsing (aligning with LevelIO return values).
- Wall bounce sound triggering again when collisions are resolved by the shared simulation.
- Projectile tunneling: bullets now use swept/continuous collision against solid tiles (segment cast per tick), with a smoke test to prevent regressions.
- Ruleset bullet tuning is now authoritative by default (non-versioned `server.cfg` ship weapon fields no longer override bullet speed/delay unless explicitly enabled).
- Baseline bullet firing cadence no longer defaults to every tick (cooldown now enforced via ruleset `cooldown_ticks`).
