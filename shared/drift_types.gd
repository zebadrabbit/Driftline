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
	# Ability buttons (client reports current button-down; sim performs edge detection).
	var stealth_btn: bool
	var cloak_btn: bool
	var xradar_btn: bool
	var antiwarp_btn: bool

	func _init(
		thrust_value: float = 0.0,
		rotation_value: float = 0.0,
		fire_primary_value: bool = false,
		fire_secondary_value: bool = false,
		modifier_value: bool = false,
		stealth_btn_value: bool = false,
		cloak_btn_value: bool = false,
		xradar_btn_value: bool = false,
		antiwarp_btn_value: bool = false
	) -> void:
		thrust = clampf(float(thrust_value), -1.0, 1.0)
		rotation = clampf(float(rotation_value), -1.0, 1.0)
		fire_primary = bool(fire_primary_value)
		fire_secondary = bool(fire_secondary_value)
		modifier = bool(modifier_value)
		stealth_btn = bool(stealth_btn_value)
		cloak_btn = bool(cloak_btn_value)
		xradar_btn = bool(xradar_btn_value)
		antiwarp_btn = bool(antiwarp_btn_value)



class DriftShipState:
	var id: int
	var position: Vector2
	var velocity: Vector2
	var rotation: float
	# Team / frequency. 0 means unassigned / neutral.
	var freq: int = 0
	var username: String = ""
	var bounty: int = 0

	# Safe-zone time limit tracking (deterministic; server authoritative).
	# - safe_zone_time_used_ticks accumulates only while alive and in safe zone.
	# - safe_zone_time_max_ticks is the configured cap in ticks (0 disables).
	var safe_zone_time_used_ticks: int = 0
	var safe_zone_time_max_ticks: int = 0

	# Death/respawn (server-authoritative, replicated via snapshots).
	# If world.tick < dead_until_tick, the ship is considered dead and non-interactive.
	var dead_until_tick: int = 0

	# Last energy mutation provenance (debug/authoritative semantics).
	# Used to distinguish combat damage from voluntary spending.
	var last_energy_change_reason: int = 0
	var last_energy_change_source_id: int = -1
	var last_energy_change_tick: int = 0

	# Combat / damage protection.
	# Deterministic tick timestamp; damage is ignored while world.tick < damage_protect_until_tick.
	var damage_protect_until_tick: int = 0
	# Prizes/upgrades (server authoritative, replicated via snapshots).
	var gun_level: int = 1
	var bomb_level: int = 1
	var multi_fire_enabled: bool = false
	var bullet_bounce_bonus: int = 0
	var engine_shutdown_until_tick: int = 0
	var top_speed_bonus: int = 0
	var thruster_bonus: int = 0
	var recharge_bonus: int = 0

	# Deterministic energy system (tick-based).
	# Units:
	# - energy_current/energy_max: integer energy points.
	# - energy_recharge_rate_per_sec: integer points per second.
	# - energy_recharge_wait_ticks: countdown until recharge begins.
	# - energy_recharge_fp_accum: remainder accumulator in "points per tick" space (see DriftWorld).
	# - energy_drain_fp_accum: remainder accumulator for continuous drains (e.g., afterburner).
	var energy_current: int = 0
	var energy_max: int = 0
	var energy_recharge_rate_per_sec: int = 0
	var energy_recharge_delay_ticks: int = 0
	var energy_recharge_wait_ticks: int = 0
	var energy_recharge_fp_accum: int = 0
	var energy_drain_fp_accum: int = 0

	# Continuous-drain abilities (replicated via snapshots).
	# - afterburner_on is a hold ability (typically modifier + forward thrust)
	# - others are toggles (edge-detected in the deterministic sim)
	var afterburner_on: bool = false
	var stealth_on: bool = false
	var cloak_on: bool = false
	var xradar_on: bool = false
	var antiwarp_on: bool = false

	# Safe zone state (deterministic, derived from map data).
	var in_safe_zone: bool = false

	# Legacy field kept for backward compatibility with older UI/debug.
	# New code should prefer energy_current/energy_max.
	var energy: float = 100.0

	func _init(
		ship_id: int,
		position_value: Vector2,
		velocity_value: Vector2 = Vector2.ZERO,
		rotation_value: float = 0.0,
		username_value: String = "",
		bounty_value: int = 0,
		gun_level_value: int = 1,
		bomb_level_value: int = 1,
		multi_fire_enabled_value: bool = false,
		bullet_bounce_bonus_value: int = 0,
		engine_shutdown_until_tick_value: int = 0,
		top_speed_bonus_value: int = 0,
		thruster_bonus_value: int = 0,
		recharge_bonus_value: int = 0,
		energy_value: float = 100.0,
		energy_current_value: int = 0,
		energy_max_value: int = 0,
		energy_recharge_rate_per_sec_value: int = 0,
		energy_recharge_delay_ticks_value: int = 0,
		energy_recharge_wait_ticks_value: int = 0,
		energy_recharge_fp_accum_value: int = 0,
		energy_drain_fp_accum_value: int = 0,
		afterburner_on_value: bool = false,
		stealth_on_value: bool = false,
		cloak_on_value: bool = false,
		xradar_on_value: bool = false,
		antiwarp_on_value: bool = false,
		in_safe_zone_value: bool = false,
		damage_protect_until_tick_value: int = 0,
		dead_until_tick_value: int = 0,
		last_energy_change_reason_value: int = 0,
		last_energy_change_source_id_value: int = -1,
		last_energy_change_tick_value: int = 0,
		freq_value: int = 0
	) -> void:
		id = ship_id
		position = position_value
		velocity = velocity_value
		rotation = rotation_value
		freq = int(freq_value)
		safe_zone_time_used_ticks = 0
		safe_zone_time_max_ticks = 0
		username = username_value
		bounty = bounty_value
		gun_level = clampi(int(gun_level_value), 1, 3)
		bomb_level = clampi(int(bomb_level_value), 1, 3)
		multi_fire_enabled = bool(multi_fire_enabled_value)
		bullet_bounce_bonus = clampi(int(bullet_bounce_bonus_value), 0, 16)
		engine_shutdown_until_tick = maxi(0, int(engine_shutdown_until_tick_value))
		top_speed_bonus = clampi(int(top_speed_bonus_value), 0, 16)
		thruster_bonus = clampi(int(thruster_bonus_value), 0, 16)
		recharge_bonus = clampi(int(recharge_bonus_value), 0, 16)

		energy_current = maxi(0, int(energy_current_value))
		energy_max = maxi(0, int(energy_max_value))
		energy_recharge_rate_per_sec = maxi(0, int(energy_recharge_rate_per_sec_value))
		energy_recharge_delay_ticks = maxi(0, int(energy_recharge_delay_ticks_value))
		energy_recharge_wait_ticks = maxi(0, int(energy_recharge_wait_ticks_value))
		energy_recharge_fp_accum = maxi(0, int(energy_recharge_fp_accum_value))
		energy_drain_fp_accum = maxi(0, int(energy_drain_fp_accum_value))

		afterburner_on = bool(afterburner_on_value)
		stealth_on = bool(stealth_on_value)
		cloak_on = bool(cloak_on_value)
		xradar_on = bool(xradar_on_value)
		antiwarp_on = bool(antiwarp_on_value)
		in_safe_zone = bool(in_safe_zone_value)
		damage_protect_until_tick = maxi(0, int(damage_protect_until_tick_value))
		dead_until_tick = maxi(0, int(dead_until_tick_value))
		last_energy_change_reason = int(last_energy_change_reason_value)
		last_energy_change_source_id = int(last_energy_change_source_id_value)
		last_energy_change_tick = maxi(0, int(last_energy_change_tick_value))

		energy = clampf(float(energy_value), 0.0, 1000000.0)



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
	# Snapshot-stable weapon level at time of firing.
	# Used for deterministic level-based behaviors (e.g., shrapnel) without depending
	# on the firing ship's later upgrades.
	var level: int = 1
	var position: Vector2
	var velocity: Vector2
	var spawn_tick: int
	var die_tick: int
	var bounces_left: int

	func _init(
		bullet_id: int,
		owner_id_value: int,
		level_value: int,
		pos: Vector2,
		vel: Vector2,
		spawn_tick_value: int,
		die_tick_value: int = -1,
		bounces_left_value: int = 0
	) -> void:
		id = bullet_id
		owner_id = owner_id_value
		level = clampi(int(level_value), 1, 3)
		position = pos
		velocity = vel
		spawn_tick = spawn_tick_value
		die_tick = die_tick_value
		bounces_left = int(bounces_left_value)


