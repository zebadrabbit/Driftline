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

var map_w_tiles: int = 0
var map_h_tiles: int = 0
var _main_walkable_tiles: Array = [] # Array[Vector2i]
var _main_walkable_set: Dictionary = {} # Dictionary[Vector2i, bool]


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

## Deterministic energy system tuning (integer, tick-based).
## Units:
## - energy_*_per_sec: integer energy points per second
## - costs: integer energy points
var energy_max_points: int = DriftConstants.DEFAULT_ENERGY_MAX
var energy_recharge_rate_per_sec: int = DriftConstants.DEFAULT_RECHARGE_RATE_PER_SEC
var energy_recharge_delay_ticks: int = DriftConstants.DEFAULT_RECHARGE_DELAY_TICKS
var energy_afterburner_drain_per_sec: int = 0 # optional, can be configured by ruleset
var bullet_energy_cost: int = DriftConstants.DEFAULT_BULLET_ENERGY_COST
var bullet_multifire_energy_cost: int = DriftConstants.DEFAULT_MULTIFIRE_ENERGY_COST
var bomb_energy_cost: int = DriftConstants.DEFAULT_BOMB_ENERGY_COST
var energy_afterburner_multiplier: float = 1.6

const TOP_SPEED_BONUS_PCT: float = 0.04
const THRUSTER_BONUS_PCT: float = 0.06
const RECHARGE_BONUS_PCT: float = 0.15

const RECHARGE_BONUS_PCT_NUM: int = 15
const RECHARGE_BONUS_PCT_DEN: int = 100


# Prizes (server authoritative; replicated to clients via snapshots)
var prizes: Dictionary = {} # Dictionary[int, DriftTypes.DriftPrizeState]
var _prize_buckets: Dictionary = {} # Dictionary[Vector2i, Array[int]]
var next_prize_spawn_tick: int = 0
var prize_id_counter: int = 1

var prize_enabled: bool = false
var prize_delay_ticks: int = 0
var prize_hide_count: int = 0
var prize_min_exist_ticks: int = 0
var prize_max_exist_ticks: int = 0
var prize_negative_factor: int = 0
var death_prize_time_ticks: int = 0
var multi_prize_count: int = 0
var engine_shutdown_time_ticks: int = 0
var minimum_virtual: int = 0
var upgrade_virtual: int = 0

var _prize_weights: Array[int] = []
var _prize_total_weight: int = 0

var _prize_rng := RandomNumberGenerator.new()

const PRIZE_PICKUP_RADIUS: float = float(DriftConstants.SHIP_RADIUS) + 8.0
const MIN_PRIZE_SPACING_TILES: int = 2
const PRIZE_SPAWN_ATTEMPTS: int = 200


# Bullets (authoritative + predicted)
var bullets: Dictionary = {} # Dictionary[int, DriftTypes.DriftBulletState]
var _next_bullet_id: int = 1
var _prev_fire_by_ship: Dictionary = {} # Dictionary[int, bool]

# Effective bullet tuning values used by the deterministic sim.
var bullet_speed: float = 950.0
var bullet_lifetime_ticks: int = 24
var bullet_muzzle_offset: float = float(DriftConstants.SHIP_RADIUS) + 10.0
var bullet_radius: float = 2.0
var bullet_gun_spacing: float = 8.0
var bullet_bounces: int = 0
var bullet_bounce_restitution: float = 1.0


