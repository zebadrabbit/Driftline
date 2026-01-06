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
var ability_stealth_drain_per_sec: int = 0
var ability_cloak_drain_per_sec: int = 0
var ability_xradar_drain_per_sec: int = 0
var ability_antiwarp_drain_per_sec: int = 0
var ability_antiwarp_radius_px: int = 0
var bullet_energy_cost: int = DriftConstants.DEFAULT_BULLET_ENERGY_COST
var bullet_multifire_energy_cost: int = DriftConstants.DEFAULT_MULTIFIRE_ENERGY_COST
var bomb_energy_cost: int = DriftConstants.DEFAULT_BOMB_ENERGY_COST
var energy_afterburner_multiplier: float = 1.6
var energy_afterburner_speed_multiplier: float = 1.0

# Combat tuning.
# Spawn protection blocks damage application for a short period after spawn/respawn.
var spawn_protect_ticks: int = 0

# Death/respawn tuning.
# Respawn delay after combat death (apply_damage drove energy to 0).
var respawn_delay_ticks: int = int((1500 * DriftConstants.TICK_RATE + 999) / 1000)


# Safe-zone camping limit.
# 0 disables.
var safe_zone_max_ticks: int = 0


# Team / friendly-fire tuning (schema v2; engine defaults apply if omitted).
# - team_max_freq: 0 means FFA; otherwise teams are 0..team_max_freq-1.
# - team_force_even: used for server-enforced manual team changes.
# - combat_friendly_fire: if true, same-team damage is allowed.
var team_max_freq: int = 2
var team_force_even: bool = true
var combat_friendly_fire: bool = false


func _ship_is_dead(ship_state: DriftTypes.DriftShipState, tick_value: int) -> bool:
	return int(ship_state.dead_until_tick) > 0 and int(tick_value) < int(ship_state.dead_until_tick)

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
var _prev_ability_buttons_by_ship: Dictionary = {} # Dictionary[int, int]


static func _q(v: float, scale: float = 1000.0) -> int:
	# Quantize floats into deterministic integers for hashing.
	return int(round(float(v) * float(scale)))


static func _qb(v: bool) -> int:
	return 1 if bool(v) else 0


func compute_world_hash() -> int:
	# Deterministic per-tick hash of gameplay-relevant world state.
	#
	# Rules:
	# - Only include authoritative state that could affect future simulation.
	# - Never depend on Dictionary iteration order; sort keys.
	# - Quantize floats.
	const Q_POS: float = 1000.0
	const Q_VEL: float = 1000.0
	const Q_ROT: float = 1000000.0
	const Q_TUNE: float = 1000000.0

	var parts := PackedStringArray()
	parts.append("DRIFTWORLD_HASH_V1")

	# Core tick + map/config.
	parts.append("tick=%d" % int(tick))
	parts.append("map=%dx%d" % [int(map_w_tiles), int(map_h_tiles)])

	# Effective tuning values (authoritative; must match for determinism).
	parts.append("wall_restitution=%d" % _q(wall_restitution, Q_TUNE))
	parts.append("tangent_damping=%d" % _q(tangent_damping, Q_TUNE))
	parts.append("ship_turn_rate=%d" % _q(ship_turn_rate, Q_TUNE))
	parts.append("ship_thrust_accel=%d" % _q(ship_thrust_accel, Q_TUNE))
	parts.append("ship_reverse_accel=%d" % _q(ship_reverse_accel, Q_TUNE))
	parts.append("ship_max_speed=%d" % _q(ship_max_speed, Q_TUNE))
	parts.append("ship_base_drag=%d" % _q(ship_base_drag, Q_TUNE))
	parts.append("ship_overspeed_drag=%d" % _q(ship_overspeed_drag, Q_TUNE))
	parts.append("ship_bounce_min_normal_speed=%d" % _q(ship_bounce_min_normal_speed, Q_TUNE))

	parts.append("ball_friction=%d" % _q(ball_friction, Q_TUNE))
	parts.append("ball_max_speed=%d" % _q(ball_max_speed, Q_TUNE))
	parts.append("ball_kick_speed=%d" % _q(ball_kick_speed, Q_TUNE))
	parts.append("ball_knock_impulse=%d" % _q(ball_knock_impulse, Q_TUNE))
	parts.append("ball_stick_offset=%d" % _q(ball_stick_offset, Q_TUNE))
	parts.append("ball_steal_padding=%d" % _q(ball_steal_padding, Q_TUNE))

	parts.append("energy_max_points=%d" % int(energy_max_points))
	parts.append("energy_recharge_rate_per_sec=%d" % int(energy_recharge_rate_per_sec))
	parts.append("energy_recharge_delay_ticks=%d" % int(energy_recharge_delay_ticks))
	parts.append("energy_afterburner_drain_per_sec=%d" % int(energy_afterburner_drain_per_sec))
	parts.append("ability_stealth_drain_per_sec=%d" % int(ability_stealth_drain_per_sec))
	parts.append("ability_cloak_drain_per_sec=%d" % int(ability_cloak_drain_per_sec))
	parts.append("ability_xradar_drain_per_sec=%d" % int(ability_xradar_drain_per_sec))
	parts.append("ability_antiwarp_drain_per_sec=%d" % int(ability_antiwarp_drain_per_sec))
	parts.append("ability_antiwarp_radius_px=%d" % int(ability_antiwarp_radius_px))
	parts.append("bullet_energy_cost=%d" % int(bullet_energy_cost))
	parts.append("bullet_multifire_energy_cost=%d" % int(bullet_multifire_energy_cost))
	parts.append("bomb_energy_cost=%d" % int(bomb_energy_cost))
	parts.append("energy_afterburner_multiplier=%d" % _q(energy_afterburner_multiplier, Q_TUNE))
	parts.append("energy_afterburner_speed_multiplier=%d" % _q(energy_afterburner_speed_multiplier, Q_TUNE))

	parts.append("spawn_protect_ticks=%d" % int(spawn_protect_ticks))
	parts.append("respawn_delay_ticks=%d" % int(respawn_delay_ticks))
	parts.append("safe_zone_max_ticks=%d" % int(safe_zone_max_ticks))
	parts.append("team_max_freq=%d" % int(team_max_freq))
	parts.append("team_force_even=%d" % _qb(team_force_even))
	parts.append("combat_friendly_fire=%d" % _qb(combat_friendly_fire))

	# Prize/bullet systems state that affects future simulation.
	parts.append("prize_enabled=%d" % _qb(prize_enabled))
	parts.append("next_prize_spawn_tick=%d" % int(next_prize_spawn_tick))
	parts.append("prize_id_counter=%d" % int(prize_id_counter))
	parts.append("_next_bullet_id=%d" % int(_next_bullet_id))

	# RNG state (authoritative streams).
	parts.append("prize_rng_seed=%d" % int(_prize_rng.seed))
	parts.append("prize_rng_state=%d" % int(_prize_rng.state))
	parts.append("spawn_rng_seed=%d" % int(_spawn_rng.seed))
	parts.append("spawn_rng_state=%d" % int(_spawn_rng.state))

	# Edge-detection state.
	var pf_ids: Array = _prev_fire_by_ship.keys()
	pf_ids.sort()
	for sid in pf_ids:
		parts.append("pf:%d=%d" % [int(sid), _qb(_prev_fire_by_ship.get(sid, false))])
	var pab_ids: Array = _prev_ability_buttons_by_ship.keys()
	pab_ids.sort()
	for sid in pab_ids:
		parts.append("pab:%d=%d" % [int(sid), int(_prev_ability_buttons_by_ship.get(sid, 0))])

	# Solid tiles (affects movement/collisions).
	var solid_keys: Array = solid_tiles.keys()
	solid_keys.sort_custom(func(a, b):
		if not (a is Vector2i) or not (b is Vector2i):
			return false
		var va: Vector2i = a
		var vb: Vector2i = b
		return (va.y < vb.y) or (va.y == vb.y and va.x < vb.x)
	)
	for c in solid_keys:
		if c is Vector2i:
			var v: Vector2i = c
			parts.append("solid=%d,%d" % [int(v.x), int(v.y)])

	# Ships (stable order).
	var ship_ids: Array = ships.keys()
	ship_ids.sort()
	for sid in ship_ids:
		var s: DriftTypes.DriftShipState = ships.get(sid)
		if s == null:
			continue
		parts.append("ship=%d" % int(s.id))
		parts.append("p=%d,%d" % [_q(float(s.position.x), Q_POS), _q(float(s.position.y), Q_POS)])
		parts.append("v=%d,%d" % [_q(float(s.velocity.x), Q_VEL), _q(float(s.velocity.y), Q_VEL)])
		parts.append("r=%d" % _q(float(s.rotation), Q_ROT))
		parts.append("freq=%d" % int(s.freq))
		parts.append("bounty=%d" % int(s.bounty))
		parts.append("sz_used=%d" % int(s.safe_zone_time_used_ticks))
		parts.append("sz_max=%d" % int(s.safe_zone_time_max_ticks))
		parts.append("dead_until=%d" % int(s.dead_until_tick))
		parts.append("dmg_protect=%d" % int(s.damage_protect_until_tick))
		parts.append("gun=%d" % int(s.gun_level))
		parts.append("bomb=%d" % int(s.bomb_level))
		parts.append("multi=%d" % _qb(s.multi_fire_enabled))
		parts.append("bbounce=%d" % int(s.bullet_bounce_bonus))
		parts.append("shutdown=%d" % int(s.engine_shutdown_until_tick))
		parts.append("top=%d" % int(s.top_speed_bonus))
		parts.append("thr=%d" % int(s.thruster_bonus))
		parts.append("rech=%d" % int(s.recharge_bonus))
		parts.append("e_cur=%d" % int(s.energy_current))
		parts.append("e_max=%d" % int(s.energy_max))
		parts.append("e_rr=%d" % int(s.energy_recharge_rate_per_sec))
		parts.append("e_delay=%d" % int(s.energy_recharge_delay_ticks))
		parts.append("e_wait=%d" % int(s.energy_recharge_wait_ticks))
		parts.append("e_racc=%d" % int(s.energy_recharge_fp_accum))
		parts.append("e_dacc=%d" % int(s.energy_drain_fp_accum))
		parts.append("ab=%d" % _qb(s.afterburner_on))
		parts.append("st=%d" % _qb(s.stealth_on))
		parts.append("ck=%d" % _qb(s.cloak_on))
		parts.append("xr=%d" % _qb(s.xradar_on))
		parts.append("aw=%d" % _qb(s.antiwarp_on))
		parts.append("in_safe=%d" % _qb(s.in_safe_zone))
		parts.append("lecr=%d" % int(s.last_energy_change_reason))
		parts.append("lecs=%d" % int(s.last_energy_change_source_id))
		parts.append("lect=%d" % int(s.last_energy_change_tick))

	# Bullets (stable order).
	var bullet_ids: Array = bullets.keys()
	bullet_ids.sort()
	for bid in bullet_ids:
		var b: DriftTypes.DriftBulletState = bullets.get(bid)
		if b == null:
			continue
		parts.append("bullet=%d" % int(b.id))
		parts.append("bo=%d" % int(b.owner_id))
		parts.append("bl=%d" % int(b.level))
		parts.append("bp=%d,%d" % [_q(float(b.position.x), Q_POS), _q(float(b.position.y), Q_POS)])
		parts.append("bv=%d,%d" % [_q(float(b.velocity.x), Q_VEL), _q(float(b.velocity.y), Q_VEL)])
		parts.append("bs=%d" % int(b.spawn_tick))
		parts.append("bd=%d" % int(b.die_tick))
		parts.append("bb=%d" % int(b.bounces_left))

	# Prizes (stable order).
	var prize_ids: Array = prizes.keys()
	prize_ids.sort()
	for pid in prize_ids:
		var p: DriftTypes.DriftPrizeState = prizes.get(pid)
		if p == null:
			continue
		parts.append("prize=%d" % int(p.id))
		parts.append("pp=%d,%d" % [_q(float(p.pos.x), Q_POS), _q(float(p.pos.y), Q_POS)])
		parts.append("ps=%d" % int(p.spawn_tick))
		parts.append("pd=%d" % int(p.despawn_tick))
		parts.append("pk=%d" % int(p.kind))
		parts.append("pn=%d" % _qb(p.is_negative))
		parts.append("pdd=%d" % _qb(p.is_death_drop))

	# Ball.
	parts.append("ball_owner=%d" % int(ball.owner_id))
	parts.append("ball_p=%d,%d" % [_q(float(ball.position.x), Q_POS), _q(float(ball.position.y), Q_POS)])
	parts.append("ball_v=%d,%d" % [_q(float(ball.velocity.x), Q_VEL), _q(float(ball.velocity.y), Q_VEL)])

	return "|".join(parts).hash()

