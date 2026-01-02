## Driftline authoritative simulation container.
##
## Rules:
## - Pure deterministic logic
## - Fixed tick stepping
## - Iteration order must be stable (sorted ship IDs)

class_name DriftWorld

const DriftConstants = preload("res://shared/drift_constants.gd")
const DriftTypes = preload("res://shared/drift_types.gd")
const DriftShip = preload("res://shared/drift_ship.gd")
const DriftBall = preload("res://shared/drift_ball.gd")


var tick: int = 0
var ships: Dictionary = {} # Dictionary[int, DriftTypes.DriftShipState]
var ball: DriftTypes.DriftBallState = DriftTypes.DriftBallState.new(DriftConstants.ARENA_CENTER, Vector2.ZERO)
var solid_tiles: Dictionary = {} # Dictionary[Vector2i, bool] - tile coordinates that are solid

# Ruleset (authoritative + prediction must match)
# This is the validated canonical ruleset dict (no normalization).
var ruleset: Dictionary = {}

# Effective tuning values used by the deterministic sim.
var wall_restitution: float = DriftConstants.SHIP_WALL_RESTITUTION
var tangent_damping: float = 0.0
var ship_turn_rate: float = DriftConstants.SHIP_TURN_RATE
var ship_thrust_accel: float = DriftConstants.SHIP_THRUST_ACCEL
var ship_reverse_accel: float = DriftConstants.SHIP_REVERSE_ACCEL
var ship_max_speed: float = DriftConstants.SHIP_MAX_SPEED
var ship_base_drag: float = DriftConstants.SHIP_BASE_DRAG
var ship_overspeed_drag: float = DriftConstants.SHIP_OVERSPEED_DRAG
var ship_bounce_min_normal_speed: float = 160.0

var ball_friction: float = 0.98
var ball_max_speed: float = 600.0
var ball_kick_speed: float = DriftConstants.BALL_KICK_SPEED
var ball_knock_impulse: float = DriftConstants.BALL_KNOCK_IMPULSE
var ball_stick_offset: float = 18.0
var ball_steal_padding: float = 4.0

var energy_max: float = 100.0
var energy_regen_per_s: float = 18.0
var energy_afterburner_drain_per_s: float = 30.0


func apply_ruleset(canonical_ruleset: Dictionary) -> void:
	# Must only be called with a validated driftline.ruleset dict.
	ruleset = canonical_ruleset

	var physics: Dictionary = canonical_ruleset.get("physics", {})
	if typeof(physics) == TYPE_DICTIONARY:
		wall_restitution = float(physics.get("wall_restitution", wall_restitution))
		# Optional: tangent damping on wall collisions.
		# Default to 0.0 only after validation (sim init), not in the validator.
		if physics.has("tangent_damping"):
			tangent_damping = float(physics.get("tangent_damping"))
		else:
			tangent_damping = 0.0
		ship_turn_rate = float(physics.get("ship_turn_rate", ship_turn_rate))
		ship_thrust_accel = float(physics.get("ship_thrust_accel", ship_thrust_accel))
		ship_reverse_accel = float(physics.get("ship_reverse_accel", ship_reverse_accel))
		ship_max_speed = float(physics.get("ship_max_speed", ship_max_speed))
		ship_base_drag = float(physics.get("ship_base_drag", ship_base_drag))
		ship_overspeed_drag = float(physics.get("ship_overspeed_drag", ship_overspeed_drag))
		ship_bounce_min_normal_speed = float(physics.get("ship_bounce_min_normal_speed", ship_bounce_min_normal_speed))

	var weapons: Dictionary = canonical_ruleset.get("weapons", {})
	if typeof(weapons) == TYPE_DICTIONARY and not weapons.is_empty():
		ball_friction = float(weapons.get("ball_friction", ball_friction))
		ball_max_speed = float(weapons.get("ball_max_speed", ball_max_speed))
		ball_kick_speed = float(weapons.get("ball_kick_speed", ball_kick_speed))
		ball_knock_impulse = float(weapons.get("ball_knock_impulse", ball_knock_impulse))
		ball_stick_offset = float(weapons.get("ball_stick_offset", ball_stick_offset))
		ball_steal_padding = float(weapons.get("ball_steal_padding", ball_steal_padding))

	var energy: Dictionary = canonical_ruleset.get("energy", {})
	if typeof(energy) == TYPE_DICTIONARY and not energy.is_empty():
		energy_max = float(energy.get("max", energy_max))
		energy_regen_per_s = float(energy.get("regen_per_s", energy_regen_per_s))
		energy_afterburner_drain_per_s = float(energy.get("afterburner_drain_per_s", energy_afterburner_drain_per_s))

