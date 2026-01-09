# Ruleset Schema (`rulesets/*.json`)

This document specifies the **ruleset contract** used by Driftline to hold gameplay tuning values.

- Format identity: `"driftline.ruleset"`
- Schema version: `2` (latest)

The validator also supports schema version `1` for legacy rulesets.

Rulesets are **data only**. They declare parameters; the engine interprets them. Unknown keys are rejected.

## Non-negotiable rules

- All persistent JSON artifacts MUST include `format` and `schema_version`.
- Loaders MUST refuse to load files missing these fields.
- Unknown `format` or `schema_version` MUST fail loudly.
- Unknown keys MUST fail loudly at all levels (top-level and nested objects).
- No normalization, auto-fill, or silent defaults.

## Schema

Top-level object:

```json
{
  "format": "driftline.ruleset",
  "schema_version": 2,
  "physics": {
    "wall_restitution": 0.6,
    "tangent_damping": 0.5,
    "ship_turn_rate": 3.5,
    "ship_thrust_accel": 520.0,
    "ship_reverse_accel": 400.0,
    "ship_max_speed": 720.0,
    "ship_base_drag": 0.35,
    "ship_overspeed_drag": 2.0,
    "ship_bounce_min_normal_speed": 160.0
  },
  "weapons": {
    "ball_friction": 0.98,
    "ball_max_speed": 600.0,
    "ball_kick_speed": 700.0,
    "ball_knock_impulse": 250.0,
    "ball_stick_offset": 18.0,
    "ball_steal_padding": 4.0,
    "bullet": {
      "speed": 950.0,
      "lifetime_s": 0.8,
      "muzzle_offset": 28.0,
      "bounces": 1,
      "bounce_restitution": 1.0,
      "levels": {
        "1": { "guns": 1 },
        "2": { "guns": 2 },
        "3": { "guns": 3, "multi_fire": true, "bounces": 1 }
      }
    }
  },
  "ships": {
    "1": {
      "weapons": {
        "bullet": {
          "level": 3,
          "multishot": true,
          "bounce": true,
          "guns": 3,
          "multi_fire": true,
          "speed": 1200.0
        }
      }
    }
  },
  "abilities": {
    "afterburner": { "drain_per_sec": 30, "speed_mult_pct": 100, "thrust_mult_pct": 160 },
    "stealth": { "drain_per_sec": 20 },
    "cloak": { "drain_per_sec": 25 },
    "xradar": { "drain_per_sec": 15 },
    "antiwarp": { "drain_per_sec": 35, "radius_px": 200 }
  },
  "energy": {
    "max": 1200,
    "recharge_rate_per_sec": 150,
    "recharge_delay_ms": 300,
    "bullet_energy_cost": 30,
    "multifire_energy_cost": 90,
    "bomb_energy_cost": 150
  },
  "combat": {
    "spawn_protect_ms": 250,
    "respawn_delay_ms": 1500,
    "friendly_fire": false
  },
  "team": {
    "max_freq": 2,
    "force_even": true
  },
  "zones": {
    "safe_zone_max_ms": 15000
  }
}
```

### `zones` (optional, schema v2)

- Type: object
- Unknown keys are rejected.

Zone tuning is declarative data; the engine interprets it.

#### `zones.safe_zone_max_ms` (optional)

- Type: number
- Range: `0..600000`

Maximum cumulative time (in milliseconds) a ship may remain in a safe zone **while alive** before the authoritative sim forces a respawn to a non-safe spawn point.

- `0` disables the limit.

### `ui` (optional, schema v2)

- Type: object
- Unknown keys are rejected.

UI tuning is declarative data; the client interprets it.

#### `ui.low_energy_frac` (optional)

- Type: number
- Range: `0.0..1.0`
- Default (engine): `0.33`

When `energy_current/energy_max <= low_energy_frac`, the HUD energy indicator enters a warning state.

#### `ui.critical_energy_frac` (optional)

- Type: number
- Range: `0.0..1.0`
- Default (engine): `0.15`

When `energy_current/energy_max <= critical_energy_frac`, the HUD energy indicator enters a critical state and the client may display an in-world numeric energy readout.

Constraint: `critical_energy_frac` must be $\le$ `low_energy_frac`.

### `combat` (optional, schema v2)

- Type: object
- Unknown keys are rejected.

Combat tuning is declarative data; the engine interprets it.

#### `combat.friendly_fire` (optional)

- Type: boolean
- Default (engine): `false`

When `false`, the authoritative sim rejects same-team damage (same `ship.freq`).

In FFA mode (`team.max_freq == 0`), friendly-fire is treated as effectively enabled to avoid degenerate "all ships freq=0 -> no damage" behavior.

### `team` (optional, schema v2)

- Type: object
- Unknown keys are rejected.

Team configuration controls authoritative team/frequency assignment.