func _resolve_bullet_bounce_restitution_for_ship(ship_id: int) -> float:
	var restitution: float = bullet_bounce_restitution

	# Optional level profiles live under ruleset.weapons.bullet.levels.
	var rs_weapons: Dictionary = ruleset.get("weapons", {})
	var levels: Dictionary = {}
	if typeof(rs_weapons) == TYPE_DICTIONARY and rs_weapons.has("bullet") and typeof(rs_weapons.get("bullet")) == TYPE_DICTIONARY:
		var rs_bullet: Dictionary = rs_weapons.get("bullet")
		if rs_bullet.has("levels") and typeof(rs_bullet.get("levels")) == TYPE_DICTIONARY:
			levels = rs_bullet.get("levels")

	# Per-ship override.
	var rs_ships: Dictionary = ruleset.get("ships", {})
	if typeof(rs_ships) == TYPE_DICTIONARY:
		var ship_key := str(ship_id)
		if rs_ships.has(ship_key) and typeof(rs_ships.get(ship_key)) == TYPE_DICTIONARY:
			var ship_cfg: Dictionary = rs_ships.get(ship_key)
			if ship_cfg.has("weapons") and typeof(ship_cfg.get("weapons")) == TYPE_DICTIONARY:
				var ship_weapons: Dictionary = ship_cfg.get("weapons")
				if ship_weapons.has("bullet") and typeof(ship_weapons.get("bullet")) == TYPE_DICTIONARY:
					var sb: Dictionary = ship_weapons.get("bullet")
					var level: int = int(sb.get("level", 1))
					if typeof(levels) == TYPE_DICTIONARY and levels.has(str(level)) and typeof(levels.get(str(level))) == TYPE_DICTIONARY:
						var level_cfg: Dictionary = levels.get(str(level))
						restitution = float(level_cfg.get("bounce_restitution", restitution))
					restitution = float(sb.get("bounce_restitution", restitution))

	return clampf(restitution, 0.0, 2.0)


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
		if weapons.has("bullet") and typeof(weapons.get("bullet")) == TYPE_DICTIONARY:
			var b: Dictionary = weapons.get("bullet")
			bullet_speed = float(b.get("speed", bullet_speed))
			bullet_muzzle_offset = float(b.get("muzzle_offset", bullet_muzzle_offset))
			bullet_bounces = int(b.get("bounces", bullet_bounces))
			bullet_bounce_restitution = float(b.get("bounce_restitution", bullet_bounce_restitution))
			if b.has("lifetime_s"):
				var lifetime_s: float = float(b.get("lifetime_s"))
				bullet_lifetime_ticks = int(round(lifetime_s / DriftConstants.TICK_DT))

	var energy: Dictionary = canonical_ruleset.get("energy", {})
	if typeof(energy) == TYPE_DICTIONARY and not energy.is_empty():
		# Legacy keys (schema v1): max, regen_per_s, afterburner_drain_per_s.
		# New keys (optional): recharge_rate_per_sec, recharge_delay_ms, bullet_energy_cost, multifire_energy_cost, bomb_energy_cost.
		if energy.has("max"):
			var m = energy.get("max")
			if typeof(m) in [TYPE_INT, TYPE_FLOAT]:
				energy_max_points = maxi(0, int(round(float(m))))

		# Prefer new name if present; fall back to legacy.
		if energy.has("recharge_rate_per_sec"):
			var r = energy.get("recharge_rate_per_sec")
			if typeof(r) in [TYPE_INT, TYPE_FLOAT]:
				energy_recharge_rate_per_sec = maxi(0, int(round(float(r))))
		elif energy.has("regen_per_s"):
			var rr = energy.get("regen_per_s")
			if typeof(rr) in [TYPE_INT, TYPE_FLOAT]:
				energy_recharge_rate_per_sec = maxi(0, int(round(float(rr))))

		if energy.has("recharge_delay_ms"):
			var ms = energy.get("recharge_delay_ms")
			if typeof(ms) in [TYPE_INT, TYPE_FLOAT]:
				var ms_i: int = maxi(0, int(round(float(ms))))
				energy_recharge_delay_ticks = int((ms_i * DriftConstants.TICK_RATE + 999) / 1000)

		# Prefer new name if present; fall back to legacy.
		if energy.has("afterburner_drain_per_sec"):
			var d2 = energy.get("afterburner_drain_per_sec")
			if typeof(d2) in [TYPE_INT, TYPE_FLOAT]:
				energy_afterburner_drain_per_sec = maxi(0, int(round(float(d2))))
		elif energy.has("afterburner_drain_per_s"):
			var d = energy.get("afterburner_drain_per_s")
			if typeof(d) in [TYPE_INT, TYPE_FLOAT]:
				energy_afterburner_drain_per_sec = maxi(0, int(round(float(d))))

		if energy.has("bullet_energy_cost"):
			var bc = energy.get("bullet_energy_cost")
			if typeof(bc) in [TYPE_INT, TYPE_FLOAT]:
				bullet_energy_cost = maxi(0, int(round(float(bc))))
		if energy.has("multifire_energy_cost"):
			var mc = energy.get("multifire_energy_cost")
			if typeof(mc) in [TYPE_INT, TYPE_FLOAT]:
				bullet_multifire_energy_cost = maxi(0, int(round(float(mc))))
		if energy.has("bomb_energy_cost"):
			var boc = energy.get("bomb_energy_cost")
			if typeof(boc) in [TYPE_INT, TYPE_FLOAT]:
				bomb_energy_cost = maxi(0, int(round(float(boc))))


func set_map_dimensions(w_tiles: int, h_tiles: int) -> void:
	map_w_tiles = maxi(0, int(w_tiles))
	map_h_tiles = maxi(0, int(h_tiles))
	_recompute_main_walkable_component()
	# Reset spawn schedule when map changes.
	next_prize_spawn_tick = maxi(0, tick + prize_delay_ticks)
	# Clear any existing prizes from a previous map.
	prizes.clear()
	_prize_buckets.clear()
	prize_id_counter = 1


func apply_prize_config(prize_cfg: Dictionary, weights_by_key: Dictionary) -> void:
	# prize_cfg is a plain config dictionary from server.cfg (not a versioned contract).
	prize_delay_ticks = maxi(0, int(prize_cfg.get("prize_delay_ticks", 0)))
	prize_hide_count = clampi(int(prize_cfg.get("prize_hide_count", 0)), 0, 256)
	minimum_virtual = maxi(0, int(prize_cfg.get("minimum_virtual", 0)))
	upgrade_virtual = maxi(0, int(prize_cfg.get("upgrade_virtual", 0)))
	prize_min_exist_ticks = maxi(0, int(prize_cfg.get("prize_min_exist_ticks", 0)))
	prize_max_exist_ticks = maxi(prize_min_exist_ticks, int(prize_cfg.get("prize_max_exist_ticks", 0)))
	prize_negative_factor = maxi(0, int(prize_cfg.get("prize_negative_factor", 0)))
	death_prize_time_ticks = maxi(0, int(prize_cfg.get("death_prize_time_ticks", 0)))
	multi_prize_count = clampi(int(prize_cfg.get("multi_prize_count", 0)), 0, 16)
	engine_shutdown_time_ticks = maxi(0, int(prize_cfg.get("engine_shutdown_time_ticks", 0)))

	# Build weights table in enum order (deterministic).
	_prize_weights.clear()
	_prize_total_weight = 0
	var keys_in_order: Array[String] = DriftTypes.prize_kind_keys_in_order()
	_prize_weights.resize(keys_in_order.size())
	for i in range(keys_in_order.size()):
		var key := keys_in_order[i]
		var w: int = 0
		if typeof(weights_by_key) == TYPE_DICTIONARY and weights_by_key.has(key):
			w = int(weights_by_key.get(key, 0))
		w = maxi(0, w)
		_prize_weights[i] = w
		_prize_total_weight += w

	prize_enabled = (prize_delay_ticks > 0 and prize_hide_count > 0 and _prize_total_weight > 0)
	# Schedule next spawn relative to current tick.
	next_prize_spawn_tick = tick + prize_delay_ticks