# Doors (dynamic tile solids)
var _static_solid_tiles: Dictionary = {} # Dictionary[Vector2i, bool]
var _door_tile_cells: Array = [] # Array[Vector2i]
var _doors_closed: bool = false

var _door_open_ticks: int = 120
var _door_closed_ticks: int = 120
var _door_frame_ticks: int = 12
var _door_start_open: bool = true

const TILE_SIZE: int = 16
const SEPARATION_EPSILON: float = 0.05

# Transient (not networked): per-tick collision events for client-side audio/FX.
# Each entry is a Dictionary: {type, ship_id, pos, normal, impact_speed}
var collision_events: Array = []


func _record_wall_bounce(ship_id: int, pos: Vector2, normal: Vector2, impact_speed: float) -> void:
	collision_events.append({
		"type": "wall",
		"ship_id": ship_id,
		"pos": pos,
		"normal": normal,
		"impact_speed": impact_speed,
	})


func add_ship(id: int, position: Vector2) -> void:
	ships[id] = DriftTypes.DriftShipState.new(id, position)

func get_spawn_position(ship_id: int) -> Vector2:
	# Example: spread ships horizontally from center
	return DriftConstants.ARENA_CENTER + Vector2((ship_id-1) * 30, 0)


func set_solid_tiles(tiles: Array) -> void:
	"""Set solid tile positions from map data. tiles is Array of [x, y, atlas_x, atlas_y]"""
	_static_solid_tiles.clear()
	for tile_data in tiles:
		if tile_data.size() >= 2:
			var tile_pos := Vector2i(tile_data[0], tile_data[1])
			_static_solid_tiles[tile_pos] = true
	_rebuild_effective_solids_for_tick(tick)


func set_door_tiles(tiles: Array) -> void:
	"""Set door tile positions from map data. tiles is Array of [x, y, atlas_x, atlas_y]"""
	_door_tile_cells.clear()
	for tile_data in tiles:
		if tile_data.size() >= 2:
			_door_tile_cells.append(Vector2i(int(tile_data[0]), int(tile_data[1])))
	_rebuild_effective_solids_for_tick(tick)


func configure_doors(open_seconds: float, closed_seconds: float, frame_seconds: float = 0.2, start_open: bool = true) -> void:
	# Convert to ticks (keep deterministic integers).
	var open_ticks: int = int(round(open_seconds / DriftConstants.TICK_DT))
	var closed_ticks: int = int(round(closed_seconds / DriftConstants.TICK_DT))
	var frame_ticks: int = int(round(frame_seconds / DriftConstants.TICK_DT))
	_door_open_ticks = maxi(1, open_ticks)
	_door_closed_ticks = maxi(1, closed_ticks)
	_door_frame_ticks = maxi(1, frame_ticks)
	_door_start_open = start_open
	_rebuild_effective_solids_for_tick(tick)


func get_door_anim_for_tick(tick_value: int) -> Dictionary:
	# Returns { open: bool, frame: int }. frame is 0..3 when closed, -1 when open.
	var cycle_ticks: int = _door_open_ticks + _door_closed_ticks
	if cycle_ticks <= 0:
		return {"open": true, "frame": -1}
	var t_in_cycle: int = tick_value % cycle_ticks
	if t_in_cycle < 0:
		t_in_cycle += cycle_ticks
	var open_first: bool = _door_start_open
	var is_open: bool
	if open_first:
		is_open = (t_in_cycle < _door_open_ticks)
	else:
		is_open = (t_in_cycle >= _door_closed_ticks)
	if is_open:
		return {"open": true, "frame": -1}
	var closed_t: int
	if open_first:
		closed_t = t_in_cycle - _door_open_ticks
	else:
		closed_t = t_in_cycle
	var frame: int = int(floor(float(closed_t) / float(_door_frame_ticks))) % 4
	if frame < 0:
		frame += 4
	return {"open": false, "frame": frame}