enum PrizeKind {
	QuickCharge,
	Energy,
	Rotation,
	Stealth,
	Cloak,
	AntiWarp,
	XRadar,
	Warp,
	Gun,
	Bomb,
	BouncingBullets,
	Thruster,
	TopSpeed,
	Recharge,
	MultiFire,
	Proximity,
	Glue,
	AllWeapons,
	Shields,
	Shrapnel,
	Repel,
	Burst,
	Decoy,
	Thor,
	Portal,
	Brick,
	Rocket,
	MultiPrize,
}


static func prize_kind_from_key(key: String) -> int:
	var k := String(key).strip_edges()
	match k:
		"QuickCharge":
			return PrizeKind.QuickCharge
		"Energy":
			return PrizeKind.Energy
		"Rotation":
			return PrizeKind.Rotation
		"Stealth":
			return PrizeKind.Stealth
		"Cloak":
			return PrizeKind.Cloak
		"AntiWarp":
			return PrizeKind.AntiWarp
		"XRadar":
			return PrizeKind.XRadar
		"Warp":
			return PrizeKind.Warp
		"Gun":
			return PrizeKind.Gun
		"Bomb":
			return PrizeKind.Bomb
		"BouncingBullets":
			return PrizeKind.BouncingBullets
		"Thruster":
			return PrizeKind.Thruster
		"TopSpeed":
			return PrizeKind.TopSpeed
		"Recharge":
			return PrizeKind.Recharge
		"MultiFire":
			return PrizeKind.MultiFire
		"Proximity":
			return PrizeKind.Proximity
		"Glue":
			return PrizeKind.Glue
		"AllWeapons":
			return PrizeKind.AllWeapons
		"Shields":
			return PrizeKind.Shields
		"Shrapnel":
			return PrizeKind.Shrapnel
		"Repel":
			return PrizeKind.Repel
		"Burst":
			return PrizeKind.Burst
		"Decoy":
			return PrizeKind.Decoy
		"Thor":
			return PrizeKind.Thor
		"Portal":
			return PrizeKind.Portal
		"Brick":
			return PrizeKind.Brick
		"Rocket":
			return PrizeKind.Rocket
		"MultiPrize":
			return PrizeKind.MultiPrize
		_:
			return -1


