# SubSpace/Continuum 1:1 Parity Plan

Goal: make driftline play like original SubSpace 1.34 / Continuum, using the
reference material in `original_content/` (server.cfg, TEMPLATE.SSS, main.c,
original .lvl maps, 106 graphics, 154 sounds).

Constraint: sole dev — turrets/attaching deferred (untestable solo). Everything
else is single-client testable against bots.

## Key discovery

`assets/tilesets/subspace_base/tiles.png` keeps the original 19-wide tile
layout: atlas `(x,y)` ⇔ original tile id `y*19 + x + 1`. Safe tile (18,8)=171,
doors (9..16,8)=162..169 — identical to VIE special tile IDs. So .lvl import
is a direct id→atlas mapping, no remapping table needed.

## Phase 1 — .lvl import (DONE = maps in `maps/imported/`)

- `tools/lvl_import.py`: parse optional BMP tileset header (file starts `BM`;
  tile data begins at the BMP's file-size offset), then 4-byte little-endian
  records: bits 0-11 x, 12-23 y, 24-31 tile id. Arena is 1024×1024.
- Tile id mapping:
  - 1–161: solid, atlas `((id-1)%19, (id-1)//19)`
  - 162–169: doors (already animate/behave in engine)
  - 170: turf flag → `flag` entity (team 0 = neutral)
  - 171: safe zone (fg, non-solid)
  - 172: goal → goal tiles; also emit `goal` entity clusters
  - 173–175 fly-over, 176–190 fly-under: fg/bg decor, non-solid
  - 216 small asteroid, 217 big asteroid (2×2), 218 small asteroid 2,
    219 station (6×6): solid footprint (destructible asteroids = later)
  - 220 wormhole (5×5): `wormhole` entity at center
  - 252 brick, 253-255 internal: skip
- Convert bundled maps: `_castle` (WAR), `_soccer`/`_romp` (SOCCER),
  `_alpha`, `_jollyr` (CHAOS/SPEED), `_spiral` (JACKPOT), `_nivag` (KING),
  `_melted` (RABBIT).
- Add spawn entities (original spawns center-radius based; use safe zones or
  map center).
- LVZ (Continuum decor overlays): later, low gameplay value. Original 1.34
  didn't have LVZ; skip for 1:1-with-1.34.

## Phase 2 — special-tile gameplay

- **Wormholes**: gravity well (pull accel ∝ 1/r², `Wormhole:GravityAccel`,
  `SwitchTime` from server.cfg) + teleport to another wormhole. Deterministic,
  runs in `step_tick()`. Client: `warppnt.png` animation + `warp.wav`.
- **Turf flags** (FlagMode 2): flag tiles claimable by touch, team ownership,
  `KillPointsPerFlag` bonus. Reuses existing flag replication.
- **Goal tiles**: map-driven goal zones for soccer maps (currently goals are
  entities only; importer emits entities so no sim change needed initially).

## Phase 3 — flag game completion

- FlagMode 0/1 (dropped flags unowned/owned, carry-all/own-all to win),
  `FlagReward` victory formula (players² × FlagReward / 1000), flag reset
  timer, `FlagDropDelay`, flagger adjustments (speed/thrust/fire-cost/damage
  multipliers, `FlaggerKillMultiplier`).
- Win → score event broadcast + arena reset (mirrors existing CTF/powerball
  match flow).

## Phase 4 — feel parity

- **Sounds**: wire remaining originals — flag.wav, goal.wav, wormhole/warp,
  bong chat sounds, ship engine loops (wbroll/jvroll/…), prize/bong on green.
- **Ruleset audit**: reconcile classic/*.json against original server.cfg
  values with original units (speed = px/10s? verify in main.c; times in
  centiseconds; energy raw).
- **Energy viewing**: `SeeEnergy` — show teammate energy bars (Terrier/spec).
- **Radar**: `FlaggerOnRadar` red flaggers, X-radar cloak reveal rules.
- **Kill messages**: original green-text style + bong.

## Phase 5 — later / deferred

- Turrets/attaching (deferred: untestable solo).
- LVZ overlay rendering.
- Destructible asteroids, station services.
- Persistent scores between sessions; squads/banners.
- Jackpot game (`JackpotBountyPercent`).

## Commit discipline

One commit per completed slice, tests green (modulo the 8 known pre-existing
Godot 4.6.1 failures documented in memory).
