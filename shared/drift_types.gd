## Driftline shared simulation types.
##
## Rules:
## - No logic beyond constructors
## - No inheritance from Node
## - Lightweight data structures only

class_name DriftTypes


class DriftInputCmd:
	var thrust: bool
	var reverse: bool
	var turn: float # -1.0 to +1.0
	var fire: bool

	func _init(thrust_value: bool = false, turn_value: float = 0.0, fire_value: bool = false, reverse_value: bool = false) -> void:
		thrust = thrust_value
		reverse = reverse_value
		turn = clampf(turn_value, -1.0, 1.0)
		fire = fire_value



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


class DriftWorldSnapshot:
	var tick: int
	var ships: Dictionary # Dictionary[int, DriftShipState]
	var ball_position: Vector2
	var ball_velocity: Vector2
	var ball_owner_id: int
	var king_ship_id: int = -1

	func _init(tick_value: int, ships_value: Dictionary, ball_pos: Vector2 = Vector2.ZERO, ball_vel: Vector2 = Vector2.ZERO, ball_owner: int = -1, king_id: int = -1) -> void:
		tick = tick_value
		ships = ships_value
		ball_position = ball_pos
		ball_velocity = ball_vel
		ball_owner_id = ball_owner
		king_ship_id = king_id