# Effective bullet tuning values used by the deterministic sim.
var bullet_speed: float = 950.0
var bullet_lifetime_ticks: int = 24
var bullet_muzzle_offset: float = float(DriftConstants.SHIP_RADIUS) + 10.0
var bullet_radius: float = 2.0
var bullet_gun_spacing: float = 8.0
var bullet_bounces: int = 0
var bullet_bounce_restitution: float = 1.0

# Tactical bullet options (ruleset-configurable; deterministic).
# - cooldown_ticks is enforced as a tick-phase gate: ship can only fire on ticks where
#   (tick + ship_id) % cooldown_ticks == 0.
var bullet_cooldown_ticks: int = 0
var bullet_spread_deg: float = 0.0
var bullet_shrapnel_count: int = 0
var bullet_shrapnel_speed_mult: float = 0.65
var bullet_shrapnel_lifetime_ticks: int = 10
var bullet_shrapnel_cone_deg: float = 70.0


func _resolve_bullet_bounce_restitution_for_bullet(owner_id: int, bullet_level: int) -> float:
	# IMPORTANT: bounce is per-projectile.
	# Use the bullet's snapshot-stable weapon level (b.level), not any current ship state,
	# so mid-flight upgrades cannot change existing projectiles.
	var restitution: float = bullet_bounce_restitution
	var eff_level: int = clampi(int(bullet_level), 1, 3)

	# Optional level profiles live under ruleset.weapons.bullet.levels.
	var rs_weapons: Dictionary = ruleset.get("weapons", {})
	if typeof(rs_weapons) == TYPE_DICTIONARY and rs_weapons.has("bullet") and typeof(rs_weapons.get("bullet")) == TYPE_DICTIONARY:
		var rs_bullet: Dictionary = rs_weapons.get("bullet")
		if rs_bullet.has("levels") and typeof(rs_bullet.get("levels")) == TYPE_DICTIONARY:
			var levels: Dictionary = rs_bullet.get("levels")
			if typeof(levels) == TYPE_DICTIONARY and levels.has(str(eff_level)) and typeof(levels.get(str(eff_level))) == TYPE_DICTIONARY:
				var level_cfg: Dictionary = levels.get(str(eff_level))
				restitution = float(level_cfg.get("bounce_restitution", restitution))

	# Per-ship override (static ruleset config; safe to apply without breaking per-projectile behavior).
	var rs_ships: Dictionary = ruleset.get("ships", {})
	if typeof(rs_ships) == TYPE_DICTIONARY:
		var ship_key := str(int(owner_id))
		if rs_ships.has(ship_key) and typeof(rs_ships.get(ship_key)) == TYPE_DICTIONARY:
			var ship_cfg: Dictionary = rs_ships.get(ship_key)
			if ship_cfg.has("weapons") and typeof(ship_cfg.get("weapons")) == TYPE_DICTIONARY:
				var ship_weapons: Dictionary = ship_cfg.get("weapons")
				if ship_weapons.has("bullet") and typeof(ship_weapons.get("bullet")) == TYPE_DICTIONARY:
					var sb: Dictionary = ship_weapons.get("bullet")
					restitution = float(sb.get("bounce_restitution", restitution))

	return clampf(restitution, 0.0, 2.0)