func add_boundary_tiles(width: int, height: int) -> void:
	"""Add boundary tiles around the map edges."""
	for x in range(width):
		_static_solid_tiles[Vector2i(x, 0)] = true
		_static_solid_tiles[Vector2i(x, height - 1)] = true
	for y in range(height):
		_static_solid_tiles[Vector2i(0, y)] = true
		_static_solid_tiles[Vector2i(width - 1, y)] = true
	_rebuild_effective_solids_for_tick(tick)


func _rebuild_effective_solids_for_tick(tick_value: int) -> void:
	# Start with static solids.
	solid_tiles = _static_solid_tiles.duplicate(false)
	# Apply door solids depending on current cycle.
	var d := get_door_anim_for_tick(tick_value)
	var closed_now: bool = not bool(d.get("open", true))
	_doors_closed = closed_now
	if closed_now:
		for c in _door_tile_cells:
			if c is Vector2i:
				solid_tiles[c] = true


func _update_doors_for_current_tick() -> void:
	if _door_tile_cells.is_empty():
		return
	var d := get_door_anim_for_tick(tick)
	var closed_now: bool = not bool(d.get("open", true))
	if closed_now == _doors_closed:
		return
	_doors_closed = closed_now
	if closed_now:
		for c in _door_tile_cells:
			if c is Vector2i:
				solid_tiles[c] = true
	else:
		for c in _door_tile_cells:
			if c is Vector2i:
				if solid_tiles.has(c):
					solid_tiles.erase(c)


func is_position_blocked(pos: Vector2, radius: float) -> bool:
	"""Check if a circular entity at pos with given radius collides with solid tiles."""
	
	# Check tiles in a square around the position
	var min_tile_x := int(floor((pos.x - radius) / TILE_SIZE))
	var max_tile_x := int(floor((pos.x + radius) / TILE_SIZE))
	var min_tile_y := int(floor((pos.y - radius) / TILE_SIZE))
	var max_tile_y := int(floor((pos.y + radius) / TILE_SIZE))
	
	for tx in range(min_tile_x, max_tile_x + 1):
		for ty in range(min_tile_y, max_tile_y + 1):
			var tile_coord := Vector2i(tx, ty)
			if solid_tiles.has(tile_coord):
				# Check if circle overlaps tile (simple AABB for now)
				var tile_rect_min := Vector2(tx * TILE_SIZE, ty * TILE_SIZE)
				var tile_rect_max := tile_rect_min + Vector2(TILE_SIZE, TILE_SIZE)
				
				# Find closest point on rectangle to circle center
				var closest_x := clampf(pos.x, tile_rect_min.x, tile_rect_max.x)
				var closest_y := clampf(pos.y, tile_rect_min.y, tile_rect_max.y)
				var closest := Vector2(closest_x, closest_y)
				
				# Check if closest point is within circle radius
				if pos.distance_to(closest) < radius:
					return true
	
	return false


func get_collision_normal(old_pos: Vector2, new_pos: Vector2, radius: float) -> Vector2:
	"""Get collision normal if moving from old_pos to new_pos would hit a wall."""
	if not is_position_blocked(new_pos, radius):
		return Vector2.ZERO
	
	const TILE_SIZE: int = 16
	
	# Find the colliding tile and compute normal
	var min_tile_x := int(floor((new_pos.x - radius) / TILE_SIZE))
	var max_tile_x := int(floor((new_pos.x + radius) / TILE_SIZE))
	var min_tile_y := int(floor((new_pos.y - radius) / TILE_SIZE))
	var max_tile_y := int(floor((new_pos.y + radius) / TILE_SIZE))
	
	for tx in range(min_tile_x, max_tile_x + 1):
		for ty in range(min_tile_y, max_tile_y + 1):
			var tile_coord := Vector2i(tx, ty)
			if solid_tiles.has(tile_coord):
				var tile_rect_min := Vector2(tx * TILE_SIZE, ty * TILE_SIZE)
				var tile_rect_max := tile_rect_min + Vector2(TILE_SIZE, TILE_SIZE)
				
				var closest_x := clampf(new_pos.x, tile_rect_min.x, tile_rect_max.x)
				var closest_y := clampf(new_pos.y, tile_rect_min.y, tile_rect_max.y)
				var closest := Vector2(closest_x, closest_y)
				
				if new_pos.distance_to(closest) < radius:
					# Compute normal from circle center to closest point
					var normal := (new_pos - closest).normalized()
					if normal.length_squared() < 0.01:
						# If at tile center, use movement direction
						normal = (new_pos - old_pos).normalized()
					return normal
	
	return Vector2.ZERO



