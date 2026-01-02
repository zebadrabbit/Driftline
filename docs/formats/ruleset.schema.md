# Ruleset Schema (`rulesets/*.json`)

This document specifies the **ruleset contract** used by Driftline to hold gameplay tuning values.

- Format identity: `"driftline.ruleset"`
- Schema version: `1`

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
  "schema_version": 1,
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
      "muzzle_offset": 28.0
    }
  },
  "ships": {
    "1": {
      "weapons": {
        "bullet": {
          "guns": 3,
          "multi_fire": true,
          "speed": 1200.0
        }
      }
    }
  },
  "energy": {
    "max": 100.0,
    "regen_per_s": 18.0,
    "afterburner_drain_per_s": 30.0
  }
}
```

### `format` (required)

- Type: string
- Must equal `"driftline.ruleset"`

### `schema_version` (required)

- Type: integer
- Must equal `1`

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

##### `weapons.bullet.lifetime_s` (optional)

- Type: number
- Range: `0.0..10.0`

Converted to integer ticks deterministically.

##### `weapons.bullet.muzzle_offset` (optional)

- Type: number
- Range: `0.0..64.0`

Distance (px) from ship center along ship forward axis where bullets spawn.

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

- `guns` (optional): integer in range `1..8`
- `multi_fire` (optional): boolean
- `speed` (optional): number in range `0.0..5000.0`
- `lifetime_s` (optional): number in range `0.0..10.0`
- `muzzle_offset` (optional): number in range `0.0..64.0`

### `energy` (optional)

- Type: object
- Unknown keys are rejected.

Energy is currently a tuning block shared to clients during handshake for consistency.

#### `energy.max` (optional)

- Type: number
- Range: `0.0..1000.0`

#### `energy.regen_per_s` (optional)

- Type: number
- Range: `0.0..1000.0`

#### `energy.afterburner_drain_per_s` (optional)

- Type: number
- Range: `0.0..1000.0`

## Defaults

Optional tuning keys may be omitted, but the engine will use its built-in defaults.
Because silent defaults are forbidden, missing optional fields produce **warnings** during ruleset validation.