func apply_ruleset(canonical_ruleset: Dictionary) -> void:
	# Must only be called with a validated driftline.ruleset dict.
	ruleset = canonical_ruleset
	var schema_version: int = int(canonical_ruleset.get("schema_version", 1))

	# Zones tuning (schema v2 only).
	safe_zone_max_ticks = 0
	if schema_version >= 2:
		var zones: Dictionary = canonical_ruleset.get("zones", {})
		if typeof(zones) == TYPE_DICTIONARY and zones.has("safe_zone_max_ms"):
			var ms: int = maxi(0, int(zones.get("safe_zone_max_ms")))
			# Convert ms -> ticks (ceil) to avoid expiring earlier than configured.
			safe_zone_max_ticks = int((ms * DriftConstants.TICK_RATE + 999) / 1000)

	# Keep per-ship max in sync for snapshot replication.
	for ship_id in ships.keys():
		var s0: DriftTypes.DriftShipState = ships.get(ship_id)
		if s0 != null:
			s0.safe_zone_time_max_ticks = int(safe_zone_max_ticks)

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
			bullet_cooldown_ticks = int(b.get("cooldown_ticks", bullet_cooldown_ticks))
			bullet_spread_deg = float(b.get("spread_deg", bullet_spread_deg))
			bullet_shrapnel_count = int(b.get("shrapnel_count", bullet_shrapnel_count))
			bullet_shrapnel_speed_mult = float(b.get("shrapnel_speed_mult", bullet_shrapnel_speed_mult))
			bullet_shrapnel_cone_deg = float(b.get("shrapnel_cone_deg", bullet_shrapnel_cone_deg))
			if b.has("shrapnel_lifetime_s"):
				var sl: float = float(b.get("shrapnel_lifetime_s"))
				bullet_shrapnel_lifetime_ticks = int(round(sl / DriftConstants.TICK_DT))
			if b.has("lifetime_s"):
				var lifetime_s: float = float(b.get("lifetime_s"))
				bullet_lifetime_ticks = int(round(lifetime_s / DriftConstants.TICK_DT))

			bullet_cooldown_ticks = clampi(bullet_cooldown_ticks, 0, 120)
			bullet_spread_deg = clampf(bullet_spread_deg, 0.0, 45.0)
			bullet_shrapnel_count = clampi(bullet_shrapnel_count, 0, 16)
			bullet_shrapnel_speed_mult = clampf(bullet_shrapnel_speed_mult, 0.0, 2.0)
			bullet_shrapnel_lifetime_ticks = clampi(bullet_shrapnel_lifetime_ticks, 0, 600)
			bullet_shrapnel_cone_deg = clampf(bullet_shrapnel_cone_deg, 0.0, 360.0)

	# Ensure sane defaults even if ruleset omitted bullet section.
	bullet_cooldown_ticks = clampi(bullet_cooldown_ticks, 0, 120)
	bullet_spread_deg = clampf(bullet_spread_deg, 0.0, 45.0)
	bullet_shrapnel_count = clampi(bullet_shrapnel_count, 0, 16)
	bullet_shrapnel_speed_mult = clampf(bullet_shrapnel_speed_mult, 0.0, 2.0)
	bullet_shrapnel_lifetime_ticks = clampi(bullet_shrapnel_lifetime_ticks, 0, 600)
	bullet_shrapnel_cone_deg = clampf(bullet_shrapnel_cone_deg, 0.0, 360.0)

	# Abilities section (schema v2).
	# Note: schema v1 has no abilities block; ability drains and behavior are engine-disabled.
	energy_afterburner_speed_multiplier = 1.0
	energy_afterburner_multiplier = 1.6
	ability_stealth_drain_per_sec = 0
	ability_cloak_drain_per_sec = 0
	ability_xradar_drain_per_sec = 0
	ability_antiwarp_drain_per_sec = 0
	ability_antiwarp_radius_px = 0
	if schema_version >= 2:
		var abilities: Dictionary = canonical_ruleset.get("abilities", {})
		if typeof(abilities) == TYPE_DICTIONARY and not abilities.is_empty():
			if abilities.has("afterburner") and typeof(abilities.get("afterburner")) == TYPE_DICTIONARY:
				var ab: Dictionary = abilities.get("afterburner")
				if ab.has("drain_per_sec"):
					energy_afterburner_drain_per_sec = maxi(0, int(round(float(ab.get("drain_per_sec")))))
				# Defaults preserve prior behavior (thrust boost only; no speed cap change).
				var sp_pct: int = int(round(float(ab.get("speed_mult_pct", 100.0))))
				var th_pct: int = int(round(float(ab.get("thrust_mult_pct", 160.0))))
				sp_pct = clampi(sp_pct, 0, 500)
				th_pct = clampi(th_pct, 0, 500)
				energy_afterburner_speed_multiplier = float(sp_pct) / 100.0
				energy_afterburner_multiplier = float(th_pct) / 100.0
			if abilities.has("stealth") and typeof(abilities.get("stealth")) == TYPE_DICTIONARY:
				var st: Dictionary = abilities.get("stealth")
				ability_stealth_drain_per_sec = maxi(0, int(round(float(st.get("drain_per_sec", 0.0)))))
			if abilities.has("cloak") and typeof(abilities.get("cloak")) == TYPE_DICTIONARY:
				var ck: Dictionary = abilities.get("cloak")
				ability_cloak_drain_per_sec = maxi(0, int(round(float(ck.get("drain_per_sec", 0.0)))))
			if abilities.has("xradar") and typeof(abilities.get("xradar")) == TYPE_DICTIONARY:
				var xr: Dictionary = abilities.get("xradar")
				ability_xradar_drain_per_sec = maxi(0, int(round(float(xr.get("drain_per_sec", 0.0)))))
			if abilities.has("antiwarp") and typeof(abilities.get("antiwarp")) == TYPE_DICTIONARY:
				var aw: Dictionary = abilities.get("antiwarp")
				ability_antiwarp_drain_per_sec = maxi(0, int(round(float(aw.get("drain_per_sec", 0.0)))))
				ability_antiwarp_radius_px = maxi(0, int(round(float(aw.get("radius_px", 0.0)))))

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

		# Legacy (schema v1): afterburner drain lives under energy.*
		if schema_version == 1:
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

	# Combat section (schema v2, optional).
	spawn_protect_ticks = 0
	respawn_delay_ticks = int((1500 * DriftConstants.TICK_RATE + 999) / 1000)
	combat_friendly_fire = false
	if schema_version >= 2:
		var combat: Dictionary = canonical_ruleset.get("combat", {})
		if typeof(combat) == TYPE_DICTIONARY and not combat.is_empty():
			if combat.has("spawn_protect_ms"):
				var ms = combat.get("spawn_protect_ms")
				if typeof(ms) in [TYPE_INT, TYPE_FLOAT]:
					var ms_i: int = maxi(0, int(round(float(ms))))
					spawn_protect_ticks = int((ms_i * DriftConstants.TICK_RATE + 999) / 1000)
			if combat.has("respawn_delay_ms"):
				var rms = combat.get("respawn_delay_ms")
				if typeof(rms) in [TYPE_INT, TYPE_FLOAT]:
					var rms_i: int = maxi(0, int(round(float(rms))))
					respawn_delay_ticks = int((rms_i * DriftConstants.TICK_RATE + 999) / 1000)
			if combat.has("friendly_fire"):
				combat_friendly_fire = bool(combat.get("friendly_fire"))

	# Team section (schema v2, optional).
	# Note: schema v1 has no team config; defaults apply.
	team_max_freq = 2
	team_force_even = true
	if schema_version >= 2:
		var team: Dictionary = canonical_ruleset.get("team", {})
		if typeof(team) == TYPE_DICTIONARY and not team.is_empty():
			if team.has("max_freq"):
				team_max_freq = clampi(int(team.get("max_freq")), 0, 16)
			if team.has("force_even"):
				team_force_even = bool(team.get("force_even"))
	team_max_freq = clampi(int(team_max_freq), 0, 16)


func _resolve_bullet_shrapnel_cfg_for_level(level: int) -> Dictionary:
	var out := {
		"count": bullet_shrapnel_count,
		"speed_mult": bullet_shrapnel_speed_mult,
		"lifetime_ticks": bullet_shrapnel_lifetime_ticks,
		"cone_deg": bullet_shrapnel_cone_deg,
	}
	var lvl: int = clampi(int(level), 1, 3)
	var rs_weapons: Dictionary = ruleset.get("weapons", {})
	if typeof(rs_weapons) != TYPE_DICTIONARY:
		return out
	if not rs_weapons.has("bullet") or typeof(rs_weapons.get("bullet")) != TYPE_DICTIONARY:
		return out
	var rs_bullet: Dictionary = rs_weapons.get("bullet")
	if not rs_bullet.has("levels") or typeof(rs_bullet.get("levels")) != TYPE_DICTIONARY:
		return out
	var levels: Dictionary = rs_bullet.get("levels")
	var key := str(lvl)
	if not levels.has(key) or typeof(levels.get(key)) != TYPE_DICTIONARY:
		return out
	var cfg: Dictionary = levels.get(key)
	if cfg.has("shrapnel_count"):
		out["count"] = int(cfg.get("shrapnel_count"))
	if cfg.has("shrapnel_speed_mult"):
		out["speed_mult"] = float(cfg.get("shrapnel_speed_mult"))
	if cfg.has("shrapnel_lifetime_s"):
		out["lifetime_ticks"] = int(round(float(cfg.get("shrapnel_lifetime_s")) / DriftConstants.TICK_DT))
	if cfg.has("shrapnel_cone_deg"):
		out["cone_deg"] = float(cfg.get("shrapnel_cone_deg"))

	out["count"] = clampi(int(out.get("count", 0)), 0, 16)
	out["speed_mult"] = clampf(float(out.get("speed_mult", 0.0)), 0.0, 2.0)
	out["lifetime_ticks"] = clampi(int(out.get("lifetime_ticks", 0)), 0, 600)
	out["cone_deg"] = clampf(float(out.get("cone_deg", 0.0)), 0.0, 360.0)
	return out