func _prize_target_count_for_players(player_count: int) -> int:
	# Keep prize supply roughly proportional to players so large matches don't feel starved.
	# PrizeHideCount is treated as a *base* target capacity, then scaled up by player count.
	# Clamp defensively to keep CPU/memory bounded.
	var base_target: int = maxi(0, int(prize_hide_count))
	if base_target <= 0:
		return 0
	if player_count <= 1:
		return base_target
	const PLAYERS_PER_STEP: int = 5
	var steps: int = int(ceil(float(player_count) / float(PLAYERS_PER_STEP)))
	return clampi(base_target * maxi(1, steps), base_target, 256)


func _prize_spawn_delay_for_players(player_count: int) -> int:
	# Scale spawn delay down with player count, but clamp to avoid runaway spam.
	if prize_delay_ticks <= 0:
		return 0
	var p: int = maxi(1, int(player_count))
	var desired: int = int(round(float(prize_delay_ticks) / float(p)))
	# Never faster than 10x baseline (i.e., delay >= baseline/10).
	var min_delay: int = maxi(1, int(round(float(prize_delay_ticks) / 10.0)))
	var max_delay: int = maxi(1, int(prize_delay_ticks))
	return clampi(desired, min_delay, max_delay)


func _step_ship_energy(ship_state: DriftTypes.DriftShipState, input_cmd: DriftTypes.DriftInputCmd) -> void:
	# Deterministic, tick-based energy update.
	# - Recharge is linear and begins only after energy_recharge_wait_ticks reaches 0.
	# - Any drain event resets energy_recharge_wait_ticks to energy_recharge_delay_ticks.
	# - No float accumulation: recharge and continuous drains use integer remainder accumulators.

	# Tick down recharge wait.
	# Important: if the ship was waiting at the start of the tick, we do NOT allow recharge
	# to begin on the same tick the counter reaches 0 (avoids an off-by-one early recharge).
	var was_waiting: bool = int(ship_state.energy_recharge_wait_ticks) > 0
	if was_waiting:
		ship_state.energy_recharge_wait_ticks = int(ship_state.energy_recharge_wait_ticks) - 1
		if int(ship_state.energy_recharge_wait_ticks) < 0:
			ship_state.energy_recharge_wait_ticks = 0

	# Optional continuous drain: afterburner (Shift + forward thrust).
	# This keeps existing boost behavior while using deterministic integer math.
	var wants_afterburner: bool = bool(input_cmd.modifier) and float(input_cmd.thrust) > 0.0
	if wants_afterburner and int(ship_state.energy_current) > 0 and int(energy_afterburner_drain_per_sec) > 0:
		# Distribute per-second drain across ticks deterministically.
		ship_state.energy_drain_fp_accum += int(energy_afterburner_drain_per_sec)
		var drain_this_tick: int = int(ship_state.energy_drain_fp_accum) / DriftConstants.TICK_RATE
		ship_state.energy_drain_fp_accum = int(ship_state.energy_drain_fp_accum) % DriftConstants.TICK_RATE
		if drain_this_tick > 0:
			# Afterburner should not be blocked by "insufficient" energy; clamp to 0.
			ship_state.energy_current = maxi(0, int(ship_state.energy_current) - drain_this_tick)
			ship_state.energy_recharge_wait_ticks = int(ship_state.energy_recharge_delay_ticks)

	# Recharge (only when wait is zero, and we were not waiting at tick start).
	if (not was_waiting) and int(ship_state.energy_recharge_wait_ticks) == 0 and int(ship_state.energy_current) < int(ship_state.energy_max):
		var base_rate: int = maxi(0, int(ship_state.energy_recharge_rate_per_sec))
		# Apply recharge bonus deterministically as a rational percentage.
		var bonus: int = maxi(0, int(ship_state.recharge_bonus))
		var eff_rate: int = base_rate
		if bonus > 0 and base_rate > 0:
			eff_rate = base_rate + int((base_rate * RECHARGE_BONUS_PCT_NUM * bonus) / RECHARGE_BONUS_PCT_DEN)
		# Distribute per-second recharge across ticks deterministically.
		ship_state.energy_recharge_fp_accum += eff_rate
		var add_this_tick: int = int(ship_state.energy_recharge_fp_accum) / DriftConstants.TICK_RATE
		ship_state.energy_recharge_fp_accum = int(ship_state.energy_recharge_fp_accum) % DriftConstants.TICK_RATE
		if add_this_tick > 0:
			ship_state.energy_current = mini(int(ship_state.energy_max), int(ship_state.energy_current) + add_this_tick)

	# Keep legacy mirror updated.
	ship_state.energy = float(ship_state.energy_current)


func set_prize_rng_seed(seed_value: int) -> void:
	_prize_rng.seed = int(seed_value)


func _tile_for_world_pos(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / float(TILE_SIZE))), int(floor(pos.y / float(TILE_SIZE))))


func _world_pos_for_tile(t: Vector2i) -> Vector2:
	return Vector2((float(t.x) + 0.5) * float(TILE_SIZE), (float(t.y) + 0.5) * float(TILE_SIZE))


func _center_tile() -> Vector2i:
	if map_w_tiles > 0 and map_h_tiles > 0:
		return Vector2i(int(floor(map_w_tiles * 0.5)), int(floor(map_h_tiles * 0.5)))
	return _tile_for_world_pos(DriftConstants.ARENA_CENTER)