func step_tick(inputs: Dictionary) -> DriftTypes.DriftWorldSnapshot:
	# Advance world tick.
	tick += 1
	_update_doors_for_current_tick()
	# Clear transient events each tick.
	collision_events.clear()

	# Stable update order for determinism.
	var ship_ids: Array = ships.keys()
	ship_ids.sort()


	for ship_id in ship_ids:
		var ship_state: DriftTypes.DriftShipState = ships[ship_id]
		var input_cmd: DriftTypes.DriftInputCmd = inputs.get(ship_id, DriftTypes.DriftInputCmd.new(false, 0.0, false, false))
		
		# Store position before movement
		var old_position := ship_state.position
		
		DriftShip.apply_input(
			ship_state,
			input_cmd,
			DriftConstants.TICK_DT,
			ship_turn_rate,
			ship_thrust_accel,
			ship_reverse_accel,
			ship_max_speed,
			ship_base_drag,
			ship_overspeed_drag,
		)
		
		# Axis-separated collision resolution (sweep to avoid "teleport back")
		# We keep the post-integration velocity, but resolve position by sweeping
		# along the movement segment on each axis and stopping at last valid point.
		const SEPARATION_EPSILON: float = 0.25
		# Only bounce when the ship has meaningful speed INTO the wall.
		# Otherwise, kill the normal component and let the ship slide along the wall.
		var BOUNCE_NORMAL_SPEED: float = ship_bounce_min_normal_speed
		const SWEEP_ITERS: int = 10
		var next_pos := ship_state.position
		ship_state.position = old_position

		# Resolve X-axis
		var target_x := Vector2(next_pos.x, ship_state.position.y)
		if is_position_blocked(target_x, DriftConstants.SHIP_RADIUS):
			# If we're already in a bad state, don't make things worse.
			if is_position_blocked(ship_state.position, DriftConstants.SHIP_RADIUS):
				ship_state.position = old_position
				ship_state.velocity.x = 0.0
			else:
				var t_lo := 0.0
				var t_hi := 1.0
				for _i in range(SWEEP_ITERS):
					var t_mid := (t_lo + t_hi) * 0.5
					var mid_x := lerpf(old_position.x, next_pos.x, t_mid)
					var cand := Vector2(mid_x, ship_state.position.y)
					if is_position_blocked(cand, DriftConstants.SHIP_RADIUS):
						t_hi = t_mid
					else:
						t_lo = t_mid
				ship_state.position.x = lerpf(old_position.x, next_pos.x, t_lo)
				# Keep a tiny gap so we don't remain in-contact and jitter.
				var dir_x := signf(next_pos.x - old_position.x)
				ship_state.position.x -= dir_x * SEPARATION_EPSILON
				var pre_v: Vector2 = ship_state.velocity
				var nrm_x: Vector2 = Vector2(-dir_x, 0.0)
				var vdotn: float = pre_v.dot(nrm_x)
				# Only apply bounce/damping when moving into the wall.
				if vdotn < 0.0:
					var normal_speed: float = -vdotn
					var v_t: Vector2 = pre_v - nrm_x * vdotn
					var v_t_damped: Vector2 = v_t * (1.0 - tangent_damping)
					if normal_speed >= BOUNCE_NORMAL_SPEED:
						ship_state.velocity = v_t_damped + nrm_x * (normal_speed * wall_restitution)
						_record_wall_bounce(ship_id, ship_state.position, nrm_x, normal_speed)
					else:
						ship_state.velocity = v_t_damped
				else:
					# Not moving into the wall; kill outward normal component only.
					ship_state.velocity = pre_v - nrm_x * maxf(0.0, vdotn)
		else:
			ship_state.position.x = next_pos.x

		# Resolve Y-axis
		var target_y := Vector2(ship_state.position.x, next_pos.y)
		if is_position_blocked(target_y, DriftConstants.SHIP_RADIUS):
			if is_position_blocked(ship_state.position, DriftConstants.SHIP_RADIUS):
				ship_state.position = old_position
				ship_state.velocity.y = 0.0
			else:
				var t_lo := 0.0
				var t_hi := 1.0
				for _i in range(SWEEP_ITERS):
					var t_mid := (t_lo + t_hi) * 0.5
					var mid_y := lerpf(old_position.y, next_pos.y, t_mid)
					var cand := Vector2(ship_state.position.x, mid_y)
					if is_position_blocked(cand, DriftConstants.SHIP_RADIUS):
						t_hi = t_mid
					else:
						t_lo = t_mid
				ship_state.position.y = lerpf(old_position.y, next_pos.y, t_lo)
				var dir_y := signf(next_pos.y - old_position.y)
				ship_state.position.y -= dir_y * SEPARATION_EPSILON
				var pre_v: Vector2 = ship_state.velocity
				var nrm_y: Vector2 = Vector2(0.0, -dir_y)
				var vdotn: float = pre_v.dot(nrm_y)
				if vdotn < 0.0:
					var normal_speed: float = -vdotn
					var v_t: Vector2 = pre_v - nrm_y * vdotn
					var v_t_damped: Vector2 = v_t * (1.0 - tangent_damping)
					if normal_speed >= BOUNCE_NORMAL_SPEED:
						ship_state.velocity = v_t_damped + nrm_y * (normal_speed * wall_restitution)
						_record_wall_bounce(ship_id, ship_state.position, nrm_y, normal_speed)
					else:
						ship_state.velocity = v_t_damped
				else:
					ship_state.velocity = pre_v - nrm_y * maxf(0.0, vdotn)
		else:
			ship_state.position.y = next_pos.y

		# Clamp ship position to arena bounds and bounce
		var old_x = ship_state.position.x
		var old_y = ship_state.position.y
		var min_x = DriftConstants.ARENA_MIN.x + DriftConstants.SHIP_RADIUS
		var max_x = DriftConstants.ARENA_MAX.x - DriftConstants.SHIP_RADIUS
		var min_y = DriftConstants.ARENA_MIN.y + DriftConstants.SHIP_RADIUS
		var max_y = DriftConstants.ARENA_MAX.y - DriftConstants.SHIP_RADIUS
		ship_state.position.x = clamp(ship_state.position.x, min_x, max_x)
		ship_state.position.y = clamp(ship_state.position.y, min_y, max_y)
		# Bounce on arena bounds
		if ship_state.position.x != old_x:
			var pre_v: Vector2 = ship_state.velocity
			var nrm_x2: Vector2 = Vector2(1.0, 0.0) if old_x < ship_state.position.x else Vector2(-1.0, 0.0)
			var vdotn: float = pre_v.dot(nrm_x2)
			if vdotn < 0.0:
				var normal_speed: float = -vdotn
				var v_t: Vector2 = pre_v - nrm_x2 * vdotn
				var v_t_damped: Vector2 = v_t * (1.0 - tangent_damping)
				if normal_speed >= BOUNCE_NORMAL_SPEED:
					ship_state.velocity = v_t_damped + nrm_x2 * (normal_speed * wall_restitution)
					_record_wall_bounce(ship_id, ship_state.position, nrm_x2, normal_speed)
				else:
					ship_state.velocity = v_t_damped
			else:
				ship_state.velocity = pre_v - nrm_x2 * maxf(0.0, vdotn)
		if ship_state.position.y != old_y:
			var pre_v: Vector2 = ship_state.velocity
			var nrm_y2: Vector2 = Vector2(0.0, 1.0) if old_y < ship_state.position.y else Vector2(0.0, -1.0)
			var vdotn: float = pre_v.dot(nrm_y2)
			if vdotn < 0.0:
				var normal_speed: float = -vdotn
				var v_t: Vector2 = pre_v - nrm_y2 * vdotn
				var v_t_damped: Vector2 = v_t * (1.0 - tangent_damping)
				if normal_speed >= BOUNCE_NORMAL_SPEED:
					ship_state.velocity = v_t_damped + nrm_y2 * (normal_speed * wall_restitution)
					_record_wall_bounce(ship_id, ship_state.position, nrm_y2, normal_speed)
				else:
					ship_state.velocity = v_t_damped
			else:
				ship_state.velocity = pre_v - nrm_y2 * maxf(0.0, vdotn)


	# --- Sticky/Magnetic Ball Logic ---
	if ball.owner_id == -1:
		# Free ball physics
		# Clamp ball position to arena bounds
		var ball_old_x = ball.position.x
		var ball_old_y = ball.position.y
		var ball_min_x = DriftConstants.ARENA_MIN.x + DriftConstants.BALL_RADIUS
		var ball_max_x = DriftConstants.ARENA_MAX.x - DriftConstants.BALL_RADIUS
		var ball_min_y = DriftConstants.ARENA_MIN.y + DriftConstants.BALL_RADIUS
		var ball_max_y = DriftConstants.ARENA_MAX.y - DriftConstants.BALL_RADIUS
		ball.position.x = clamp(ball.position.x, ball_min_x, ball_max_x)
		ball.position.y = clamp(ball.position.y, ball_min_y, ball_max_y)
		if ball.position.x != ball_old_x:
			ball.velocity.x = 0.0
		if ball.position.y != ball_old_y:
			ball.velocity.y = 0.0
		DriftBall.step_ball(ball, DriftConstants.TICK_DT, ball_friction, ball_max_speed)
		# Check for acquisition
		for ship_id in ship_ids:
			var ship = ships[ship_id]
			if ship.position.distance_to(ball.position) <= DriftConstants.SHIP_RADIUS + DriftConstants.BALL_RADIUS:
				ball.owner_id = ship.id
				ball.velocity = Vector2.ZERO
				ball.position = ship.position + Vector2(ball_stick_offset, 0.0).rotated(ship.rotation)
				break
	else:
		# Ball is carried
		if not ships.has(ball.owner_id):
			# Owner disconnected, drop ball
			ball.owner_id = -1
		else:
			var owner = ships[ball.owner_id]
			ball.position = owner.position + Vector2(ball_stick_offset, 0.0).rotated(owner.rotation)
			ball.velocity = owner.velocity
			# Knock-off / steal check
			for other_id in ship_ids:
				if other_id == owner.id:
					continue
				var other = ships[other_id]
				var steal_radius := DriftConstants.SHIP_RADIUS + DriftConstants.BALL_RADIUS + ball_steal_padding
				if other.position.distance_to(owner.position) <= steal_radius:
					var n = ball.position - other.position
					if n.length() == 0:
						n = Vector2(1,0)
					n = n.normalized()
					ball.owner_id = -1
					ball.velocity = owner.velocity + n * ball_knock_impulse
					ball.position = owner.position + n * (DriftConstants.SHIP_RADIUS + DriftConstants.BALL_RADIUS)
					break

	# Kick on fire
	if ball.owner_id != -1 and inputs.has(ball.owner_id) and inputs[ball.owner_id].fire:
		var owner = ships[ball.owner_id]
		ball.owner_id = -1
		var fwd = Vector2(cos(owner.rotation), sin(owner.rotation))
		ball.velocity = owner.velocity + fwd * ball_kick_speed
		ball.position = owner.position + fwd * (DriftConstants.SHIP_RADIUS + DriftConstants.BALL_RADIUS + 2.0)

	# Return a snapshot (deep copy of ship states and ball)
	var snapshot_ships: Dictionary = {}
	for ship_id in ship_ids:
		snapshot_ships[ship_id] = _copy_ship_state(ships[ship_id])

	return DriftTypes.DriftWorldSnapshot.new(tick, snapshot_ships, ball.position, ball.velocity, ball.owner_id)


func _copy_ship_state(source: DriftTypes.DriftShipState) -> DriftTypes.DriftShipState:
	return DriftTypes.DriftShipState.new(
		source.id,
		source.position,
		source.velocity,
		source.rotation,
		source.username,
		source.bounty
	)
