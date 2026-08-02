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

## 0.7.0 - 2026-08-01

### Added

- **Chat commands and `%` macros** (`client/scripts/ui/chat_commands.gd`): `?help`,
  `?ping`, `?packetloss`, `?status`, `?flags`, `?team`, `?kill`, `?lines=N`,
  `?ignore <name>`, and `=NNNN` frequency change. Messages expand `%coord %area
  %selfname %freq %bounty %flags %energy %shield %super %killer %killed %red
  %redname %redflags %redbounty`, with `%%` as the literal-percent escape. Unknown
  `?` commands fall through to public chat, as in SubSpace.
- **Multifire toggle key.** The 3-shot spread logic already existed but could only be
  switched on by the prize. New `multi_fire_capable` state separates owning the
  upgrade from having it switched on, so the key cannot conjure it from nothing.
- **King of the Hill** from the `[King]` config block: per-ship crown state with all
  six keys (`ExpireTime`, `DeathCount`, `NonCrownAdjustTime`, `NonCrownMinimumBounty`,
  `CrownRecoverKills`, `RewardFactor`), an append-only snapshot section, server round
  flow with arena announcements, and a HUD `KING m:ss` countdown.
- **Game-mode profiles**: `[Game] Mode` in `server.cfg` selects `res://modes/<mode>.cfg`,
  a third config layer between `res://` and `user://`. Profiles for `war`, `chaos`,
  `king`, `rabbit`, `soccer`, `speed`, `jackpot` and `alpha`, generated from the
  original per-arena `SERVER.CFG` files.
- **Player stat box** with the six SubSpace F2 modes (names / points / sorted by
  points / grouped by team / win-loss / frequency statistics), replacing the single
  hardcoded F9 scoreboard.
- `F11` spectator toggle and `F12` ship cycle.
- Ability ownership: `*Status` values now distinguish `1` (must be prized) from `2`
  (start with it). Only the Spider starts with stealth; only the Spider and Shark can
  ever receive cloak.
- `Glue` wired as the Engine Shutdown prize with a severe ~40 s variant; negative
  QuickCharge now empties the energy bar ("Energy Depleted").
- 26 original sounds wired: per-level bomb/mine/EMP fire, EMP detonation, ability
  toggles, multifire on/off, decoy, rocket, victory cues.
- Previously-dead art wired: EMP burst, super-shield bubble, rocket exhaust plume, the
  expiring-crown sheet, and per-ship wreckage on death.
- Cloak now hides enemy ships in the world view (XRadar counters it); stealth stays
  radar-only, matching `Screen Items.pdf`.
- **Map editor**: undo/redo (`Ctrl+Z` / `Ctrl+Y`) with rect and flood fills as single
  steps, line (`L`), bucket fill (`G`) and eyedropper (`I`) tools, an `F1` hotkey
  overlay replacing the permanent 3-line label, and `F10` switching between the map
  and tileset editors.
- Smoke tests for chat commands, macros, multifire, negative prizes, King of the Hill,
  ball gating, per-ship starting loadouts, ability ownership and item caps, the map
  editor's undo stack and tools, and the music library.

### Changed

- **Default keybindings now follow the original SubSpace 1.34 layout**: arrow keys to
  fly, `Ctrl` guns, `Tab` bombs, `Shift`+`Tab` mines, `Home`/`Shift`+`Home` for
  stealth/cloak, `End`/`Shift`+`End` for XRadar/AntiWarp, `Del`/`Shift`+`Del` for
  multifire/burst, `Ins`/`Shift`+`Ins` for warp/portal, and `F3`-`F6` for
  rocket/brick/decoy/thor. Saved rebinds in `user://settings.json` are unaffected.
- Powerball is gated on the map containing goal entities, derived independently by
  both sides from the same map file.
- Per-ship item capacities (`DecoyMax`, `ThorMax`, `BrickMax`, `RocketMax`) are
  honoured instead of a hardcoded cap of 10.
- Shrapnel prizes add `ShrapnelRate` up to `ShrapnelMax`; the Weasel's max of 0 means
  its EMP bombs never throw shrapnel.
- Help ticker text rewritten for the new bindings and chat commands.
- Smoke suite restored to green after six weeks red; six stale test expectations
  re-baselined and the determinism golden hash regenerated (again for ball gating).

### Fixed

- **Portal never worked in multiplayer**: the server built its `DriftInputCmd` without
  `portal_btn`, so the beacon appeared only in client prediction and was then
  reconciled away.