func _maybe_spawn_bullet_shrapnel(b: DriftTypes.DriftBulletState) -> void:
	# Shrapnel is level-based and stored on the bullet at fire-time.
	# To avoid recursion/infinite fragmentation, fragments are spawned as level 1 bullets.
	var cfg := _resolve_bullet_shrapnel_cfg_for_level(int(b.level))
	var count: int = int(cfg.get("count", 0))
	if count <= 0:
		return
	var lifetime_ticks: int = int(cfg.get("lifetime_ticks", 0))
	if lifetime_ticks <= 0:
		return
	var speed_mult: float = float(cfg.get("speed_mult", 0.0))
	if speed_mult <= 0.0:
		return
	var cone_deg: float = float(cfg.get("cone_deg", 0.0))

	var v := b.velocity
	var base_speed := v.length()
	if base_speed <= 0.001:
		base_speed = bullet_speed
	var frag_speed := base_speed * speed_mult
	frag_speed = clampf(frag_speed, 0.0, 5000.0)
	if frag_speed <= 0.001:
		return
	var base_ang := v.angle()

	for i in range(count):
		var t: float = 0.0
		if count > 1:
			t = (float(i) / float(count - 1)) * 2.0 - 1.0
		var ang := base_ang + deg_to_rad(t * (cone_deg * 0.5))
		var dir := Vector2(cos(ang), sin(ang))
		var vel := dir * frag_speed
		var die_tick := tick + lifetime_ticks
		var frag := DriftTypes.DriftBulletState.new(_next_bullet_id, int(b.owner_id), 1, b.position, vel, tick, die_tick, 0)
		bullets[_next_bullet_id] = frag
		_next_bullet_id += 1


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

	# Ability toggles (edge-detected in the deterministic sim).
	var prev_bits: int = int(_prev_ability_buttons_by_ship.get(int(ship_state.id), 0))
	var cur_bits: int = 0
	if bool(input_cmd.stealth_btn):
		cur_bits |= 1
	if bool(input_cmd.cloak_btn):
		cur_bits |= 2
	if bool(input_cmd.xradar_btn):
		cur_bits |= 4
	if bool(input_cmd.antiwarp_btn):
		cur_bits |= 8
	var pressed_bits: int = cur_bits & (~prev_bits)
	_prev_ability_buttons_by_ship[int(ship_state.id)] = cur_bits
	if (pressed_bits & 1) != 0:
		ship_state.stealth_on = not bool(ship_state.stealth_on)
	if (pressed_bits & 2) != 0:
		ship_state.cloak_on = not bool(ship_state.cloak_on)
	if (pressed_bits & 4) != 0:
		ship_state.xradar_on = not bool(ship_state.xradar_on)
	if (pressed_bits & 8) != 0:
		ship_state.antiwarp_on = not bool(ship_state.antiwarp_on)

	# Optional continuous drains: afterburner (hold) + toggled abilities.
	# Note: while any sustained drain is active, recharge must be blocked deterministically.
	var wants_afterburner: bool = bool(input_cmd.modifier) and float(input_cmd.thrust) > 0.0
	ship_state.afterburner_on = wants_afterburner and int(ship_state.energy_current) > 0 and int(energy_afterburner_drain_per_sec) > 0
	# If an ability has no configured drain, treat it as unavailable.
	if bool(ship_state.stealth_on) and int(ability_stealth_drain_per_sec) <= 0:
		ship_state.stealth_on = false
	if bool(ship_state.cloak_on) and int(ability_cloak_drain_per_sec) <= 0:
		ship_state.cloak_on = false
	if bool(ship_state.xradar_on) and int(ability_xradar_drain_per_sec) <= 0:
		ship_state.xradar_on = false
	if bool(ship_state.antiwarp_on) and int(ability_antiwarp_drain_per_sec) <= 0:
		ship_state.antiwarp_on = false

	var total_drain_per_sec: int = 0
	if bool(ship_state.afterburner_on):
		total_drain_per_sec += int(energy_afterburner_drain_per_sec)
	if bool(ship_state.stealth_on):
		total_drain_per_sec += int(ability_stealth_drain_per_sec)
	if bool(ship_state.cloak_on):
		total_drain_per_sec += int(ability_cloak_drain_per_sec)
	if bool(ship_state.xradar_on):
		total_drain_per_sec += int(ability_xradar_drain_per_sec)
	if bool(ship_state.antiwarp_on):
		total_drain_per_sec += int(ability_antiwarp_drain_per_sec)

	if total_drain_per_sec > 0 and int(ship_state.energy_current) <= 0:
		# Auto-disable abilities when energy is depleted.
		ship_state.afterburner_on = false
		ship_state.stealth_on = false
		ship_state.cloak_on = false
		ship_state.xradar_on = false
		ship_state.antiwarp_on = false
	elif total_drain_per_sec > 0 and int(ship_state.energy_current) > 0:
		# Block recharge while any sustained ability is active.
		ship_state.energy_recharge_wait_ticks = maxi(int(ship_state.energy_recharge_wait_ticks), int(ship_state.energy_recharge_delay_ticks))
		# Distribute per-second drain across ticks deterministically.
		ship_state.energy_drain_fp_accum += int(total_drain_per_sec)
		var drain_this_tick: int = int(ship_state.energy_drain_fp_accum) / DriftConstants.TICK_RATE
		ship_state.energy_drain_fp_accum = int(ship_state.energy_drain_fp_accum) % DriftConstants.TICK_RATE
		if drain_this_tick > 0:
			var ok_drain: bool = adjust_energy(int(ship_state.id), -drain_this_tick, EnergyReason.DRAIN_SUSTAINED, int(ship_state.id))
			if (not ok_drain) and int(ship_state.energy_current) <= 0:
				# Insufficient energy to sustain abilities: drain to 0 and force-disable.
				ship_state.afterburner_on = false
				ship_state.stealth_on = false
				ship_state.cloak_on = false
				ship_state.xradar_on = false
				ship_state.antiwarp_on = false
				ship_state.energy_drain_fp_accum = 0
			# If energy reaches 0, sustained abilities must shut off deterministically.
			if int(ship_state.energy_current) <= 0:
				ship_state.afterburner_on = false
				ship_state.stealth_on = false
				ship_state.cloak_on = false
				ship_state.xradar_on = false
				ship_state.antiwarp_on = false

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
			adjust_energy(int(ship_state.id), add_this_tick, EnergyReason.REGEN_BASE, -1)

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


func _spawn_prize_batch(player_count: int, now_tick: int) -> void:
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
		var despawn_tick := int(now_tick) + maxi(0, lifetime_ticks)

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
		var ps := DriftTypes.DriftPrizeState.new(pid, pos, int(now_tick), despawn_tick, kind, is_negative, false)
		prizes[pid] = ps
		_prize_bucket_add(pid, pos)


func spawn_death_prize_at(pos: Vector2, now_tick: int = -1) -> void:
	if not prize_enabled:
		return
	if death_prize_time_ticks <= 0:
		return
	if int(now_tick) < 0:
		now_tick = int(tick)
	var kind: int = _pick_weighted_prize_kind(false)
	if kind < 0:
		return
	var pid: int = prize_id_counter
	prize_id_counter += 1
	var despawn_tick := int(now_tick) + death_prize_time_ticks
	var ps := DriftTypes.DriftPrizeState.new(pid, pos, int(now_tick), despawn_tick, kind, false, true)
	prizes[pid] = ps
	_prize_bucket_add(pid, pos)


func _apply_prize_effect(ship_state: DriftTypes.DriftShipState, kind: int, is_negative: bool, now_tick: int) -> void:
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
				adjust_energy(int(ship_state.id), -amt, EnergyReason.PRIZE_NEGATIVE, -1)
			else:
				adjust_energy(int(ship_state.id), amt, EnergyReason.PRIZE_POSITIVE, -1)
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
				_apply_prize_effect(ship_state, sub_kind, false, now_tick)
		_:
			# Other prizes are currently stubs; must not crash.
			pass

	# Negative fallback: if negative prize would do nothing, apply EngineShutdown.
	if is_negative and not applied_effect:
		if engine_shutdown_time_ticks > 0:
			ship_state.engine_shutdown_until_tick = maxi(int(ship_state.engine_shutdown_until_tick), int(now_tick) + engine_shutdown_time_ticks)


func _process_prize_despawns(now_tick: int) -> void:
	if prizes.is_empty():
		return
	var ids: Array = prizes.keys()
	ids.sort()
	for pid in ids:
		var p: DriftTypes.DriftPrizeState = prizes.get(pid)
		if p == null:
			continue
		if int(p.despawn_tick) >= 0 and int(now_tick) >= int(p.despawn_tick):
			_prize_bucket_remove(int(p.id), p.pos)
			prizes.erase(pid)


func _process_prize_pickups(now_tick: int) -> void:
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
						_apply_prize_effect(s, int(p.kind), bool(p.is_negative), now_tick)
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


# Safe zones (deterministic, derived from map data).
var _safe_zone_tiles: Dictionary = {} # Dictionary[Vector2i, bool]
var _safe_zone_tile_list: Array = [] # Array[Vector2i]
var _safe_zone_tile_list_sorted: Array = [] # Array[Vector2i]


enum ActionType {
	FIRE_PRIMARY,
	FIRE_SECONDARY,
	BOMB,
	MINE,
	ABILITY,
	APPLY_DAMAGE,
}


enum EnergyReason {
	DAMAGE_BULLET,
	DAMAGE_BOMB,
	DAMAGE_MINE,
	DAMAGE_ENV,
	COST_FIRE_PRIMARY,
	COST_FIRE_SECONDARY,
	COST_ABILITY,
	DRAIN_CLOAK,
	DRAIN_AFTERBURNER,
	DRAIN_SUSTAINED,
	PRIZE_NEGATIVE,
	PRIZE_POSITIVE,
	REGEN_BASE,
}


func _energy_reason_is_cost(reason: int) -> bool:
	return int(reason) == EnergyReason.COST_FIRE_PRIMARY \
		or int(reason) == EnergyReason.COST_FIRE_SECONDARY \
		or int(reason) == EnergyReason.COST_ABILITY


func _energy_reason_is_drain(reason: int) -> bool:
	return int(reason) == EnergyReason.DRAIN_CLOAK \
		or int(reason) == EnergyReason.DRAIN_AFTERBURNER \
		or int(reason) == EnergyReason.DRAIN_SUSTAINED


func _damage_reason_for_source(source: Variant) -> int:
	# Keep this deterministic and permissive (unknown -> env).
	if typeof(source) == TYPE_STRING:
		var s: String = String(source)
		match s:
			"bullet":
				return EnergyReason.DAMAGE_BULLET
			"bomb":
				return EnergyReason.DAMAGE_BOMB
			"mine":
				return EnergyReason.DAMAGE_MINE
			"env", "environment":
				return EnergyReason.DAMAGE_ENV
	return EnergyReason.DAMAGE_ENV