func _recompute_main_walkable_component() -> void:
	_main_walkable_tiles.clear()
	_main_walkable_set.clear()
	if map_w_tiles <= 0 or map_h_tiles <= 0:
		return

	# Use static solids (doors are dynamic); treat doors as walkable for reachability.
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var visited: Dictionary = {}
	var components: Array = [] # Array[Array[Vector2i]]
	for y in range(map_h_tiles):
		for x in range(map_w_tiles):
			var start := Vector2i(x, y)
			if visited.has(start):
				continue
			if _static_solid_tiles.has(start):
				visited[start] = true
				continue
			# Flood fill 4-neighborhood.
			var comp: Array = []
			var q: Array = [start]
			visited[start] = true
			while not q.is_empty():
				var cur: Vector2i = q.pop_back()
				comp.append(cur)
				for d: Vector2i in dirs:
					var n: Vector2i = cur + d
					if n.x < 0 or n.y < 0 or n.x >= map_w_tiles or n.y >= map_h_tiles:
						continue
					if visited.has(n):
						continue
					visited[n] = true
					if _static_solid_tiles.has(n):
						continue
					q.append(n)
			components.append(comp)

	if components.is_empty():
		return

	# Prefer the component containing the center tile; else pick the largest.
	var center := _center_tile()
	var chosen: Array = []
	var largest: Array = []
	for comp in components:
		if comp.size() > largest.size():
			largest = comp
		if chosen.is_empty():
			# quick membership: linear scan is ok for this size.
			for t in comp:
				if t == center:
					chosen = comp
					break
	if chosen.is_empty():
		chosen = largest

	_main_walkable_tiles = chosen
	for t in _main_walkable_tiles:
		_main_walkable_set[t] = true


func _prize_bucket_add(prize_id: int, pos: Vector2) -> void:
	var t := _tile_for_world_pos(pos)
	if not _prize_buckets.has(t):
		_prize_buckets[t] = []
	(_prize_buckets[t] as Array).append(prize_id)


func _prize_bucket_remove(prize_id: int, pos: Vector2) -> void:
	var t := _tile_for_world_pos(pos)
	if not _prize_buckets.has(t):
		return
	var arr: Array = _prize_buckets[t]
	arr.erase(prize_id)
	if arr.is_empty():
		_prize_buckets.erase(t)


func _pick_weighted_prize_kind(exclude_multiprize: bool) -> int:
	if _prize_total_weight <= 0:
		return -1
	# Compute total, optionally excluding MultiPrize.
	var total: int = 0
	for i in range(_prize_weights.size()):
		var kind: int = i
		if exclude_multiprize and kind == DriftTypes.PrizeKind.MultiPrize:
			continue
		var w: int = int(_prize_weights[i])
		if w <= 0:
			continue
		total += w
	if total <= 0:
		return -1
	var r: int = _prize_rng.randi_range(1, total)
	var acc: int = 0
	for i in range(_prize_weights.size()):
		var kind2: int = i
		if exclude_multiprize and kind2 == DriftTypes.PrizeKind.MultiPrize:
			continue
		var w2: int = int(_prize_weights[i])
		if w2 <= 0:
			continue
		acc += w2
		if r <= acc:
			return kind2
	return -1


func _is_negative_roll() -> bool:
	if prize_negative_factor <= 0:
		return false
	if prize_negative_factor == 1:
		return true
	return _prize_rng.randi_range(1, prize_negative_factor) == 1


func _spawn_prize_batch(player_count: int) -> void:
	if not prize_enabled:
		return
	if _main_walkable_tiles.is_empty():
		return
	var target_count: int = _prize_target_count_for_players(player_count)
	if target_count <= 0:
		return
	var missing: int = target_count - int(prizes.size())
	if missing <= 0:
		return
	const MAX_SPAWN_PER_EVENT: int = 4
	var spawn_budget: int = clampi(missing, 1, MAX_SPAWN_PER_EVENT)
	var center := _center_tile()
	var min_radius_tiles: float = float(minimum_virtual + upgrade_virtual * maxi(0, int(player_count)))

	for _i in range(spawn_budget):
		var kind: int = _pick_weighted_prize_kind(false)
		if kind < 0:
			return
		var is_negative: bool = _is_negative_roll()
		var lifetime_ticks: int = prize_min_exist_ticks
		if prize_max_exist_ticks > prize_min_exist_ticks:
			lifetime_ticks = _prize_rng.randi_range(prize_min_exist_ticks, prize_max_exist_ticks)
		var despawn_tick := tick + maxi(0, lifetime_ticks)

		var chosen_tile := Vector2i(-1, -1)
		for _attempt in range(PRIZE_SPAWN_ATTEMPTS):
			var idx: int = _prize_rng.randi_range(0, _main_walkable_tiles.size() - 1)
			var t: Vector2i = _main_walkable_tiles[idx]
			# Radius constraint.
			var dist_tiles: float = Vector2(t.x - center.x, t.y - center.y).length()
			if dist_tiles < min_radius_tiles:
				continue
			# Clump prevention: avoid spawning too close to an existing prize.
			var ok_spacing: bool = true
			for pid in prizes.keys():
				var p: DriftTypes.DriftPrizeState = prizes.get(pid)
				if p == null:
					continue
				var pt := _tile_for_world_pos(p.pos)
				if absi(pt.x - t.x) <= MIN_PRIZE_SPACING_TILES and absi(pt.y - t.y) <= MIN_PRIZE_SPACING_TILES:
					ok_spacing = false
					break
			if not ok_spacing:
				continue
			chosen_tile = t
			break

		if chosen_tile.x < 0:
			continue
		var pos := _world_pos_for_tile(chosen_tile)
		# Ensure not inside solid (paranoia).
		if is_position_blocked(pos, 6.0):
			continue
		var pid: int = prize_id_counter
		prize_id_counter += 1
		var ps := DriftTypes.DriftPrizeState.new(pid, pos, tick, despawn_tick, kind, is_negative, false)
		prizes[pid] = ps
		_prize_bucket_add(pid, pos)