#### `team.max_freq` (optional)

- Type: integer
- Range: `0..16`
- Default (engine): `2`

If `0`, the game is in FFA mode and ships are assigned `freq = 0`.

If `> 0`, ships are assigned `freq` in `0..max_freq-1` using deterministic auto-balance based on active non-dead ships.

#### `team.force_even` (optional)

- Type: boolean
- Default (engine): `true`

When `true`, the server rejects manual team changes that would make team sizes differ by more than 1 active non-dead ship.

### `format` (required)

- Type: string
- Must equal `"driftline.ruleset"`

### `schema_version` (required)

- Type: integer
- Supported values: `1` (legacy) or `2` (latest)

Schema version `2` is stricter and requires explicit energy tuning keys.

Schema version `2` also introduces **continuous-drain abilities** under `abilities`.

### `physics` (required)

- Type: object
- Unknown keys are rejected.

#### `physics.wall_restitution` (required)

- Type: number
- Range: `0.0..2.0`

Used for wall bounce response in the shared deterministic simulation. Values:

- `0.0` = no bounce (normal component is fully killed)
- `1.0` = perfect elastic reflection (normal speed preserved)
- `> 1.0` = energy gain (allowed for arcade tuning)

#### `physics.tangent_damping` (optional)

- Type: number
- Range: `0.0..1.0`

Applies tangential velocity damping on wall collisions to create SubSpace-style wall sliding.
On impact, the tangential component is multiplied by $(1 - tangent_damping)$.

#### `physics.ship_turn_rate` (optional)

- Type: number
- Range: `0.0..20.0`

Radians per second.

#### `physics.ship_thrust_accel` (optional)

- Type: number
- Range: `0.0..5000.0`

Pixels/s².

#### `physics.ship_reverse_accel` (optional)

- Type: number
- Range: `0.0..5000.0`

Pixels/s².

#### `physics.ship_max_speed` (optional)

- Type: number
- Range: `0.0..5000.0`

Soft speed cap for overspeed drag.

#### `physics.ship_base_drag` (optional)

- Type: number
- Range: `0.0..10.0`

Base exponential drag coefficient (1/s).

#### `physics.ship_overspeed_drag` (optional)

- Type: number
- Range: `0.0..50.0`

Additional drag multiplier when above `ship_max_speed`.

#### `physics.ship_bounce_min_normal_speed` (optional)

- Type: number
- Range: `0.0..2000.0`

Minimum normal component speed required to bounce; below this, normal velocity is killed and the ship slides.

### `weapons` (optional)

- Type: object
- Unknown keys are rejected.

These parameters currently tune the **ball kick** behavior in the shared deterministic sim.

Ruleset-driven bullet tuning is also declared here; the engine interprets it.

#### `weapons.ball_friction` (optional)

- Type: number
- Range: `0.0..1.0`

Multiplier applied each tick to ball velocity.

#### `weapons.ball_max_speed` (optional)

- Type: number
- Range: `0.0..5000.0`

#### `weapons.ball_kick_speed` (optional)

- Type: number
- Range: `0.0..5000.0`

Initial ball speed added on kick.

#### `weapons.ball_knock_impulse` (optional)

- Type: number
- Range: `0.0..5000.0`

Impulse applied to ball when stolen by another ship.

#### `weapons.ball_stick_offset` (optional)

- Type: number
- Range: `0.0..200.0`

Distance (px) from ship center along ship forward axis where the ball sticks.

#### `weapons.ball_steal_padding` (optional)

- Type: number
- Range: `0.0..128.0`

Extra distance (px) beyond `ship_radius + ball_radius` for steal detection.

#### `weapons.bullet` (optional)

- Type: object
- Unknown keys are rejected.

This block tunes the basic bullet firing in the deterministic sim.

Bullets fire on **edge-triggered** `fire` input (press-to-fire) when the ship is **not currently holding the ball**.

##### `weapons.bullet.speed` (optional)

- Type: number
- Range: `0.0..5000.0`

##### `weapons.bullet.damage` (optional)

- Type: integer
- Range: `0..10000`

Damage applied to ships on hit. Driftline currently represents damage as **energy loss**.

##### `weapons.bullet.knock_impulse` (optional)

- Type: number
- Range: `0.0..5000.0`

Impulse applied to the target ship on hit (along bullet velocity direction). `0` disables knock.

##### `weapons.bullet.lifetime_s` (optional)

- Type: number
- Range: `0.0..10.0`

Converted to integer ticks deterministically.

##### `weapons.bullet.muzzle_offset` (optional)

- Type: number
- Range: `0.0..64.0`

Distance (px) from ship center along ship forward axis where bullets spawn.

##### `weapons.bullet.bounces` (optional)

- Type: integer
- Range: `0..16`

Number of wall bounces a bullet is allowed before it is destroyed.

##### `weapons.bullet.bounce_restitution` (optional)

