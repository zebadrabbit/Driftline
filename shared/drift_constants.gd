class_name DriftConstants

# Arena bounds (authoritative, shared)
static var ARENA_MIN := Vector2(0, 0)
static var ARENA_MAX := Vector2(2048, 1152)
# Arena center helpers
static var ARENA_CENTER := (ARENA_MIN + ARENA_MAX) * 0.5
static var HILL_CENTER := ARENA_CENTER
static var ARENA_PADDING := 0.0

# Shared entity radii
const SHIP_RADIUS: float = 10.0
const BALL_RADIUS: float = 6.0

# Soccer ball sticky/magnetic constants
const BALL_STICK_OFFSET := Vector2(18, 0)   # in front of ship nose in local space
const BALL_KICK_SPEED := 700.0
const BALL_STEAL_RADIUS := SHIP_RADIUS + BALL_RADIUS + 4.0
const BALL_KNOCK_IMPULSE := 250.0
## Driftline shared simulation constants.
##
## Rules:
## - Pure logic only (no Node/SceneTree dependencies)
## - Deterministic given identical inputs and tick order
## - Use const, not variables

## Fixed simulation tick rate.
const TICK_RATE: int = 60
const TICK_HZ: int = TICK_RATE
const TICK_DT: float = 1.0 / float(TICK_RATE)


## Deterministic energy system constants.
##
## Units:
## - energy_current/energy_max are integer "energy points".
## - recharge_rate_per_sec is integer points per second.
## - recharge math is done with integer tick-based remainder to avoid float drift.
##
## Fixed-point scale for future use (e.g. milli-energy) if needed.
const ENERGY_FP_SCALE: int = 1000

## Safe starter values (not final balance).
const DEFAULT_ENERGY_MAX: int = 1200
const DEFAULT_RECHARGE_RATE_PER_SEC: int = 150
const DEFAULT_RECHARGE_DELAY_MS: int = 300

# Convert ms to ticks deterministically using ceil(ms * TICK_RATE / 1000).
const DEFAULT_RECHARGE_DELAY_TICKS: int = int((DEFAULT_RECHARGE_DELAY_MS * TICK_RATE + 999) / 1000)

const DEFAULT_BULLET_ENERGY_COST: int = 30
const DEFAULT_BOMB_ENERGY_COST: int = 150

# Multi-fire (multiple bullets per trigger) uses a separate cost by default.
const DEFAULT_MULTIFIRE_ENERGY_COST: int = DEFAULT_BULLET_ENERGY_COST * 3

## Placeholder tile size for future map/grid work.
const TILE_SIZE: int = 32

## Default ship physics values.
## Units:
## - thrust_accel: pixels/s^2
## - turn_rate: radians/s
## - max_speed: pixels/s (soft cap, extra drag kicks in above this)
## - base_drag: drag coefficient (1/s) for exponential decay
## - overspeed_drag: additional drag when above max_speed
const SHIP_THRUST_ACCEL: float = 520.0
const SHIP_REVERSE_ACCEL: float = 400.0
const SHIP_TURN_RATE: float = 3.5
const SHIP_MAX_SPEED: float = 720.0
const SHIP_BASE_DRAG: float = 0.35
const SHIP_OVERSPEED_DRAG: float = 2.0
const SHIP_WALL_RESTITUTION: float = 0.6  # Bounce damping (1.0=perfect bounce, 0.0=no bounce)


## Door (tile) animation + cycle.
## - When open: door tiles are cleared (not drawn) and do NOT block.
## - When closed: door tiles animate 4 frames and DO block.
## These defaults can be overridden per-map via meta keys:
##   door_open_seconds, door_closed_seconds, door_frame_seconds, door_start_open
const DOOR_FRAME_SECONDS: float = 0.2
const DOOR_OPEN_SECONDS: float = 2.0
const DOOR_CLOSED_SECONDS: float = 2.0
const DOOR_START_OPEN: bool = true