func adjust_energy(ship_id: int, delta: int, reason: int, source_id: int = -1) -> bool:
	# Single authoritative energy mutation function.
	# delta: negative for loss, positive for gain.
	# Returns:
	# - false only for "all-or-nothing" cost reasons when insufficient energy.
	# - true otherwise (including clamped drains/damage).
	var sid: int = int(ship_id)
	if not ships.has(sid):
		return false
	var ship: DriftTypes.DriftShipState = ships.get(sid)
	if ship == null:
		return false

	var d: int = int(delta)
	if d == 0:
		return true

	var cur: int = int(ship.energy_current)
	var maxv: int = maxi(0, int(ship.energy_max))
	var next: int = cur + d
	var ok: bool = true

	if d < 0:
		var cost_amt: int = -d
		if _energy_reason_is_cost(reason):
			# All-or-nothing: rejected costs do not charge.
			if cur < cost_amt:
				return false
			next = cur - cost_amt
		elif _energy_reason_is_drain(reason):
			# Drains can partially deplete; signal failure when insufficient.
			if cur < cost_amt:
				ok = false
		else:
			# Drains/damage/prizes/etc: clamp.
			if next < 0:
				next = 0

		# Any loss event refreshes the recharge delay.
		ship.energy_recharge_wait_ticks = int(ship.energy_recharge_delay_ticks)
	else:
		# Gain: clamp to max.
		if next > maxv:
			next = maxv

	if next < 0:
		next = 0
	ship.energy_current = next
	ship.last_energy_change_reason = int(reason)
	ship.last_energy_change_source_id = int(source_id)
	ship.last_energy_change_tick = int(tick)
	# Keep legacy mirror updated.
	ship.energy = float(ship.energy_current)
	return ok


func _energy_reason_is_damage(reason: int) -> bool:
	return int(reason) == EnergyReason.DAMAGE_BULLET \
		or int(reason) == EnergyReason.DAMAGE_BOMB \
		or int(reason) == EnergyReason.DAMAGE_MINE \
		or int(reason) == EnergyReason.DAMAGE_ENV


func spend_energy(ship_id: int, cost: int, reason: int, action_type: int) -> bool:
	# Thin wrapper for action-linked costs.
	# Enforces: only charge when can_perform_action(...) accepts the action.
	var sid: int = int(ship_id)
	var c: int = maxi(0, int(cost))
	if c <= 0:
		return true
	if not ships.has(sid):
		return false
	var ship: DriftTypes.DriftShipState = ships.get(sid)
	if ship == null:
		return false
	var gate := can_perform_action(ship, int(action_type), {"tick": tick, "ship_id": sid})
	if not bool(gate.get("ok", true)):
		return false
	return adjust_energy(sid, -c, int(reason), sid)


func can_perform_action(ship_state: DriftTypes.DriftShipState, action_type: int, context: Dictionary = {}) -> Dictionary:
	# Single authoritative validation gate for player actions.
	# Returns a dict with at least:
	#   ok: bool
	# Optional:
	#   brake: bool (special safe-zone behavior for fire attempts while drifting)
	#   preserve_edge: bool (if false, action is considered "consumed")
	#
	# NOTE: This function should stay deterministic and depend only on replicated state.
	var ctx_tick: int = int(context.get("tick", tick))
	if _ship_is_dead(ship_state, ctx_tick):
		return {"ok": false, "preserve_edge": true}
	var in_safe: bool = bool(ship_state.in_safe_zone)
	if not in_safe:
		return {"ok": true}

	match int(action_type):
		ActionType.FIRE_PRIMARY:
			# Safe zones: reject firing. If attempting while drifting, brake.
			var speed: float = ship_state.velocity.length()
			var drifting: bool = speed > 0.5
			return {"ok": false, "brake": drifting, "preserve_edge": true}
		ActionType.FIRE_SECONDARY, ActionType.BOMB, ActionType.MINE, ActionType.ABILITY:
			# Safe zones: reject offensive actions and abilities.
			return {"ok": false, "preserve_edge": true}
		ActionType.APPLY_DAMAGE:
			# Safe zones: prevent any damage application.
			return {"ok": false}
		_:
			return {"ok": true}


func apply_damage(attacker_id: int, target_id: int, damage: int, source: Variant) -> bool:
	# Centralized damage application.
	# Determinism rules:
	# - No RNG
	# - Only depends on current tick + replicated state
	# Server-authoritative:
	# - Call from authoritative sim; clients may call during prediction but must match.
	var dmg: int = maxi(0, int(damage))
	if dmg <= 0:
		return false
	if not ships.has(target_id):
		return false
	var target: DriftTypes.DriftShipState = ships.get(target_id)
	if target == null:
		return false
	if _ship_is_dead(target, tick):
		return false

	# Safe zone immunity: no damage can be applied to ships in safe zones.
	# Also reject attempts originating from a ship in a safe zone.
	if bool(target.in_safe_zone):
		return false
	if ships.has(attacker_id):
		var attacker: DriftTypes.DriftShipState = ships.get(attacker_id)
		if attacker != null:
			if _ship_is_dead(attacker, tick):
				return false
			if bool(attacker.in_safe_zone):
				return false

	# Friendly-fire gate: if friendly_fire is disabled, same-freq damage is rejected.
	# In FFA mode (team_max_freq == 0), friendly-fire is effectively enabled to avoid
	# degenerate "all ships freq=0 -> no damage" behavior.
	if not _is_friendly_fire_enabled() and attacker_id != -1 and ships.has(attacker_id):
		var attacker2: DriftTypes.DriftShipState = ships.get(attacker_id)
		if attacker2 != null and int(attacker2.freq) == int(target.freq):
			return false

	# Spawn protection.
	if tick < int(target.damage_protect_until_tick):
		return false

	# Damage model placeholder: until a separate HP system exists, represent damage as energy loss.
	var reason: int = _damage_reason_for_source(source)
	var ok := adjust_energy(int(target_id), -dmg, reason, int(attacker_id))
	if ok and int(target.energy_current) <= 0 and _energy_reason_is_damage(reason):
		# Combat death is server-authoritative and only triggered via apply_damage.
		if int(target.dead_until_tick) <= 0 or tick >= int(target.dead_until_tick):
			target.dead_until_tick = maxi(0, tick + maxi(0, int(respawn_delay_ticks)))
			target.velocity = Vector2.ZERO
			target.afterburner_on = false
			target.stealth_on = false
			target.cloak_on = false
			target.xradar_on = false
			target.antiwarp_on = false
			_prev_fire_by_ship[target_id] = false
			_prev_ability_buttons_by_ship[target_id] = 0
	return ok


func _enforce_safe_zone_state(ship_state: DriftTypes.DriftShipState) -> void:
	# Safe zones allow movement only; enforce any stateful restrictions here.
	ship_state.afterburner_on = false
	ship_state.stealth_on = false
	ship_state.cloak_on = false
	ship_state.xradar_on = false
	ship_state.antiwarp_on = false
	ship_state.energy_drain_fp_accum = 0

# Spawning (server-auth): separate RNG stream from prizes.
var _spawn_rng := RandomNumberGenerator.new()

const SPAWN_ATTEMPTS: int = 128
const SAFE_SPAWN_ATTEMPTS: int = 96


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
	s.safe_zone_time_used_ticks = 0
	s.safe_zone_time_max_ticks = int(safe_zone_max_ticks)
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


func reset_ship_for_spawn(ship_id: int, position: Vector2) -> void:
	# Reset transient ship state after initial spawn or respawn.
	# (Does not change persistent upgrades/bounty; those are game-design dependent.)
	if not ships.has(ship_id):
		add_ship(ship_id, position)
		return
	var s: DriftTypes.DriftShipState = ships.get(ship_id)
	if s == null:
		add_ship(ship_id, position)
		return
	s.position = position
	s.velocity = Vector2.ZERO
	s.rotation = 0.0
	# Energy reset.
	s.energy_max = maxi(0, int(energy_max_points))
	s.energy_current = int(s.energy_max)
	s.energy_recharge_rate_per_sec = maxi(0, int(energy_recharge_rate_per_sec))
	s.energy_recharge_delay_ticks = maxi(0, int(energy_recharge_delay_ticks))
	s.energy_recharge_wait_ticks = 0
	s.energy_recharge_fp_accum = 0
	s.energy_drain_fp_accum = 0
	s.energy = float(s.energy_current)
	# Abilities off.
	s.afterburner_on = false
	s.stealth_on = false
	s.cloak_on = false
	s.xradar_on = false
	s.antiwarp_on = false
	# Engine shutdown cleared.
	s.engine_shutdown_until_tick = 0
	# Death/respawn cleared.
	s.dead_until_tick = 0
	# Safe-zone timer resets on spawn/respawn.
	s.safe_zone_time_used_ticks = 0
	s.safe_zone_time_max_ticks = int(safe_zone_max_ticks)
	s.last_energy_change_reason = 0
	s.last_energy_change_source_id = -1
	s.last_energy_change_tick = int(tick)
	# Spawn protection.
	s.damage_protect_until_tick = maxi(0, tick + maxi(0, int(spawn_protect_ticks)))
	# Safe-zone flag is derived from map state; set it immediately for authoritative replication.
	s.in_safe_zone = _is_position_in_safe_zone(s.position, DriftConstants.SHIP_RADIUS)


func drain_energy(ship: DriftTypes.DriftShipState, amount: int) -> bool:
	# Weapon-style drain: block if insufficient energy.
	var amt: int = maxi(0, int(amount))
	if amt <= 0:
		return true
	# Default legacy behavior: treat as primary-fire style cost.
	# Newer code should call spend_energy(...) with an explicit reason and action_type.
	return adjust_energy(int(ship.id), -amt, EnergyReason.COST_FIRE_PRIMARY, int(ship.id))


func add_energy(ship: DriftTypes.DriftShipState, amount: int) -> void:
	var amt: int = maxi(0, int(amount))
	if amt <= 0:
		return
	adjust_energy(int(ship.id), amt, EnergyReason.PRIZE_POSITIVE, -1)

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