static func prize_kind_keys_in_order() -> Array[String]:
	return [
		"QuickCharge",
		"Energy",
		"Rotation",
		"Stealth",
		"Cloak",
		"AntiWarp",
		"XRadar",
		"Warp",
		"Gun",
		"Bomb",
		"BouncingBullets",
		"Thruster",
		"TopSpeed",
		"Recharge",
		"MultiFire",
		"Proximity",
		"Glue",
		"AllWeapons",
		"Shields",
		"Shrapnel",
		"Repel",
		"Burst",
		"Decoy",
		"Thor",
		"Portal",
		"Brick",
		"Rocket",
		"MultiPrize",
	]


class DriftPrizeState:
	var id: int
	var pos: Vector2
	var spawn_tick: int
	var despawn_tick: int
	var kind: int
	var is_negative: bool = false
	var is_death_drop: bool = false

	func _init(
		prize_id: int,
		pos_value: Vector2,
		spawn_tick_value: int,
		despawn_tick_value: int,
		kind_value: int,
		is_negative_value: bool = false,
		is_death_drop_value: bool = false
	) -> void:
		id = int(prize_id)
		pos = pos_value
		spawn_tick = int(spawn_tick_value)
		despawn_tick = int(despawn_tick_value)
		kind = int(kind_value)
		is_negative = bool(is_negative_value)
		is_death_drop = bool(is_death_drop_value)


class DriftWorldSnapshot:
	var tick: int
	var ships: Dictionary # Dictionary[int, DriftShipState]
	var ball_position: Vector2
	var ball_velocity: Vector2
	var ball_owner_id: int
	var bullets: Array = [] # Array[DriftBulletState]
	var prizes: Array = [] # Array[DriftPrizeState]
	var king_ship_id: int = -1

	func _init(tick_value: int, ships_value: Dictionary, ball_pos: Vector2 = Vector2.ZERO, ball_vel: Vector2 = Vector2.ZERO, ball_owner: int = -1, bullets_value: Array = [], prizes_value: Array = [], king_id: int = -1) -> void:
		tick = tick_value
		ships = ships_value
		ball_position = ball_pos
		ball_velocity = ball_vel
		ball_owner_id = ball_owner
		bullets = bullets_value
		prizes = prizes_value
		king_ship_id = king_id
