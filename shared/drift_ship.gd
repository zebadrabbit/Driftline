## Driftline ship simulation logic.
##
## Rules:
## - Pure deterministic logic
## - No Node/SceneTree dependencies
## - All methods are static

const DriftConstants = preload("res://shared/drift_constants.gd")
const DriftTypes = preload("res://shared/drift_types.gd")


## Apply input to ship state for one tick.
static func apply_input(ship_state: DriftTypes.DriftShipState, input_cmd: DriftTypes.DriftInputCmd, delta: float) -> void:
	# Apply rotation
	if input_cmd.turn != 0.0:
		ship_state.rotation += input_cmd.turn * DriftConstants.SHIP_TURN_RATE * delta
	
	# Forward vector from heading
	var forward := Vector2(cos(ship_state.rotation), sin(ship_state.rotation))
	
	# Apply thrust or reverse thrust
	var accel := Vector2.ZERO
	if input_cmd.thrust:
		accel += forward * DriftConstants.SHIP_THRUST_ACCEL
	elif input_cmd.reverse:
		# Reverse thrust: accelerate opposite to ship forward
		accel += (-forward) * DriftConstants.SHIP_REVERSE_ACCEL
	
	# Semi-implicit Euler integration
	ship_state.velocity += accel * delta
	
	# Exponential drag (frame-rate stable)
	var drag_k := DriftConstants.SHIP_BASE_DRAG
	var speed_now := ship_state.velocity.length()
	
	# Overspeed drag: extra drag when above soft cap
	if speed_now > DriftConstants.SHIP_MAX_SPEED and speed_now > 1e-3:
		var overspeed_ratio := (speed_now - DriftConstants.SHIP_MAX_SPEED) / DriftConstants.SHIP_MAX_SPEED
		drag_k += DriftConstants.SHIP_OVERSPEED_DRAG * overspeed_ratio
	
	# Apply exponential drag
	ship_state.velocity *= exp(-drag_k * delta)
	
	# Update position
	ship_state.position += ship_state.velocity * delta