- Reconciliation dropped the new capability flags (`multi_fire_capable`, the four
  ability-ownership bits, crown state), which would have desynced prediction.
- `_is_spectating` was set on spectate but never cleared on re-entry, leaving the
  camera locked to the spectate target.
- `_king_on_kill` stripped the victim's crown before deciding the attacker's reward, so
  `CrownRecoverKills` could never fire.
- The client accepted only `goal` entities where the server also accepted `base`, so
  the two sides could disagree about whether a map has a ball.
- `drift_open_map_editor` defaulted to the Down arrow, which is now thrust-reverse.
- **Music**: the jukebox's directory scan matched only raw audio files, so an exported
  build (which ships `Track.ogg.import`) would have had an empty playlist and run
  silent. It now also handles the `.import` form. A single unloadable track no longer
  stops music for the session, `Ctrl+M` crossfades to the other player instead of
  cutting the current one, and an empty playlist no longer divides by zero.
- Deleted `client/scenes/editor/map_editor.gd`, an unused Godot template stub.
- Clean checkouts could not load the client at all: `tools/tilemap_editor/` was never committed despite being `preload()`ed by `client/client_main.gd`.
- Arena bounds (`ARENA_MIN`/`MAX`/`CENTER`, `HILL_CENTER`) were process-global `static var`s, so every `DriftWorld` in a process shared one arena and construction order changed simulation results. They are now per-world instance state; the `DriftConstants` statics remain only as a mirror for client presentation code.
- Player usernames arrived empty: `unpack_hello()` did not index `get_data()`'s `[error, PackedByteArray]` return.
- `set_map_dimensions()` now recenters the powerball, matching what the server already does on match start and after each goal.

### Removed

- Duplicate `(1)`-suffixed music files; the library is now 20 distinct tracks.

## 0.6.0 - 2026-07-20

### Added

- SubSpace 1:1 parity effort (`plans/subspace-parity.md`), using reference material in `original_content/` (server.cfg, TEMPLATE.SSS, main.c, original .lvl maps, graphics, sounds).
- Original SubSpace sprite wiring (flags/goals/crown/wall/warp/shield/powerball/bullets/mines/bombs/Thor) and 8192x8192 map with minimap prize display.
- Bounty and kill scoring matching original reward/bounty-increase rules.
- `tools/gen_map.py`: procedural 1024x1024 arena generator.
- `tools/lvl_import.py`: original `.lvl` map importer (atlas ⇔ original tile id mapping) plus 8 converted maps in `maps/imported/` (castle, soccer, romp, alpha, jollyr, spiral, nivag, melted).
- Wormhole simulation (gravity well + teleport, warp effect events); client now loads the server-announced map instead of hard-failing.
- Turf flags (`FlagMode 2`): tile 170 claimable by touch, team ownership.
- Original event sounds wired (warp/goal/flag/repel/thor/explode).
- Per-ship classic movement/energy stats read directly from `TEMPLATE.SSS` units (speed/rotation/thrust, energy max/recharge, per-ship ability drains, item counts).
- Classic damage economy: bullet/bomb/mine damage by level, burst pellets, level-scaled costs and delays.
- Thor implemented as a wall-piercing level-4 proximity bomb; burst pellets arm only after a wall bounce.
- Classic radar parity: red enemy-flag-carrier dots, flashing team-captured flag colors; HUD shows personal/team frags, shield countdown, and super status.
- Classic portal return beacon: drop a 60s return point, second press warps back and clears it; HUD `PT:` timer.

### Changed

- Gun level now controls damage only; `MultiFire`/`DoubleBarrel` control barrel count/spread separately (previously conflated).

### Fixed

- Ruleset unit misreads discovered during the original `server.cfg` parity audit (e.g. `DamageFactor` is wall-bounce damage, not a weapon damage multiplier).

## 0.5.8 - 2026-01-11

### Added

- Ruleset tuning knobs for high-speed handling penalties: `physics.high_speed_*`.
- Ruleset tuning knobs for speed-scaled afterburner strain: `abilities.afterburner.strain_*`.
- Smoke test: `projectile_velocity_inheritance_sanity` (logs ship/bullet velocities for forward/backward/stationary scenarios).

### Changed

- Bullets now inherit firing ship velocity once at spawn (SubSpace-style), preventing ships from outrunning their own projectiles without inflating bullet base speed.
- Afterburner drain now scales with speed near max speed to discourage indefinite cruising.
- Turning and reverse thrust are reduced near max speed to make sustained max-speed travel less controllable.
