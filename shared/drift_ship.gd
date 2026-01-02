## Driftline ship simulation logic.
##
## Rules:
## - Pure deterministic logic
## - No Node/SceneTree dependencies
## - All methods are static

const DriftTypes = preload("res://shared/drift_types.gd")


## Apply input to ship state for one tick.
static func apply_input(
	ship_state: DriftTypes.DriftShipState,
	input_cmd: DriftTypes.DriftInputCmd,
	delta: float,
	ship_turn_rate: float,
	ship_thrust_accel: float,
	ship_reverse_accel: float,
	ship_max_speed: float,
	ship_base_drag: float,
	ship_overspeed_drag: float,
) -> void:
	# Apply rotation
	if input_cmd.turn != 0.0:
		ship_state.rotation += input_cmd.turn * ship_turn_rate * delta
	
	# Forward vector from heading
	var forward := Vector2(cos(ship_state.rotation), sin(ship_state.rotation))
	
	# Apply thrust or reverse thrust
	var accel := Vector2.ZERO
	if input_cmd.thrust:
		accel += forward * ship_thrust_accel
	elif input_cmd.reverse:
		# Reverse thrust: accelerate opposite to ship forward
		accel += (-forward) * ship_reverse_accel
	
	# Semi-implicit Euler integration
	ship_state.velocity += accel * delta
	
	# Exponential drag (frame-rate stable)
	var drag_k := ship_base_drag
	var speed_now := ship_state.velocity.length()
	
	# Overspeed drag: extra drag when above soft cap
	if speed_now > ship_max_speed and speed_now > 1e-3:
		var overspeed_ratio := (speed_now - ship_max_speed) / ship_max_speed
		drag_k += ship_overspeed_drag * overspeed_ratio
	
	# Apply exponential drag
	ship_state.velocity *= exp(-drag_k * delta)
	
	# Update position
	ship_state.position += ship_state.velocity * delta