func spawn_death_prize_at(pos: Vector2) -> void:
	if not prize_enabled:
		return
	if death_prize_time_ticks <= 0:
		return
	var kind: int = _pick_weighted_prize_kind(false)
	if kind < 0:
		return
	var pid: int = prize_id_counter
	prize_id_counter += 1
	var despawn_tick := tick + death_prize_time_ticks
	var ps := DriftTypes.DriftPrizeState.new(pid, pos, tick, despawn_tick, kind, false, true)
	prizes[pid] = ps
	_prize_bucket_add(pid, pos)


func _apply_prize_effect(ship_state: DriftTypes.DriftShipState, kind: int, is_negative: bool) -> void:
	# Always increment bounty for visibility.
	ship_state.bounty = maxi(0, int(ship_state.bounty) + 1)
	var applied_effect: bool = false

	# Minimal viable set with safe stubs.
	match kind:
		DriftTypes.PrizeKind.Energy:
			applied_effect = true
			var amt: int = 25
			if is_negative:
				# Negative prize drains energy (clamped) and resets recharge delay.
				ship_state.energy_current = maxi(0, int(ship_state.energy_current) - amt)
				ship_state.energy_recharge_wait_ticks = int(ship_state.energy_recharge_delay_ticks)
			else:
				add_energy(ship_state, amt)
			ship_state.energy = float(ship_state.energy_current)
		DriftTypes.PrizeKind.Recharge:
			applied_effect = true
			if is_negative:
				ship_state.recharge_bonus = maxi(0, int(ship_state.recharge_bonus) - 1)
			else:
				ship_state.recharge_bonus = mini(16, int(ship_state.recharge_bonus) + 1)
		DriftTypes.PrizeKind.TopSpeed:
			applied_effect = true
			if is_negative:
				ship_state.top_speed_bonus = maxi(0, int(ship_state.top_speed_bonus) - 1)
			else:
				ship_state.top_speed_bonus = mini(16, int(ship_state.top_speed_bonus) + 1)
		DriftTypes.PrizeKind.Thruster:
			applied_effect = true
			if is_negative:
				ship_state.thruster_bonus = maxi(0, int(ship_state.thruster_bonus) - 1)
			else:
				ship_state.thruster_bonus = mini(16, int(ship_state.thruster_bonus) + 1)
		DriftTypes.PrizeKind.Gun:
			applied_effect = true
			if is_negative:
				ship_state.gun_level = maxi(1, int(ship_state.gun_level) - 1)
			else:
				ship_state.gun_level = mini(3, int(ship_state.gun_level) + 1)
		DriftTypes.PrizeKind.Bomb:
			applied_effect = true
			if is_negative:
				ship_state.bomb_level = maxi(1, int(ship_state.bomb_level) - 1)
			else:
				ship_state.bomb_level = mini(3, int(ship_state.bomb_level) + 1)
		DriftTypes.PrizeKind.MultiFire:
			applied_effect = true
			if is_negative:
				ship_state.multi_fire_enabled = false
			else:
				ship_state.multi_fire_enabled = true
		DriftTypes.PrizeKind.BouncingBullets:
			applied_effect = true
			if is_negative:
				ship_state.bullet_bounce_bonus = maxi(0, int(ship_state.bullet_bounce_bonus) - 1)
			else:
				ship_state.bullet_bounce_bonus = mini(16, int(ship_state.bullet_bounce_bonus) + 1)
		DriftTypes.PrizeKind.MultiPrize:
			# Apply multiple positive prizes; never recurse into MultiPrize.
			for _i in range(multi_prize_count):
				var sub_kind: int = _pick_weighted_prize_kind(true)
				if sub_kind < 0:
					break
				_apply_prize_effect(ship_state, sub_kind, false)
		_:
			# Other prizes are currently stubs; must not crash.
			pass

	# Negative fallback: if negative prize would do nothing, apply EngineShutdown.
	if is_negative and not applied_effect:
		if engine_shutdown_time_ticks > 0:
			ship_state.engine_shutdown_until_tick = maxi(int(ship_state.engine_shutdown_until_tick), tick + engine_shutdown_time_ticks)


func _process_prize_despawns() -> void:
	if prizes.is_empty():
		return
	var ids: Array = prizes.keys()
	ids.sort()
	for pid in ids:
		var p: DriftTypes.DriftPrizeState = prizes.get(pid)
		if p == null:
			continue
		if int(p.despawn_tick) >= 0 and tick >= int(p.despawn_tick):
			_prize_bucket_remove(int(p.id), p.pos)
			prizes.erase(pid)


func _process_prize_pickups() -> void:
	if prizes.is_empty():
		return
	var pickup_r2: float = PRIZE_PICKUP_RADIUS * PRIZE_PICKUP_RADIUS
	var ship_ids: Array = ships.keys()
	ship_ids.sort()
	for sid in ship_ids:
		var s: DriftTypes.DriftShipState = ships.get(sid)
		if s == null:
			continue
		var st := _tile_for_world_pos(s.position)
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				var cell := Vector2i(st.x + dx, st.y + dy)
				if not _prize_buckets.has(cell):
					continue
				# Copy to avoid mutation during iteration.
				var cand: Array = (_prize_buckets[cell] as Array).duplicate(false)
				for pid in cand:
					if not prizes.has(pid):
						continue
					var p: DriftTypes.DriftPrizeState = prizes.get(pid)
					if p == null:
						continue
					if s.position.distance_squared_to(p.pos) <= pickup_r2:
						# Remove and apply.
						_prize_bucket_remove(int(p.id), p.pos)
						prizes.erase(pid)
						_apply_prize_effect(s, int(p.kind), bool(p.is_negative))
						prize_events.append({
							"type": "pickup",
							"ship_id": int(s.id),
							"prize_id": int(p.id),
						})

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