func set_safe_zone_tiles(tiles: Array) -> void:
	"""Set safe zone tile positions from map data. tiles is Array of [x, y, atlas_x, atlas_y]"""
	_safe_zone_tiles.clear()
	_safe_zone_tile_list.clear()
	for tile_data in tiles:
		if tile_data.size() >= 2:
			var tile_pos := Vector2i(int(tile_data[0]), int(tile_data[1]))
			_safe_zone_tiles[tile_pos] = true
			_safe_zone_tile_list.append(tile_pos)
	_safe_zone_tile_list_sorted = _safe_zone_tile_list.duplicate(false)
	_sort_tiles_in_place(_safe_zone_tile_list_sorted)


func set_spawn_rng_seed(seed_value: int) -> void:
	_spawn_rng.seed = int(seed_value)


func _sort_tiles_in_place(tiles: Array) -> void:
	# Stable, deterministic ordering for fallback scans.
	# Sort by y then x.
	if tiles.size() <= 1:
		return
	tiles.sort_custom(Callable(self, "_tile_sort_lt"))


func _tile_sort_lt(a: Variant, b: Variant) -> bool:
	if not (a is Vector2i) or not (b is Vector2i):
		return false
	var ta := a as Vector2i
	var tb := b as Vector2i
	if ta.y == tb.y:
		return ta.x < tb.x
	return ta.y < tb.y


func is_valid_spawn_point(pos: Vector2) -> bool:
	var r: float = float(DriftConstants.SHIP_RADIUS)
	if map_w_tiles > 0 and map_h_tiles > 0:
		var w_px: float = float(map_w_tiles) * float(TILE_SIZE)
		var h_px: float = float(map_h_tiles) * float(TILE_SIZE)
		if pos.x < r or pos.y < r or pos.x > (w_px - r) or pos.y > (h_px - r):
			return false
	if is_position_blocked(pos, r):
		return false
	return true


func _random_point_in_tile(tile: Vector2i, radius: float) -> Vector2:
	# Prefer staying away from tile edges so ship radius doesn't straddle solids.
	var min_x: float = float(tile.x) * float(TILE_SIZE)
	var min_y: float = float(tile.y) * float(TILE_SIZE)
	var max_x: float = min_x + float(TILE_SIZE)
	var max_y: float = min_y + float(TILE_SIZE)
	var inset: float = minf(float(TILE_SIZE) * 0.45, radius + 0.5)
	var x0: float = min_x + inset
	var x1: float = max_x - inset
	var y0: float = min_y + inset
	var y1: float = max_y - inset
	if x1 <= x0 or y1 <= y0:
		return _world_pos_for_tile(tile)
	return Vector2(_spawn_rng.randf_range(x0, x1), _spawn_rng.randf_range(y0, y1))


func get_safe_spawn_point() -> Variant:
	# Returns Vector2 on success, or null if no safe zones or none valid.
	if _safe_zone_tile_list.is_empty():
		return null
	var r: float = float(DriftConstants.SHIP_RADIUS)
	for _attempt in range(SAFE_SPAWN_ATTEMPTS):
		var idx: int = _spawn_rng.randi_range(0, _safe_zone_tile_list.size() - 1)
		var t: Vector2i = _safe_zone_tile_list[idx]
		# Try center, then a jittered point.
		var p0 := _world_pos_for_tile(t)
		if is_valid_spawn_point(p0):
			return p0
		var p1 := _random_point_in_tile(t, r)
		if is_valid_spawn_point(p1):
			return p1

	# Fallback: deterministic scan for the first valid safe tile.
	for t2 in _safe_zone_tile_list_sorted:
		if not (t2 is Vector2i):
			continue
		var p2 := _world_pos_for_tile(t2)
		if is_valid_spawn_point(p2):
			return p2
	return null


func get_random_valid_spawn_point() -> Vector2:
	# Random valid location in playable field/bounds.
	# Prefer the main walkable component if available.
	var r: float = float(DriftConstants.SHIP_RADIUS)
	if not _main_walkable_tiles.is_empty():
		for _attempt in range(SPAWN_ATTEMPTS):
			var idx: int = _spawn_rng.randi_range(0, _main_walkable_tiles.size() - 1)
			var t: Vector2i = _main_walkable_tiles[idx]
			var p := _random_point_in_tile(t, r)
			if is_valid_spawn_point(p):
				return p
		# Fallback scan: first valid tile.
		for t2 in _main_walkable_tiles:
			if not (t2 is Vector2i):
				continue
			var p2 := _world_pos_for_tile(t2)
			if is_valid_spawn_point(p2):
				return p2

	# If we don't have walkables (e.g., map dimensions missing), sample within bounds.
	if map_w_tiles > 0 and map_h_tiles > 0:
		var w_px: float = float(map_w_tiles) * float(TILE_SIZE)
		var h_px: float = float(map_h_tiles) * float(TILE_SIZE)
		for _attempt2 in range(SPAWN_ATTEMPTS):
			var p3 := Vector2(_spawn_rng.randf_range(r, w_px - r), _spawn_rng.randf_range(r, h_px - r))
			if is_valid_spawn_point(p3):
				return p3

	# Deterministic last-resort fallback.
	var center := _world_pos_for_tile(_center_tile())
	if is_valid_spawn_point(center):
		return center
	# Scan whole map for first non-solid tile.
	if map_w_tiles > 0 and map_h_tiles > 0:
		for y in range(map_h_tiles):
			for x in range(map_w_tiles):
				var t := Vector2i(x, y)
				if _static_solid_tiles.has(t):
					continue
				var p4 := _world_pos_for_tile(t)
				if is_valid_spawn_point(p4):
					return p4
	return DriftConstants.ARENA_CENTER


func get_spawn_point() -> Vector2:
	# Safe-zone-first spawn selection.
	var safe = get_safe_spawn_point()
	if safe is Vector2:
		return safe
	return get_random_valid_spawn_point()


func get_non_safe_spawn_point() -> Variant:
	# Returns Vector2 on success, or null if no non-safe valid spawn exists.
	# Deterministic selection: uses spawn RNG for attempts and stable scans for fallback.
	# If no safe zones exist, any valid spawn is considered non-safe.
	if _safe_zone_tiles.is_empty():
		return get_random_valid_spawn_point()
	var r: float = float(DriftConstants.SHIP_RADIUS)

	# Prefer main walkable tiles when available.
	if not _main_walkable_tiles.is_empty():
		for _attempt in range(SPAWN_ATTEMPTS):
			var idx: int = _spawn_rng.randi_range(0, _main_walkable_tiles.size() - 1)
			var t: Vector2i = _main_walkable_tiles[idx]
			# Quick reject tiles explicitly marked safe.
			if _safe_zone_tiles.has(t):
				continue
			var p := _random_point_in_tile(t, r)
			if is_valid_spawn_point(p) and not _is_position_in_safe_zone(p, r):
				return p
		# Fallback scan: first valid walkable tile that is not safe.
		for t2 in _main_walkable_tiles:
			if not (t2 is Vector2i):
				continue
			if _safe_zone_tiles.has(t2):
				continue
			var p2 := _world_pos_for_tile(t2)
			if is_valid_spawn_point(p2) and not _is_position_in_safe_zone(p2, r):
				return p2

	# If we don't have walkables (or none suitable), sample within bounds.
	if map_w_tiles > 0 and map_h_tiles > 0:
		var w_px: float = float(map_w_tiles) * float(TILE_SIZE)
		var h_px: float = float(map_h_tiles) * float(TILE_SIZE)
		for _attempt2 in range(SPAWN_ATTEMPTS):
			var p3 := Vector2(_spawn_rng.randf_range(r, w_px - r), _spawn_rng.randf_range(r, h_px - r))
			if is_valid_spawn_point(p3) and not _is_position_in_safe_zone(p3, r):
				return p3

	# Deterministic last-resort fallback scan.
	if map_w_tiles > 0 and map_h_tiles > 0:
		for y in range(map_h_tiles):
			for x in range(map_w_tiles):
				var t3 := Vector2i(x, y)
				if _static_solid_tiles.has(t3):
					continue
				if _safe_zone_tiles.has(t3):
					continue
				var p4 := _world_pos_for_tile(t3)
				if is_valid_spawn_point(p4) and not _is_position_in_safe_zone(p4, r):
					return p4
	return null


func respawn_ship_non_safe(ship_id: int) -> void:
	var spawn = get_non_safe_spawn_point()
	if spawn is Vector2:
		reset_ship_for_spawn(ship_id, spawn)
		_assign_freq_on_spawn(ship_id)
		return
	# If no non-safe spawn exists, fall back to normal spawn behavior.
	respawn_ship(ship_id)


func respawn_ship(ship_id: int) -> void:
	# Authoritative respawn primitive: choose spawn point and reset ship state.
	# Actual death detection/triggering is owned by the server/game rules.
	var spawn = get_spawn_point()
	reset_ship_for_spawn(ship_id, spawn)
	_assign_freq_on_spawn(ship_id)


func _is_friendly_fire_enabled() -> bool:
	# Effective friendly-fire behavior.
	# If team_max_freq == 0, the game is in FFA mode and must allow damage.
	return bool(combat_friendly_fire) or int(team_max_freq) == 0


func _assign_freq_on_spawn(ship_id: int) -> void:
	# Deterministic team assignment. Intended to be called by the authoritative server
	# on join and on respawn.
	if not ships.has(ship_id):
		return
	var s: DriftTypes.DriftShipState = ships.get(ship_id)
	if s == null:
		return
	if int(team_max_freq) <= 0:
		s.freq = 0
		return
	s.freq = _choose_balanced_freq_for_ship(ship_id)


