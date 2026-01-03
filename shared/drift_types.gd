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
		energy_drain_fp_accum_value: int = 0
	) -> void:
		id = ship_id
		position = position_value
		velocity = velocity_value
		rotation = rotation_value
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
	var position: Vector2
	var velocity: Vector2
	var spawn_tick: int
	var die_tick: int
	var bounces_left: int

	func _init(
		bullet_id: int,
		owner_id_value: int,
		pos: Vector2,
		vel: Vector2,
		spawn_tick_value: int,
		die_tick_value: int = -1,
		bounces_left_value: int = 0
	) -> void:
		id = bullet_id
		owner_id = owner_id_value
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