# Transient (server-auth): per-tick prize events for client-side audio/FX.
# Each entry is a Dictionary: {type, ship_id, prize_id}
var prize_events: Array = []


func _record_wall_bounce(ship_id: int, pos: Vector2, normal: Vector2, impact_speed: float) -> void:
	collision_events.append({
		"type": "wall",
		"ship_id": ship_id,
		"pos": pos,
		"normal": normal,
		"impact_speed": impact_speed,
	})


func add_ship(id: int, position: Vector2) -> void:
	var s: DriftTypes.DriftShipState = DriftTypes.DriftShipState.new(id, position)
	s.energy_max = maxi(0, int(energy_max_points))
	s.energy_current = s.energy_max
	s.energy_recharge_rate_per_sec = maxi(0, int(energy_recharge_rate_per_sec))
	s.energy_recharge_delay_ticks = maxi(0, int(energy_recharge_delay_ticks))
	s.energy_recharge_wait_ticks = 0
	s.energy_recharge_fp_accum = 0
	s.energy_drain_fp_accum = 0
	# Legacy mirror for older UI/debug.
	s.energy = float(s.energy_current)
	ships[id] = s


func drain_energy(ship: DriftTypes.DriftShipState, amount: int) -> bool:
	# Weapon-style drain: block if insufficient energy.
	var amt: int = maxi(0, int(amount))
	if amt <= 0:
		return true
	if int(ship.energy_current) < amt:
		return false
	ship.energy_current = int(ship.energy_current) - amt
	ship.energy_recharge_wait_ticks = int(ship.energy_recharge_delay_ticks)
	ship.energy = float(ship.energy_current)
	return true


func add_energy(ship: DriftTypes.DriftShipState, amount: int) -> void:
	var amt: int = maxi(0, int(amount))
	if amt <= 0:
		return
	ship.energy_current = mini(int(ship.energy_max), int(ship.energy_current) + amt)
	ship.energy = float(ship.energy_current)

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