func _choose_balanced_freq_for_ship(ship_id: int) -> int:
	var maxf: int = clampi(int(team_max_freq), 1, 16)
	var counts: Array[int] = []
	counts.resize(maxf)
	for i in range(maxf):
		counts[i] = 0

	# Determinism: stable iteration order by ship_id.
	var ids: Array[int] = []
	for k in ships.keys():
		ids.append(int(k))
	ids.sort()
	for sid in ids:
		var other_id: int = int(sid)
		if other_id == int(ship_id):
			continue
		var other: DriftTypes.DriftShipState = ships.get(other_id)
		if other == null:
			continue
		if _ship_is_dead(other, tick):
			continue
		var f: int = int(other.freq)
		if f < 0 or f >= maxf:
			continue
		counts[f] += 1

	# Choose the freq with the fewest active non-dead ships (tie-break lowest freq).
	var best_freq: int = 0
	var best_count: int = counts[0]
	for f2 in range(1, maxf):
		var c: int = int(counts[f2])
		if c < best_count:
			best_count = c
			best_freq = f2
	return best_freq


func can_set_ship_freq(ship_id: int, desired_freq: int) -> Dictionary:
	# Server helper for manual team changes.
	# Deterministic: depends only on world state.
	if not ships.has(ship_id):
		return {"ok": false, "error": "ship not found", "reason": 4}
	var s: DriftTypes.DriftShipState = ships.get(ship_id)
	if s == null:
		return {"ok": false, "error": "ship not found", "reason": 4}
	if _ship_is_dead(s, tick):
		return {"ok": false, "error": "ship is dead", "reason": 4}

	var maxf: int = int(team_max_freq)
	var df: int = int(desired_freq)
	if maxf <= 0:
		if df != 0:
			return {"ok": false, "error": "FFA mode only allows freq 0", "reason": 1}
		return {"ok": true, "reason": 0}
	if df < 0 or df >= maxf:
		return {"ok": false, "error": "desired_freq out of bounds", "reason": 1}
	if int(s.freq) == df:
		return {"ok": true, "reason": 0}

	if not bool(team_force_even):
		return {"ok": true, "reason": 0}

	# Enforce even teams: after the change, variance between max/min team counts must be <= 1.
	var counts: Array[int] = []
	counts.resize(maxf)
	for i in range(maxf):
		counts[i] = 0

	var ids: Array[int] = []
	for k in ships.keys():
		ids.append(int(k))
	ids.sort()
	for sid in ids:
		var other_id: int = int(sid)
		var other: DriftTypes.DriftShipState = ships.get(other_id)
		if other == null:
			continue
		if _ship_is_dead(other, tick):
			continue
		var f0: int = int(other.freq)
		if f0 < 0 or f0 >= maxf:
			continue
		counts[f0] += 1

	# Apply proposed move for this ship.
	var cur: int = int(s.freq)
	if cur >= 0 and cur < maxf:
		counts[cur] = maxi(0, int(counts[cur]) - 1)
	counts[df] += 1

	var min_c: int = counts[0]
	var max_c: int = counts[0]
	for f1 in range(1, maxf):
		min_c = mini(min_c, int(counts[f1]))
		max_c = maxi(max_c, int(counts[f1]))
	if (max_c - min_c) > 1:
		return {"ok": false, "error": "team balance constraint", "reason": 2}
	return {"ok": true, "reason": 0}


func set_ship_freq(ship_id: int, desired_freq: int) -> Dictionary:
	var res := can_set_ship_freq(ship_id, desired_freq)
	if not bool(res.get("ok", false)):
		return res
	if not ships.has(ship_id):
		return {"ok": false, "error": "ship not found", "reason": 4}
	var s: DriftTypes.DriftShipState = ships.get(ship_id)
	if s == null:
		return {"ok": false, "error": "ship not found", "reason": 4}
	var maxf: int = int(team_max_freq)
	if maxf <= 0:
		s.freq = 0
	else:
		s.freq = clampi(int(desired_freq), 0, maxf - 1)
	return {"ok": true, "reason": 0}


func _is_position_in_safe_zone(pos: Vector2, radius: float) -> bool:
	# Circle-rect overlap against any safe-zone tile intersecting the ship's radius.
	if _safe_zone_tiles.is_empty():
		return false
	var min_tile_x := int(floor((pos.x - radius) / TILE_SIZE))
	var max_tile_x := int(floor((pos.x + radius) / TILE_SIZE))
	var min_tile_y := int(floor((pos.y - radius) / TILE_SIZE))
	var max_tile_y := int(floor((pos.y + radius) / TILE_SIZE))
	for tx in range(min_tile_x, max_tile_x + 1):
		for ty in range(min_tile_y, max_tile_y + 1):
			var tile_coord := Vector2i(tx, ty)
			if not _safe_zone_tiles.has(tile_coord):
				continue
			var tile_rect_min := Vector2(tx * TILE_SIZE, ty * TILE_SIZE)
			var tile_rect_max := tile_rect_min + Vector2(TILE_SIZE, TILE_SIZE)
			var closest_x := clampf(pos.x, tile_rect_min.x, tile_rect_max.x)
			var closest_y := clampf(pos.y, tile_rect_min.y, tile_rect_max.y)
			var closest := Vector2(closest_x, closest_y)
			if pos.distance_to(closest) < radius:
				return true
	return false


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


