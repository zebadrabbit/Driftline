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
const TICK_DT: float = 1.0 / float(TICK_RATE)

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