- Type: number
- Range: `0.0..2.0`

Restitution applied to the normal component of bullet velocity on wall bounce.

##### `weapons.bullet.levels` (optional)

- Type: object
- Keys: level as a **string integer** (`"1"`, `"2"`, `"3"`)
- Unknown keys are rejected at all levels.

Per-level bullet profiles.

Supported keys per level:

- `guns` (optional): integer in range `1..8`
- `multi_fire` (optional): boolean
- `speed` (optional): number in range `0.0..5000.0`
- `damage` (optional): integer in range `0..10000`
- `knock_impulse` (optional): number in range `0.0..5000.0`
- `cooldown_ticks` (optional): integer in range `0..120`
- `spread_deg` (optional): number in range `0.0..45.0`
- `shrapnel_count` (optional): integer in range `0..16`
- `shrapnel_speed_mult` (optional): number in range `0.0..2.0`
- `shrapnel_lifetime_s` (optional): number in range `0.0..5.0`
- `shrapnel_cone_deg` (optional): number in range `0.0..360.0`
- `lifetime_s` (optional): number in range `0.0..10.0`
- `muzzle_offset` (optional): number in range `0.0..64.0`
- `bounces` (optional): integer in range `0..16`
- `bounce_restitution` (optional): number in range `0.0..2.0`

### `ships` (optional)

- Type: object
- Keys: ship id as a **string integer** (e.g. "1")
- Unknown keys are rejected at all levels.

Per-ship overrides. Currently supported:

- `ships.<ship_id>.weapons.bullet`

#### `ships.<ship_id>.weapons.bullet` (optional)

- Type: object
- Unknown keys are rejected.

Supported keys:

- `level` (optional): integer in range `1..3`
- `multishot` (optional): boolean (forces `multi_fire = true`)
- `bounce` (optional): boolean (forces `bounces >= 1`)
- `guns` (optional): integer in range `1..8`
- `multi_fire` (optional): boolean
- `speed` (optional): number in range `0.0..5000.0`
- `lifetime_s` (optional): number in range `0.0..10.0`
- `muzzle_offset` (optional): number in range `0.0..64.0`
- `bounces` (optional): integer in range `0..16`
- `bounce_restitution` (optional): number in range `0.0..2.0`

### `abilities` (required in schema v2)

- Type: object
- Unknown keys are rejected.

Schema v2 requires the following blocks:

- `abilities.afterburner`
- `abilities.stealth`
- `abilities.cloak`
- `abilities.xradar`
- `abilities.antiwarp`

Each block must include:

- `drain_per_sec` (required)
  - Type: number
  - Range: `0..100000`

Optional fields:

- `abilities.afterburner.speed_mult_pct` (optional)
  - Type: number
  - Range: `0..500`

- `abilities.afterburner.thrust_mult_pct` (optional)
  - Type: number
  - Range: `0..500`

- `abilities.antiwarp.radius_px` (optional)
  - Type: number
  - Range: `0..100000`

All ability behavior is interpreted by the engine; these are declarative tuning knobs only.

### `energy` (required in schema v2; optional in schema v1)

- Type: object
- Unknown keys are rejected.

Energy is currently a tuning block shared to clients during handshake for consistency.

In schema v2, sustained drains are configured under `abilities.*.drain_per_sec`.

In schema v1 (legacy), afterburner drain may appear as:

- `energy.afterburner_drain_per_s` (legacy)
- `energy.afterburner_drain_per_sec` (legacy alias)

#### `energy.max` (optional)

- Type: number
- Range: `0.0..100000.0`

#### `energy.regen_per_s` (optional)

- Type: number
- Range: `0.0..100000.0`

Legacy name for `energy.recharge_rate_per_sec`. If both are present, `recharge_rate_per_sec` wins.

#### `energy.recharge_rate_per_sec` (optional)

- Type: number
- Range: `0.0..100000.0`

Recharge rate in **energy points per second**.

#### `energy.recharge_delay_ms` (optional)

- Type: number
- Range: `0.0..10000.0`

Recharge delay in **milliseconds** after energy is spent. Converted to integer ticks deterministically.

#### `energy.afterburner_drain_per_s` (optional)

- Type: number
- Range: `0.0..100000.0`

#### `energy.bullet_energy_cost` (optional)

- Type: number
- Range: `0.0..10000.0`

Energy cost per bullet trigger.

#### `energy.multifire_energy_cost` (optional)

- Type: number
- Range: `0.0..10000.0`

Energy cost for multi-fire trigger.

#### `energy.bomb_energy_cost` (optional)

- Type: number
- Range: `0.0..10000.0`

Energy cost per bomb (when implemented).

## Defaults

Optional tuning keys may be omitted, but the engine will use its built-in defaults.
Because silent defaults are forbidden, missing optional fields produce **warnings** during ruleset validation.