func _update_doors_for_tick(tick_value: int) -> void:
	if _door_tile_cells.is_empty():
		return
	var d := get_door_anim_for_tick(tick_value)
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
	# Tick contract (vNext):
	# - `tick` is the tick being simulated at the start of this call (t).
	# - This function applies inputs for `t`.
	# - At the end, it advances `tick` to `t_next = t + 1` and returns a snapshot
	#   representing the post-step state with snapshot.tick == world.tick.
	var t: int = int(tick)
	var t_next: int = int(tick) + 1

	_update_doors_for_tick(t)
	# Clear transient events each tick.
	collision_events.clear()
	prize_events.clear()

	# Stable update order for determinism.
	var ship_ids: Array = ships.keys()
	ship_ids.sort()

	# Automatic respawn for combat deaths.
	for ship_id in ship_ids:
		var rs: DriftTypes.DriftShipState = ships.get(ship_id)
		if rs == null:
			continue
		if int(rs.dead_until_tick) > 0 and t >= int(rs.dead_until_tick):
			respawn_ship(int(ship_id))

	# Dead owners cannot carry the ball.
	if ball.owner_id != -1 and ships.has(ball.owner_id):
		var bo: DriftTypes.DriftShipState = ships.get(ball.owner_id)
		if bo != null and _ship_is_dead(bo, t):
			ball.owner_id = -1

	# Sanitized per-ship action inputs for this tick (weapons/abilities).
	# Movement is processed separately so safe zones still allow movement.
	var action_cmds: Dictionary = {} # Dictionary[int, DriftTypes.DriftInputCmd]


	for ship_id in ship_ids:
		var ship_state: DriftTypes.DriftShipState = ships[ship_id]
		var input_cmd: DriftTypes.DriftInputCmd = inputs.get(ship_id, DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false))

		# Dead ships are non-interactive: no movement, no actions, no energy steps.
		if _ship_is_dead(ship_state, t):
			ship_state.velocity = Vector2.ZERO
			action_cmds[ship_id] = DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false)
			continue

		# Safe zone detection.
		ship_state.in_safe_zone = _is_position_in_safe_zone(ship_state.position, DriftConstants.SHIP_RADIUS)

		# Safe-zone time limit (server authoritative, deterministic).
		# Accumulates only while alive and in safe zone; resets on spawn/respawn.
		if int(safe_zone_max_ticks) > 0 and bool(ship_state.in_safe_zone):
			ship_state.safe_zone_time_used_ticks = maxi(0, int(ship_state.safe_zone_time_used_ticks) + 1)
			ship_state.safe_zone_time_max_ticks = int(safe_zone_max_ticks)
			if int(ship_state.safe_zone_time_used_ticks) >= int(safe_zone_max_ticks):
				respawn_ship_non_safe(int(ship_id))
				action_cmds[ship_id] = DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false)
				continue
		else:
			# Keep max in sync for replication.
			ship_state.safe_zone_time_max_ticks = int(safe_zone_max_ticks)

		# Build action command through the single validation gate.
		var action_cmd: DriftTypes.DriftInputCmd = input_cmd
		var move_cmd: DriftTypes.DriftInputCmd = input_cmd
		var energy_cmd: DriftTypes.DriftInputCmd = input_cmd
		if bool(ship_state.in_safe_zone):
			_enforce_safe_zone_state(ship_state)

			# Abilities rejected in safe zone.
			var abil_v := can_perform_action(ship_state, ActionType.ABILITY, {"tick": t, "ship_id": ship_id})
			if not bool(abil_v.get("ok", true)):
				action_cmd = DriftTypes.DriftInputCmd.new(
					action_cmd.thrust,
					action_cmd.rotation,
					bool(action_cmd.fire_primary),
					bool(action_cmd.fire_secondary),
					false,
					false,
					false,
					false,
					false
				)
				energy_cmd = DriftTypes.DriftInputCmd.new(
					energy_cmd.thrust,
					energy_cmd.rotation,
					bool(energy_cmd.fire_primary),
					bool(energy_cmd.fire_secondary),
					false,
					false,
					false,
					false,
					false
				)

			# Fire primary rejected in safe zone; may trigger braking if drifting.
			if bool(action_cmd.fire_primary):
				var fire_v := can_perform_action(ship_state, ActionType.FIRE_PRIMARY, {"tick": tick, "ship_id": ship_id})
				if not bool(fire_v.get("ok", true)):
					if bool(fire_v.get("brake", false)):
						ship_state.velocity = Vector2.ZERO
						move_cmd = DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false)
					# Do not let the action propagate to ball/bullets.
					action_cmd = DriftTypes.DriftInputCmd.new(
						action_cmd.thrust,
						action_cmd.rotation,
						false,
						bool(action_cmd.fire_secondary),
						bool(action_cmd.modifier),
						bool(action_cmd.stealth_btn),
						bool(action_cmd.cloak_btn),
						bool(action_cmd.xradar_btn),
						bool(action_cmd.antiwarp_btn)
					)

			# Fire secondary rejected in safe zone (bomb/mine placeholders).
			if bool(action_cmd.fire_secondary):
				var sec_v := can_perform_action(ship_state, ActionType.FIRE_SECONDARY, {"tick": tick, "ship_id": ship_id})
				if not bool(sec_v.get("ok", true)):
					action_cmd = DriftTypes.DriftInputCmd.new(
						action_cmd.thrust,
						action_cmd.rotation,
						bool(action_cmd.fire_primary),
						false,
						bool(action_cmd.modifier),
						bool(action_cmd.stealth_btn),
						bool(action_cmd.cloak_btn),
						bool(action_cmd.xradar_btn),
						bool(action_cmd.antiwarp_btn)
					)

		# Store sanitized action command.
		action_cmds[ship_id] = action_cmd

		_step_ship_energy(ship_state, energy_cmd)
		# Engine shutdown (negative prize effect): thrust/rotation disabled, firing allowed.
		if int(ship_state.engine_shutdown_until_tick) > 0 and tick < int(ship_state.engine_shutdown_until_tick):
			move_cmd = DriftTypes.DriftInputCmd.new(0.0, 0.0, bool(move_cmd.fire_primary), bool(move_cmd.fire_secondary), bool(move_cmd.modifier))
		
		# Store position before movement
		var old_position := ship_state.position
		
		DriftShip.apply_input(
			ship_state,
			move_cmd,
			DriftConstants.TICK_DT,
			ship_turn_rate,
			_ship_effective_thrust_accel(ship_state, move_cmd),
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
			if _ship_is_dead(ship, tick):
				continue
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
				if _ship_is_dead(other, tick):
					continue
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

	# Kick on fire (uses validated action commands).
	var kicked_ship_id: int = -1
	if ball.owner_id != -1 and action_cmds.has(ball.owner_id) and (action_cmds[ball.owner_id] as DriftTypes.DriftInputCmd).fire_primary:
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
		if not action_cmds.has(ship_id):
			continue
		var cmd: DriftTypes.DriftInputCmd = action_cmds[ship_id]
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
		var eff_cooldown_ticks: int = bullet_cooldown_ticks
		var eff_spread_deg: float = bullet_spread_deg

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
							eff_cooldown_ticks = int(level_cfg.get("cooldown_ticks", eff_cooldown_ticks))
							eff_spread_deg = float(level_cfg.get("spread_deg", eff_spread_deg))
							eff_muzzle_offset = float(level_cfg.get("muzzle_offset", eff_muzzle_offset))
							eff_bounces = int(level_cfg.get("bounces", eff_bounces))
							eff_bounce_restitution = float(level_cfg.get("bounce_restitution", eff_bounce_restitution))
							if level_cfg.has("lifetime_s"):
								eff_lifetime_ticks = int(round(float(level_cfg.get("lifetime_s")) / DriftConstants.TICK_DT))

						guns = int(sb.get("guns", guns))
						multi_fire = bool(sb.get("multi_fire", multi_fire))
						eff_speed = float(sb.get("speed", eff_speed))
						eff_cooldown_ticks = int(sb.get("cooldown_ticks", eff_cooldown_ticks))
						eff_spread_deg = float(sb.get("spread_deg", eff_spread_deg))
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
		eff_cooldown_ticks = clampi(eff_cooldown_ticks, 0, 120)
		eff_spread_deg = clampf(eff_spread_deg, 0.0, 45.0)

		# Level-based cooldown gate (no extra replicated weapon state needed).
		if eff_cooldown_ticks > 0 and int(posmod(tick + ship_id, eff_cooldown_ticks)) != 0:
			continue
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
		if cost > 0 and not spend_energy(ship_id, cost, EnergyReason.COST_FIRE_PRIMARY, ActionType.FIRE_PRIMARY):
			continue

		for gi in fire_guns:
			var centered := float(gi) - (float(guns - 1) * 0.5)
			var lateral := centered * bullet_gun_spacing
			var ang_off := deg_to_rad(centered * eff_spread_deg)
			var shot_dir := fwd.rotated(ang_off)
			var shot_right := Vector2(-shot_dir.y, shot_dir.x)
			var spawn_pos := ship_state.position + shot_dir * eff_muzzle_offset + shot_right * lateral
			var vel := ship_state.velocity + shot_dir * eff_speed
			var die_tick := tick + maxi(0, eff_lifetime_ticks)
			var bstate := DriftTypes.DriftBulletState.new(_next_bullet_id, ship_id, eff_level, spawn_pos, vel, tick, die_tick, eff_bounces)
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
			_maybe_spawn_bullet_shrapnel(b)
			to_remove.append(int(bid))
			continue
		var next_pos := b.position + b.velocity * DriftConstants.TICK_DT
		# Arena bounds check.
		if next_pos.x < DriftConstants.ARENA_MIN.x or next_pos.x > DriftConstants.ARENA_MAX.x or next_pos.y < DriftConstants.ARENA_MIN.y or next_pos.y > DriftConstants.ARENA_MAX.y:
			_maybe_spawn_bullet_shrapnel(b)
			to_remove.append(int(bid))
			continue
		# Tile collision check (treat bullets as small circles).
		if is_position_blocked(next_pos, bullet_radius):
			if int(b.bounces_left) <= 0:
				_maybe_spawn_bullet_shrapnel(b)
				to_remove.append(int(bid))
				continue
			var n: Vector2 = get_collision_normal(b.position, next_pos, bullet_radius)
			if n == Vector2.ZERO:
				_maybe_spawn_bullet_shrapnel(b)
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
			# Keep a tiny gap so the bullet doesn't remain in-contact and jitter.
			# n is the collision normal pointing out of the wall.
			b.position = contact_pos + n * SEPARATION_EPSILON
			if is_position_blocked(b.position, bullet_radius):
				_maybe_spawn_bullet_shrapnel(b)
				to_remove.append(int(bid))
				continue
			# Reflect velocity with optional restitution.
			var vdotn: float = b.velocity.dot(n)
			if vdotn < 0.0:
				var v_t: Vector2 = b.velocity - n * vdotn
				var normal_speed: float = -vdotn
				var restitution: float = _resolve_bullet_bounce_restitution_for_bullet(int(b.owner_id), int(b.level))
				b.velocity = v_t + n * (normal_speed * restitution)
			b.bounces_left = int(b.bounces_left) - 1
			continue
		b.position = next_pos

	for bid in to_remove:
		bullets.erase(bid)

	# Server-only prize simulation (authoritative). Must not run in client prediction.
	# Note: prize timing historically used the incremented tick value.
	# Under the new tick contract, run prize scheduling against t_next.
	if include_prizes and prize_enabled:
		var prize_tick: int = int(t_next)
		_process_prize_despawns(prize_tick)
		_process_prize_pickups(prize_tick)
		if prize_tick >= next_prize_spawn_tick:
			_spawn_prize_batch(player_count_for_prizes, prize_tick)
			var dt: int = _prize_spawn_delay_for_players(player_count_for_prizes)
			next_prize_spawn_tick = prize_tick + dt

	# Advance tick at the end of the step.
	tick = t_next

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
		snapshot_bullets.append(DriftTypes.DriftBulletState.new(b.id, b.owner_id, b.level, b.position, b.velocity, b.spawn_tick, b.die_tick, b.bounces_left))

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
	var base: float = ship_max_speed * (1.0 + TOP_SPEED_BONUS_PCT * float(bonus))
	if bool(ship_state.afterburner_on):
		return base * energy_afterburner_speed_multiplier
	return base


func _ship_effective_reverse_accel(_ship_state: DriftTypes.DriftShipState) -> float:
	# Thruster affects forward thrust only; keep reverse stable.
	return ship_reverse_accel


func _ship_effective_thrust_accel(ship_state: DriftTypes.DriftShipState, input_cmd: DriftTypes.DriftInputCmd) -> float:
	var thrust_bonus: int = int(ship_state.thruster_bonus)
	var base: float = ship_thrust_accel * (1.0 + THRUSTER_BONUS_PCT * float(thrust_bonus))
	if bool(ship_state.afterburner_on):
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
		source.energy_drain_fp_accum,
		source.afterburner_on,
		source.stealth_on,
		source.cloak_on,
		source.xradar_on,
		source.antiwarp_on,
		source.in_safe_zone,
		source.damage_protect_until_tick,
		source.dead_until_tick,
		source.last_energy_change_reason,
		source.last_energy_change_source_id,
		source.last_energy_change_tick
	)
