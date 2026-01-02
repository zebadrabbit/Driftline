## Driftline shared simulation types.
##
## Rules:
## - No logic beyond constructors
## - No inheritance from Node
## - Lightweight data structures only

class_name DriftTypes


class DriftInputCmd:
	# thrust: -1..+1 where -1 is reverse thrust, +1 is forward thrust
	var thrust: float
	# rotation: -1..+1 where -1 is rotate left, +1 is rotate right
	var rotation: float
	var fire_primary: bool
	var fire_secondary: bool
	var modifier: bool

	func _init(
		thrust_value: float = 0.0,
		rotation_value: float = 0.0,
		fire_primary_value: bool = false,
		fire_secondary_value: bool = false,
		modifier_value: bool = false
	) -> void:
		thrust = clampf(float(thrust_value), -1.0, 1.0)
		rotation = clampf(float(rotation_value), -1.0, 1.0)
		fire_primary = bool(fire_primary_value)
		fire_secondary = bool(fire_secondary_value)
		modifier = bool(modifier_value)



class DriftShipState:
	var id: int
	var position: Vector2
	var velocity: Vector2
	var rotation: float
	var username: String = ""
	var bounty: int = 0

	func _init(ship_id: int, position_value: Vector2, velocity_value: Vector2 = Vector2.ZERO, rotation_value: float = 0.0, username_value: String = "", bounty_value: int = 0) -> void:
		id = ship_id
		position = position_value
		velocity = velocity_value
		rotation = rotation_value
		username = username_value
		bounty = bounty_value



# Ball state with owner_id
class DriftBallState:
	var position: Vector2
	var velocity: Vector2
	var owner_id: int = -1

	func _init(pos: Vector2 = Vector2.ZERO, vel: Vector2 = Vector2.ZERO, owner: int = -1) -> void:
		position = pos
		velocity = vel
		owner_id = owner


class DriftBulletState:
	var id: int
	var owner_id: int
	var position: Vector2
	var velocity: Vector2
	var spawn_tick: int
	var die_tick: int

	func _init(bullet_id: int, owner_id_value: int, pos: Vector2, vel: Vector2, spawn_tick_value: int, die_tick_value: int = -1) -> void:
		id = bullet_id
		owner_id = owner_id_value
		position = pos
		velocity = vel
		spawn_tick = spawn_tick_value
		die_tick = die_tick_value


class DriftWorldSnapshot:
	var tick: int
	var ships: Dictionary # Dictionary[int, DriftShipState]
	var ball_position: Vector2
	var ball_velocity: Vector2
	var ball_owner_id: int
	var bullets: Array = [] # Array[DriftBulletState]
	var king_ship_id: int = -1

	func _init(tick_value: int, ships_value: Dictionary, ball_pos: Vector2 = Vector2.ZERO, ball_vel: Vector2 = Vector2.ZERO, ball_owner: int = -1, bullets_value: Array = [], king_id: int = -1) -> void:
		tick = tick_value
		ships = ships_value
		ball_position = ball_pos
		ball_velocity = ball_vel
		ball_owner_id = ball_owner
		bullets = bullets_value
		king_ship_id = king_id