func step_tick(inputs: Dictionary, include_prizes: bool = false, player_count_for_prizes: int = 0) -> DriftTypes.DriftWorldSnapshot:
	# Advance world tick.
	tick += 1
	_update_doors_for_current_tick()
	# Clear transient events each tick.
	collision_events.clear()
	prize_events.clear()

	# Stable update order for determinism.
	var ship_ids: Array = ships.keys()
	ship_ids.sort()


	for ship_id in ship_ids:
		var ship_state: DriftTypes.DriftShipState = ships[ship_id]
		var input_cmd: DriftTypes.DriftInputCmd = inputs.get(ship_id, DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false))
		_step_ship_energy(ship_state, input_cmd)
		# Engine shutdown (negative prize effect): thrust/rotation disabled, firing allowed.
		if int(ship_state.engine_shutdown_until_tick) > 0 and tick < int(ship_state.engine_shutdown_until_tick):
			input_cmd = DriftTypes.DriftInputCmd.new(0.0, 0.0, bool(input_cmd.fire_primary), bool(input_cmd.fire_secondary), bool(input_cmd.modifier))
		
		# Store position before movement
		var old_position := ship_state.position
		
		DriftShip.apply_input(
			ship_state,
			input_cmd,
			DriftConstants.TICK_DT,
			ship_turn_rate,
			_ship_effective_thrust_accel(ship_state, input_cmd),
			_ship_effective_reverse_accel(ship_state),
			_ship_effective_max_speed(ship_state),
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
	var kicked_ship_id: int = -1
	if ball.owner_id != -1 and inputs.has(ball.owner_id) and inputs[ball.owner_id].fire_primary:
		kicked_ship_id = int(ball.owner_id)
		var owner = ships[ball.owner_id]
		ball.owner_id = -1
		var fwd = Vector2(cos(owner.rotation), sin(owner.rotation))
		ball.velocity = owner.velocity + fwd * ball_kick_speed
		ball.position = owner.position + fwd * (DriftConstants.SHIP_RADIUS + DriftConstants.BALL_RADIUS + 2.0)

	# --- Bullets ---
	# Fire bullets only when NOT currently holding the ball.
	# Edge-triggered fire (no additional weapon state needed in snapshots).
	for ship_id in ship_ids:
		if not inputs.has(ship_id):
			continue
		var cmd: DriftTypes.DriftInputCmd = inputs[ship_id]
		var prev_fire: bool = bool(_prev_fire_by_ship.get(ship_id, false))
		_prev_fire_by_ship[ship_id] = bool(cmd.fire_primary)
		if not cmd.fire_primary or prev_fire:
			continue
		if ship_id == kicked_ship_id:
			continue
		if ball.owner_id == ship_id:
			continue
		if not ships.has(ship_id):
			continue

		var ship_state: DriftTypes.DriftShipState = ships[ship_id]
		var fwd := Vector2(cos(ship_state.rotation), sin(ship_state.rotation))
		var right := Vector2(-fwd.y, fwd.x)

		# Defaults.
		var eff_speed: float = bullet_speed
		var eff_lifetime_ticks: int = bullet_lifetime_ticks
		var eff_muzzle_offset: float = bullet_muzzle_offset
		var guns: int = 1
		var multi_fire: bool = false
		var eff_bounces: int = bullet_bounces
		var eff_bounce_restitution: float = bullet_bounce_restitution
		var eff_level: int = clampi(int(ship_state.gun_level), 1, 3)
		var toggle_multishot: bool = bool(ship_state.multi_fire_enabled)
		var toggle_bounce: bool = (int(ship_state.bullet_bounce_bonus) > 0)

		# Optional level profiles (ruleset.weapons.bullet.levels).
		var level_cfg: Dictionary = {}
		var rs_weapons: Dictionary = ruleset.get("weapons", {})
		var levels: Dictionary = {}
		if typeof(rs_weapons) == TYPE_DICTIONARY and rs_weapons.has("bullet") and typeof(rs_weapons.get("bullet")) == TYPE_DICTIONARY:
			var rs_bullet: Dictionary = rs_weapons.get("bullet")
			if rs_bullet.has("levels") and typeof(rs_bullet.get("levels")) == TYPE_DICTIONARY:
				levels = rs_bullet.get("levels")
				if levels.has(str(eff_level)) and typeof(levels.get(str(eff_level))) == TYPE_DICTIONARY:
					level_cfg = levels.get(str(eff_level))

		# Per-ship overrides (ruleset is validated canonical).
		var rs_ships: Dictionary = ruleset.get("ships", {})
		if typeof(rs_ships) == TYPE_DICTIONARY:
			var ship_key := str(ship_id)
			if rs_ships.has(ship_key) and typeof(rs_ships.get(ship_key)) == TYPE_DICTIONARY:
				var ship_cfg: Dictionary = rs_ships.get(ship_key)
				if ship_cfg.has("weapons") and typeof(ship_cfg.get("weapons")) == TYPE_DICTIONARY:
					var ship_weapons: Dictionary = ship_cfg.get("weapons")
					if ship_weapons.has("bullet") and typeof(ship_weapons.get("bullet")) == TYPE_DICTIONARY:
						var sb: Dictionary = ship_weapons.get("bullet")
						# New (optional): gun level + toggles.
						eff_level = int(sb.get("level", eff_level))
						# Re-resolve level profile after applying the per-ship level.
						if typeof(levels) == TYPE_DICTIONARY and levels.has(str(eff_level)) and typeof(levels.get(str(eff_level))) == TYPE_DICTIONARY:
							level_cfg = levels.get(str(eff_level))
						toggle_multishot = bool(sb.get("multishot", toggle_multishot))
						toggle_bounce = bool(sb.get("bounce", toggle_bounce))

						# Apply level profile first (if present), then explicit per-ship overrides.
						if typeof(level_cfg) == TYPE_DICTIONARY and not level_cfg.is_empty():
							guns = int(level_cfg.get("guns", guns))
							multi_fire = bool(level_cfg.get("multi_fire", multi_fire))
							eff_speed = float(level_cfg.get("speed", eff_speed))
							eff_muzzle_offset = float(level_cfg.get("muzzle_offset", eff_muzzle_offset))
							eff_bounces = int(level_cfg.get("bounces", eff_bounces))
							eff_bounce_restitution = float(level_cfg.get("bounce_restitution", eff_bounce_restitution))
							if level_cfg.has("lifetime_s"):
								eff_lifetime_ticks = int(round(float(level_cfg.get("lifetime_s")) / DriftConstants.TICK_DT))

						guns = int(sb.get("guns", guns))
						multi_fire = bool(sb.get("multi_fire", multi_fire))
						eff_speed = float(sb.get("speed", eff_speed))
						eff_muzzle_offset = float(sb.get("muzzle_offset", eff_muzzle_offset))
						eff_bounces = int(sb.get("bounces", eff_bounces))
						eff_bounce_restitution = float(sb.get("bounce_restitution", eff_bounce_restitution))
						if sb.has("lifetime_s"):
							eff_lifetime_ticks = int(round(float(sb.get("lifetime_s")) / DriftConstants.TICK_DT))

		# Apply toggles (if present) as final modifiers.
		if toggle_multishot:
			multi_fire = true
		if toggle_bounce and eff_bounces <= 0:
			eff_bounces = 1
		eff_bounces += clampi(int(ship_state.bullet_bounce_bonus), 0, 16)

		guns = clampi(guns, 1, 8)
		eff_bounces = clampi(eff_bounces, 0, 16)
		eff_bounce_restitution = clampf(eff_bounce_restitution, 0.0, 2.0)
		var fire_guns: Array[int] = []
		if multi_fire or guns == 1:
			for gi in range(guns):
				fire_guns.append(gi)
		else:
			# Deterministic single-gun cycling without any extra persistent state.
			var idx: int = int(posmod(tick + ship_id, guns))
			fire_guns.append(idx)

		# Energy gate: firing drains energy and blocks if insufficient.
		var shots: int = fire_guns.size()
		var cost: int = int(bullet_energy_cost)
		if shots > 1:
			cost = int(bullet_multifire_energy_cost)
		if cost > 0 and not drain_energy(ship_state, cost):
			continue

		for gi in fire_guns:
			var centered := float(gi) - (float(guns - 1) * 0.5)
			var lateral := centered * bullet_gun_spacing
			var spawn_pos := ship_state.position + fwd * eff_muzzle_offset + right * lateral
			var vel := ship_state.velocity + fwd * eff_speed
			var die_tick := tick + maxi(0, eff_lifetime_ticks)
			var bstate := DriftTypes.DriftBulletState.new(_next_bullet_id, ship_id, spawn_pos, vel, tick, die_tick, eff_bounces)
			bullets[_next_bullet_id] = bstate
			_next_bullet_id += 1

	# Step bullets (movement + despawn).
	var bullet_ids: Array = bullets.keys()
	bullet_ids.sort()
	var to_remove: Array[int] = []
	for bid in bullet_ids:
		var b: DriftTypes.DriftBulletState = bullets.get(bid)
		if b == null:
			continue
		if b.die_tick >= 0 and tick >= b.die_tick:
			to_remove.append(int(bid))
			continue
		var next_pos := b.position + b.velocity * DriftConstants.TICK_DT
		# Arena bounds check.
		if next_pos.x < DriftConstants.ARENA_MIN.x or next_pos.x > DriftConstants.ARENA_MAX.x or next_pos.y < DriftConstants.ARENA_MIN.y or next_pos.y > DriftConstants.ARENA_MAX.y:
			to_remove.append(int(bid))
			continue
		# Tile collision check (treat bullets as small circles).
		if is_position_blocked(next_pos, bullet_radius):
			if int(b.bounces_left) <= 0:
				to_remove.append(int(bid))
				continue
			var n: Vector2 = get_collision_normal(b.position, next_pos, bullet_radius)
			if n == Vector2.ZERO:
				to_remove.append(int(bid))
				continue
			# Sweep to last non-colliding point to avoid tunneling/jitter.
			const SWEEP_ITERS_BULLET: int = 10
			var t_lo := 0.0
			var t_hi := 1.0
			for _i in range(SWEEP_ITERS_BULLET):
				var t_mid := (t_lo + t_hi) * 0.5
				var cand := b.position.lerp(next_pos, t_mid)
				if is_position_blocked(cand, bullet_radius):
					t_hi = t_mid
				else:
					t_lo = t_mid
			var contact_pos := b.position.lerp(next_pos, t_lo)
			b.position = contact_pos - n * SEPARATION_EPSILON
			if is_position_blocked(b.position, bullet_radius):
				to_remove.append(int(bid))
				continue
			# Reflect velocity with optional restitution.
			var vdotn: float = b.velocity.dot(n)
			if vdotn < 0.0:
				var v_t: Vector2 = b.velocity - n * vdotn
				var normal_speed: float = -vdotn
				var restitution: float = _resolve_bullet_bounce_restitution_for_ship(int(b.owner_id))
				b.velocity = v_t + n * (normal_speed * restitution)
			b.bounces_left = int(b.bounces_left) - 1
			continue
		b.position = next_pos

	for bid in to_remove:
		bullets.erase(bid)

	# Server-only prize simulation (authoritative). Must not run in client prediction.
	if include_prizes and prize_enabled:
		_process_prize_despawns()
		_process_prize_pickups()
		if tick >= next_prize_spawn_tick:
			_spawn_prize_batch(player_count_for_prizes)
			var dt: int = _prize_spawn_delay_for_players(player_count_for_prizes)
			next_prize_spawn_tick = tick + dt

	# Return a snapshot (deep copy of ship states and ball)
	var snapshot_ships: Dictionary = {}
	for ship_id in ship_ids:
		snapshot_ships[ship_id] = _copy_ship_state(ships[ship_id])
	# Bullets snapshot (stable by id).
	var snapshot_bullets: Array = []
	var snapshot_bullet_ids: Array = bullets.keys()
	snapshot_bullet_ids.sort()
	for bid in snapshot_bullet_ids:
		var b: DriftTypes.DriftBulletState = bullets.get(bid)
		if b == null:
			continue
		snapshot_bullets.append(DriftTypes.DriftBulletState.new(b.id, b.owner_id, b.position, b.velocity, b.spawn_tick, b.die_tick, b.bounces_left))

	var snapshot_prizes: Array = []
	if include_prizes:
		var snapshot_prize_ids: Array = prizes.keys()
		snapshot_prize_ids.sort()
		for pid in snapshot_prize_ids:
			var p: DriftTypes.DriftPrizeState = prizes.get(pid)
			if p == null:
				continue
			snapshot_prizes.append(p)

	return DriftTypes.DriftWorldSnapshot.new(tick, snapshot_ships, ball.position, ball.velocity, ball.owner_id, snapshot_bullets, snapshot_prizes)


func _ship_effective_max_speed(ship_state: DriftTypes.DriftShipState) -> float:
	var bonus: int = int(ship_state.top_speed_bonus)
	return ship_max_speed * (1.0 + TOP_SPEED_BONUS_PCT * float(bonus))


func _ship_effective_reverse_accel(_ship_state: DriftTypes.DriftShipState) -> float:
	# Thruster affects forward thrust only; keep reverse stable.
	return ship_reverse_accel


func _ship_effective_thrust_accel(ship_state: DriftTypes.DriftShipState, input_cmd: DriftTypes.DriftInputCmd) -> float:
	var thrust_bonus: int = int(ship_state.thruster_bonus)
	var base: float = ship_thrust_accel * (1.0 + THRUSTER_BONUS_PCT * float(thrust_bonus))
	var wants_afterburner: bool = bool(input_cmd.modifier) and float(input_cmd.thrust) > 0.0
	if wants_afterburner and int(ship_state.energy_current) > 0:
		return base * energy_afterburner_multiplier
	return base


func _copy_ship_state(source: DriftTypes.DriftShipState) -> DriftTypes.DriftShipState:
	return DriftTypes.DriftShipState.new(
		source.id,
		source.position,
		source.velocity,
		source.rotation,
		source.username,
		source.bounty,
		source.gun_level,
		source.bomb_level,
		source.multi_fire_enabled,
		source.bullet_bounce_bonus,
		source.engine_shutdown_until_tick,
		source.top_speed_bonus,
		source.thruster_bonus,
		source.recharge_bonus,
		source.energy,
		source.energy_current,
		source.energy_max,
		source.energy_recharge_rate_per_sec,
		source.energy_recharge_delay_ticks,
		source.energy_recharge_wait_ticks,
		source.energy_recharge_fp_accum,
		source.energy_drain_fp_accum
	)
