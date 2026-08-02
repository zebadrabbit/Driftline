## Driftline shared networking packets + serialization.
##
## Purpose:
## - Define minimal packet types
## - Provide explicit pack/unpack helpers using StreamPeerBuffer
##
## Notes:
## - Floats are sent directly (no quantization yet)
## - Packet layouts are versionless for now (keep stable)

class_name DriftNet

const DriftTypes = preload("res://shared/drift_types.gd")


const PKT_INPUT: int = 1
const PKT_SNAPSHOT: int = 2
const PKT_WELCOME: int = 3
const PKT_HELLO: int = 4
const PKT_PRIZE_EVENT: int = 5
const PKT_SET_FREQ_REQUEST: int = 6
const PKT_SET_FREQ_RESULT: int = 7
const PKT_SHIP_CHANGE_REQUEST: int = 8
const PKT_SHIP_CHANGE_RESULT: int = 9
const PKT_KILL_EVENT: int = 10
const PKT_CHAT_MESSAGE: int = 11
const PKT_CHAT_BROADCAST: int = 12
const PKT_SCORE_EVENT: int = 13

# Reasons for PKT_SET_FREQ_RESULT.
# Keep these stable; they are part of the network contract.
const SET_FREQ_REASON_NONE: int = 0
const SET_FREQ_REASON_OUT_OF_BOUNDS: int = 1
const SET_FREQ_REASON_UNEVEN_TEAMS: int = 2
const SET_FREQ_REASON_COOLDOWN: int = 3
const SET_FREQ_REASON_NOT_ALLOWED: int = 4

const PRIZE_EVENT_PICKUP: int = 1


static func pack_prize_event_packet(event_type: int, ship_id: int, prize_id: int) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.seek(0)
	buffer.put_u8(PKT_PRIZE_EVENT)
	buffer.put_u8(int(clampi(int(event_type), 0, 255)))
	buffer.put_32(int(ship_id))
	buffer.put_32(int(prize_id))
	return buffer.data_array


static func unpack_prize_event_packet(bytes: PackedByteArray) -> Dictionary:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(0)
	var pkt_type: int = buffer.get_u8()
	if pkt_type != PKT_PRIZE_EVENT:
		return {}
	# event_type + ship_id + prize_id = 1 + 4 + 4 bytes
	if buffer.get_available_bytes() < 9:
		return {}
	var event_type: int = int(buffer.get_u8())
	var ship_id: int = int(buffer.get_32())
	var prize_id: int = int(buffer.get_32())
	return {
		"type": pkt_type,
		"event_type": event_type,
		"ship_id": ship_id,
		"prize_id": prize_id,
	}

static func pack_hello(username: String) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.seek(0)
	buffer.put_u8(PKT_HELLO)
	var utf8 = username.to_utf8_buffer()
	buffer.put_u16(utf8.size())
	buffer.put_data(utf8)
	return buffer.data_array

static func unpack_hello(bytes: PackedByteArray) -> String:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(0)
	var pkt_type: int = buffer.get_u8()
	if pkt_type != PKT_HELLO:
		return ""
	if buffer.get_available_bytes() < 2:
		return ""
	var length = buffer.get_u16()
	if length <= 0 or buffer.get_available_bytes() < length:
		return ""
	# get_data() returns [error, PackedByteArray] — index [1] for the bytes.
	var data = buffer.get_data(length)
	return (data[1] as PackedByteArray).get_string_from_utf8()


static func pack_set_freq_request(ship_id: int, desired_freq: int) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.seek(0)
	buffer.put_u8(PKT_SET_FREQ_REQUEST)
	buffer.put_32(int(ship_id))
	buffer.put_16(int(clampi(int(desired_freq), 0, 65535)))
	return buffer.data_array


static func unpack_set_freq_request(bytes: PackedByteArray) -> Dictionary:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(0)
	var pkt_type: int = buffer.get_u8()
	if pkt_type != PKT_SET_FREQ_REQUEST:
		return {}
	# ship_id (4) + desired_freq (2)
	if buffer.get_available_bytes() < 6:
		return {}
	var ship_id: int = int(buffer.get_32())
	var desired_freq: int = int(buffer.get_16())
	return {
		"type": pkt_type,
		"ship_id": ship_id,
		"desired_freq": desired_freq,
	}


static func pack_set_freq_result(ship_id: int, ok: bool, freq: int, reason: int) -> PackedByteArray:
	# Result for PKT_SET_FREQ_REQUEST.
	# Layout:
	#   u8  type
	#   u32 ship_id
	#   u8  ok (0/1)
	#   u16 freq (requested)
	#   u8  reason (enum)
	var buffer := StreamPeerBuffer.new()
	buffer.seek(0)
	buffer.put_u8(PKT_SET_FREQ_RESULT)
	buffer.put_32(int(ship_id))
	buffer.put_u8(1 if bool(ok) else 0)
	buffer.put_16(int(clampi(int(freq), 0, 65535)))
	buffer.put_u8(int(clampi(int(reason), 0, 255)))
	return buffer.data_array


static func unpack_set_freq_result(bytes: PackedByteArray) -> Dictionary:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(0)
	var pkt_type: int = buffer.get_u8()
	if pkt_type != PKT_SET_FREQ_RESULT:
		return {}
	# ship_id (4) + ok (1) + freq (2) + reason (1)
	if buffer.get_available_bytes() < 8:
		return {}
	var ship_id: int = int(buffer.get_32())
	var ok_flag: bool = (int(buffer.get_u8()) != 0)
	var freq: int = int(buffer.get_16())
	var reason: int = int(buffer.get_u8())
	return {
		"type": pkt_type,
		"ship_id": ship_id,
		"ok": ok_flag,
		"freq": freq,
		"reason": reason,
	}


# Ship change request/result reason codes.
const SHIP_CHANGE_REASON_NONE: int = 0
const SHIP_CHANGE_REASON_INVALID_TYPE: int = 1
const SHIP_CHANGE_REASON_COOLDOWN: int = 2


static func pack_ship_change_request(ship_id: int, desired_ship_type: int) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.seek(0)
	buffer.put_u8(PKT_SHIP_CHANGE_REQUEST)
	buffer.put_32(int(ship_id))
	buffer.put_u8(int(clampi(int(desired_ship_type), 0, 255)))
	return buffer.data_array


static func unpack_ship_change_request(bytes: PackedByteArray) -> Dictionary:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(0)
	var pkt_type: int = buffer.get_u8()
	if pkt_type != PKT_SHIP_CHANGE_REQUEST:
		return {}
	# ship_id (4) + desired_ship_type (1)
	if buffer.get_available_bytes() < 5:
		return {}
	var ship_id: int = int(buffer.get_32())
	var desired_ship_type: int = int(buffer.get_u8())
	return {
		"type": pkt_type,
		"ship_id": ship_id,
		"desired_ship_type": desired_ship_type,
	}


static func pack_ship_change_result(ship_id: int, ok: bool, ship_type: int, reason: int) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.seek(0)
	buffer.put_u8(PKT_SHIP_CHANGE_RESULT)
	buffer.put_32(int(ship_id))
	buffer.put_u8(1 if bool(ok) else 0)
	buffer.put_u8(int(clampi(int(ship_type), 0, 255)))
	buffer.put_u8(int(clampi(int(reason), 0, 255)))
	return buffer.data_array


static func unpack_ship_change_result(bytes: PackedByteArray) -> Dictionary:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(0)
	var pkt_type: int = buffer.get_u8()
	if pkt_type != PKT_SHIP_CHANGE_RESULT:
		return {}
	# ship_id (4) + ok (1) + ship_type (1) + reason (1)
	if buffer.get_available_bytes() < 7:
		return {}
	var ship_id: int = int(buffer.get_32())
	var ok_flag: bool = (int(buffer.get_u8()) != 0)
	var ship_type: int = int(buffer.get_u8())
	var reason: int = int(buffer.get_u8())
	return {
		"type": pkt_type,
		"ship_id": ship_id,
		"ok": ok_flag,
		"ship_type": ship_type,
		"reason": reason,
	}


static func get_packet_type(bytes: PackedByteArray) -> int:
	if bytes.size() < 1:
		return 0
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(0)
	return buffer.get_u8()


static func pack_input_packet(tick: int, ship_id: int, cmd: DriftTypes.DriftInputCmd) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.seek(0)

	# Input packet tick refers to the simulation tick that will be stepped next using this input.
	buffer.put_u8(PKT_INPUT)
	buffer.put_32(tick)
	buffer.put_32(ship_id)
	# Core layout (kept stable): forward bool, reverse bool, rotation scalar, fire_primary bool.
	buffer.put_u8(1 if cmd.thrust > 0.0 else 0)
	buffer.put_u8(1 if cmd.thrust < 0.0 else 0)
	buffer.put_float(cmd.rotation)
	buffer.put_u8(1 if cmd.fire_primary else 0)
	# Extensions (optional trailing fields; old servers/clients ignore extra bytes).
	buffer.put_u8(1 if cmd.fire_secondary else 0)
	buffer.put_u8(1 if cmd.modifier else 0)
	buffer.put_u8(1 if cmd.stealth_btn else 0)
	buffer.put_u8(1 if cmd.cloak_btn else 0)
	buffer.put_u8(1 if cmd.xradar_btn else 0)
	buffer.put_u8(1 if cmd.antiwarp_btn else 0)
	# Mine-lay extension (optional trailing fields; append-only).
	buffer.put_u8(1 if cmd.lay_mine else 0)
	# Item-use buttons (append-only).
	buffer.put_u8(1 if cmd.repel_btn else 0)
	buffer.put_u8(1 if cmd.burst_btn else 0)
	buffer.put_u8(1 if cmd.warp_btn else 0)
	buffer.put_u8(1 if cmd.thor_btn else 0)
	buffer.put_u8(1 if cmd.rocket_btn else 0)
	buffer.put_u8(1 if cmd.decoy_btn else 0)
	buffer.put_u8(1 if cmd.brick_btn else 0)
	buffer.put_u8(1 if cmd.portal_btn else 0)
	# Multifire toggle button (append-only).
	buffer.put_u8(1 if cmd.multifire_btn else 0)

	return buffer.data_array


static func unpack_input_packet(bytes: PackedByteArray) -> Dictionary:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(0)

	var pkt_type: int = buffer.get_u8()
	if pkt_type != PKT_INPUT:
		return {}
	# The core layout below is fixed size (tick 4 + ship_id 4 + fwd 1 + rev 1 +
	# rotation 4 + fire 1). The server parses these bytes straight off the wire, so a
	# short packet must be rejected rather than read as zeros.
	if buffer.get_available_bytes() < 15:
		return {}

	# Input packet tick refers to the simulation tick that will be stepped next using this input.
	var tick: int = buffer.get_32()
	var ship_id: int = buffer.get_32()
	var forward: bool = buffer.get_u8() != 0
	var reverse: bool = buffer.get_u8() != 0
	var rotation: float = buffer.get_float()
	var fire_primary: bool = buffer.get_u8() != 0
	var fire_secondary: bool = false
	var modifier: bool = false
	var stealth_btn: bool = false
	var cloak_btn: bool = false
	var xradar_btn: bool = false
	var antiwarp_btn: bool = false
	var lay_mine: bool = false
	var repel_btn: bool = false
	var burst_btn: bool = false
	var warp_btn: bool = false
	if buffer.get_available_bytes() >= 1:
		fire_secondary = buffer.get_u8() != 0
	if buffer.get_available_bytes() >= 1:
		modifier = buffer.get_u8() != 0
	if buffer.get_available_bytes() >= 1:
		stealth_btn = buffer.get_u8() != 0
	if buffer.get_available_bytes() >= 1:
		cloak_btn = buffer.get_u8() != 0
	if buffer.get_available_bytes() >= 1:
		xradar_btn = buffer.get_u8() != 0
	if buffer.get_available_bytes() >= 1:
		antiwarp_btn = buffer.get_u8() != 0
	if buffer.get_available_bytes() >= 1:
		lay_mine = buffer.get_u8() != 0
	if buffer.get_available_bytes() >= 1:
		repel_btn = buffer.get_u8() != 0
	if buffer.get_available_bytes() >= 1:
		burst_btn = buffer.get_u8() != 0
	if buffer.get_available_bytes() >= 1:
		warp_btn = buffer.get_u8() != 0
	var thor_btn: bool = false
	var rocket_btn: bool = false
	var decoy_btn: bool = false
	var brick_btn: bool = false
	if buffer.get_available_bytes() >= 1:
		thor_btn = buffer.get_u8() != 0
	if buffer.get_available_bytes() >= 1:
		rocket_btn = buffer.get_u8() != 0
	if buffer.get_available_bytes() >= 1:
		decoy_btn = buffer.get_u8() != 0
	if buffer.get_available_bytes() >= 1:
		brick_btn = buffer.get_u8() != 0
	var portal_btn: bool = false
	if buffer.get_available_bytes() >= 1:
		portal_btn = buffer.get_u8() != 0
	var multifire_btn: bool = false
	if buffer.get_available_bytes() >= 1:
		multifire_btn = buffer.get_u8() != 0
	var thrust: float = (1.0 if forward else 0.0) + (-1.0 if reverse else 0.0)

	return {
		"type": pkt_type,
		"tick": tick,
		"ship_id": ship_id,
		"thrust": thrust,
		"rotation": clampf(rotation, -1.0, 1.0),
		"fire_primary": fire_primary,
		"fire_secondary": fire_secondary,
		"modifier": modifier,
		"stealth_btn": stealth_btn,
		"cloak_btn": cloak_btn,
		"xradar_btn": xradar_btn,
		"antiwarp_btn": antiwarp_btn,
		"lay_mine": lay_mine,
		"repel_btn": repel_btn,
		"burst_btn": burst_btn,
		"warp_btn": warp_btn,
		"thor_btn": thor_btn,
		"rocket_btn": rocket_btn,
		"decoy_btn": decoy_btn,
		"brick_btn": brick_btn,
		"portal_btn": portal_btn,
		"multifire_btn": multifire_btn,
	}



# Extended: ships + ball (+ optional bullets)
static func pack_snapshot_packet(
	tick: int,
	ships: Array,
	ball_pos: Vector2 = Vector2.ZERO,
	ball_vel: Vector2 = Vector2.ZERO,
	ball_owner_id: int = -1,
	bullets: Array = [],
	bombs: Array = [],
	mines: Array = [],
	prizes: Array = [],
	prize_events: Array = [],
	extra_data: Dictionary = {},
	decoys: Array = [],
	bricks: Array = [],
	effect_events: Array = [],
) -> PackedByteArray:
	# ships: Array[DriftShipState]
	var buffer := StreamPeerBuffer.new()
	buffer.seek(0)

	buffer.put_u8(PKT_SNAPSHOT)
	buffer.put_32(tick)
	buffer.put_u16(ships.size())

	for ship_state in ships:
		buffer.put_32(ship_state.id)
		buffer.put_float(ship_state.position.x)
		buffer.put_float(ship_state.position.y)
		buffer.put_float(ship_state.velocity.x)
		buffer.put_float(ship_state.velocity.y)
		buffer.put_float(ship_state.rotation)

	# Ball state (always present)
	buffer.put_float(ball_pos.x)
	buffer.put_float(ball_pos.y)
	buffer.put_float(ball_vel.x)
	buffer.put_float(ball_vel.y)
	buffer.put_32(ball_owner_id)

	# Bullets extension (optional trailing fields; old clients ignore extra bytes).
	# Layout:
	#   u16 bullet_count
	#   repeated bullet_count times:
	#     u32 id
	#     u32 owner_id
	#     f32 px, py
	#     f32 vx, vy
	#     u32 spawn_tick
	#     u32 die_tick
	#   [optional] u16 bullet_extras_count
	#   [optional] repeated bullet_extras_count times:
	#     u32 id
	#     u16 bounces_left
	#   [optional] u16 bullet_extras_v2_count
	#   [optional] repeated bullet_extras_v2_count times:
	#     u32 id
	#     u8 level
	#   [optional] u16 ship_extras_count
	#   [optional] repeated ship_extras_count times:
	#     u32 id
	#     u8 gun_level
	#     u8 bomb_level
	#     u8 bullet_bounce_bonus
	#     u8 flags (bit0=multi_fire_enabled, bit1=bomb_proximity_enabled, bit2=multi_fire_capable,
	#              bit3=has_stealth, bit4=has_cloak, bit5=has_xradar, bit6=has_antiwarp)
	#     u32 engine_shutdown_until_tick
	#     u32 bounty
	#   [optional] u16 prize_count
	#   [optional] repeated prize_count times:
	#     u32 id
	#     f32 px, py
	#     u16 kind
	#     u32 despawn_tick
	#     u8 flags (bit0=is_negative, bit1=is_death_drop)
	#   [optional] u16 ship_extras_v2_count
	#   [optional] repeated ship_extras_v2_count times:
	#     u32 id
	#     f32 energy
	#     u8 top_speed_bonus
	#     u8 thruster_bonus
	#     u8 recharge_bonus
	#   [optional] u16 ship_energy_v3_count
	#   [optional] repeated ship_energy_v3_count times:
	#     u32 id
	#     u32 energy_current
	#     u32 energy_max
	#     u32 energy_recharge_rate_per_sec
	#     u16 energy_recharge_delay_ticks
	#     u16 energy_recharge_wait_ticks
	#     u16 energy_recharge_fp_accum
	#     u16 energy_drain_fp_accum
	#   [optional] u16 prize_event_count
	#   [optional] repeated prize_event_count times:
	#     u8 event_type (1=pickup)
	#     u32 ship_id
	#     u32 prize_id
	#   [optional] u16 ship_abilities_v1_count
	#   [optional] repeated ship_abilities_v1_count times:
	#     u32 id
	#     u8 flags (bit0=stealth_on, bit1=cloak_on, bit2=xradar_on, bit3=antiwarp_on, bit4=in_safe_zone)
	#   [optional] u16 ship_damage_v1_count
	#   [optional] repeated ship_damage_v1_count times:
	#     u32 id
	#     u32 damage_protect_until_tick
	#   [optional] u16 ship_death_v1_count
	#   [optional] repeated ship_death_v1_count times:
	#     u32 id
	#     u32 dead_until_tick
	#   [optional] u16 ship_safe_zone_timer_v1_count
	#   [optional] repeated ship_safe_zone_timer_v1_count times:
	#     u32 id
	#     u32 safe_zone_time_used_ticks
	#     u32 safe_zone_time_max_ticks
	#   [optional] u16 ship_freq_v1_count
	#   [optional] repeated ship_freq_v1_count times:
	#     u32 id
	#     u16 freq
	#   [optional] u16 ship_weapon_cooldown_v1_count
	#   [optional] repeated ship_weapon_cooldown_v1_count times:
	#     u32 id
	#     u32 next_bullet_tick
	#   [optional] u16 ship_weapon_cooldown_v2_count
	#   [optional] repeated ship_weapon_cooldown_v2_count times:
	#     u32 id
	#     u32 next_bomb_tick
	#     u32 next_mine_tick
	#   [optional] u16 bomb_count
	#   [optional] repeated bomb_count times:
	#     u32 id
	#     u32 owner_id
	#     f32 px, py
	#     f32 vx, vy
	#     u32 spawn_tick
	#     u32 die_tick
	#     u16 bounces_left
	#     u8 level
	#     u8 flags (bit0=is_emp)
	#   [optional] u16 mine_count
	#   [optional] repeated mine_count times:
	#     u32 id
	#     u32 owner_id
	#     f32 px, py
	#     u32 spawn_tick
	#     u32 die_tick
	#     u8 level
	#     u8 flags (bit0=triggered)
	#     u32 triggered_by_ship_id
	#     u32 triggered_tick
	var bullet_count: int = bullets.size()
	if bullet_count < 0:
		bullet_count = 0
	if bullet_count > 65535:
		bullet_count = 65535
	buffer.put_u16(bullet_count)
	for i in range(bullet_count):
		var b = bullets[i]
		buffer.put_32(int(b.id))
		buffer.put_32(int(b.owner_id))
		buffer.put_float(float(b.position.x))
		buffer.put_float(float(b.position.y))
		buffer.put_float(float(b.velocity.x))
		buffer.put_float(float(b.velocity.y))
		buffer.put_32(int(b.spawn_tick))
		buffer.put_32(int(b.die_tick))

	# Bullet extras (optional trailing section; safe for older clients because it comes
	# AFTER the fixed-size bullet list).
	buffer.put_u16(bullet_count)
	for i in range(bullet_count):
		var b = bullets[i]
		buffer.put_32(int(b.id))
		buffer.put_u16(int(clampi(int(b.bounces_left), 0, 65535)))

	# Bullet extras v2 (optional trailing section; append-only).
	buffer.put_u16(bullet_count)
	for i in range(bullet_count):
		var b2 = bullets[i]
		buffer.put_32(int(b2.id))
		buffer.put_u8(int(clampi(int(b2.level), 1, 4)))  # 4 = burst pellet

	# Ship extras section (optional trailing).
	var ship_count: int = ships.size()
	if ship_count < 0:
		ship_count = 0
	if ship_count > 65535:
		ship_count = 65535
	buffer.put_u16(ship_count)
	for i in range(ship_count):
		var s = ships[i]
		buffer.put_32(int(s.id))
		buffer.put_u8(int(clampi(int(s.gun_level), 1, 3)))
		buffer.put_u8(int(clampi(int(s.bomb_level), 1, 3)))
		buffer.put_u8(int(clampi(int(s.bullet_bounce_bonus), 0, 255)))
		var flags: int = 0
		if bool(s.multi_fire_enabled):
			flags |= 1
		if bool(s.bomb_proximity_enabled):
			flags |= 2
		if bool(s.multi_fire_capable):
			flags |= 4
		if bool(s.has_stealth):
			flags |= 8
		if bool(s.has_cloak):
			flags |= 16
		if bool(s.has_xradar):
			flags |= 32
		if bool(s.has_antiwarp):
			flags |= 64
		buffer.put_u8(flags)
		buffer.put_32(int(maxi(0, int(s.engine_shutdown_until_tick))))
		buffer.put_32(int(maxi(0, int(s.bounty))))

	# Prizes list (optional trailing).
	var prize_count: int = prizes.size()
	if prize_count < 0:
		prize_count = 0
	if prize_count > 65535:
		prize_count = 65535
	buffer.put_u16(prize_count)
	for i in range(prize_count):
		var p = prizes[i]
		buffer.put_32(int(p.id))
		buffer.put_float(float(p.pos.x))
		buffer.put_float(float(p.pos.y))
		buffer.put_u16(int(clampi(int(p.kind), 0, 65535)))
		buffer.put_32(int(p.despawn_tick))
		var pflags: int = 0
		if bool(p.is_negative):
			pflags |= 1
		if bool(p.is_death_drop):
			pflags |= 2
		buffer.put_u8(pflags)

	# Ship extras v2 (optional trailing).
	buffer.put_u16(ship_count)
	for i in range(ship_count):
		var s2 = ships[i]
		buffer.put_32(int(s2.id))
		# Legacy mirror (ship_extras_v2) kept as float for backwards compatibility.
		buffer.put_float(float(int(s2.energy)))
		buffer.put_u8(int(clampi(int(s2.top_speed_bonus), 0, 255)))
		buffer.put_u8(int(clampi(int(s2.thruster_bonus), 0, 255)))
		buffer.put_u8(int(clampi(int(s2.recharge_bonus), 0, 255)))

	# Ship energy v3 (optional trailing).
	buffer.put_u16(ship_count)
	for i in range(ship_count):
		var s3 = ships[i]
		buffer.put_32(int(s3.id))
		buffer.put_32(int(maxi(0, int(s3.energy_current))))
		buffer.put_32(int(maxi(0, int(s3.energy_max))))
		buffer.put_32(int(maxi(0, int(s3.energy_recharge_rate_per_sec))))
		buffer.put_u16(int(clampi(int(s3.energy_recharge_delay_ticks), 0, 65535)))
		buffer.put_u16(int(clampi(int(s3.energy_recharge_wait_ticks), 0, 65535)))
		buffer.put_u16(int(clampi(int(s3.energy_recharge_fp_accum), 0, 65535)))
		buffer.put_u16(int(clampi(int(s3.energy_drain_fp_accum), 0, 65535)))

	# Prize events (optional trailing).
	var ev_count: int = prize_events.size()
	if ev_count < 0:
		ev_count = 0
	if ev_count > 65535:
		ev_count = 65535
	buffer.put_u16(ev_count)
	for i in range(ev_count):
		var e = prize_events[i]
		var et: int = 0
		var sid: int = 0
		var pid: int = 0
		if typeof(e) == TYPE_DICTIONARY:
			var d: Dictionary = e
			if String(d.get("type", "")) == "pickup":
				et = 1
			sid = int(d.get("ship_id", 0))
			pid = int(d.get("prize_id", 0))
		buffer.put_u8(et)
		buffer.put_32(sid)
		buffer.put_32(pid)

	# Ship abilities v1 (optional trailing; append-only so older clients can ignore).
	buffer.put_u16(ship_count)
	for i in range(ship_count):
		var sa = ships[i]
		buffer.put_32(int(sa.id))
		var aflags: int = 0
		if bool(sa.stealth_on):
			aflags |= 1
		if bool(sa.cloak_on):
			aflags |= 2
		if bool(sa.xradar_on):
			aflags |= 4
		if bool(sa.antiwarp_on):
			aflags |= 8
		if bool(sa.in_safe_zone):
			aflags |= 16
		buffer.put_u8(aflags)

	# Ship damage v1 (optional trailing; append-only).
	buffer.put_u16(ship_count)
	for i in range(ship_count):
		var sd = ships[i]
		buffer.put_32(int(sd.id))
		buffer.put_32(int(maxi(0, int(sd.damage_protect_until_tick))))

	# Ship death v1 (optional trailing; append-only).
	buffer.put_u16(ship_count)
	for i in range(ship_count):
		var sx = ships[i]
		buffer.put_32(int(sx.id))
		buffer.put_32(int(maxi(0, int(sx.dead_until_tick))))

	# Ship safe-zone timer v1 (optional trailing; append-only).
	buffer.put_u16(ship_count)
	for i in range(ship_count):
		var st = ships[i]
		buffer.put_32(int(st.id))
		buffer.put_32(int(maxi(0, int(st.safe_zone_time_used_ticks))))
		buffer.put_32(int(maxi(0, int(st.safe_zone_time_max_ticks))))

	# Ship freq v1 (optional trailing; append-only).
	buffer.put_u16(ship_count)
	for i in range(ship_count):
		var sf = ships[i]
		buffer.put_32(int(sf.id))
		buffer.put_u16(int(clampi(int(sf.freq), 0, 65535)))

	# Ship weapon cooldown v1 (optional trailing; append-only).
	buffer.put_u16(ship_count)
	for i in range(ship_count):
		var sw = ships[i]
		buffer.put_32(int(sw.id))
		buffer.put_32(int(maxi(0, int(sw.next_bullet_tick))))

	# Ship weapon cooldown v2 (optional trailing; append-only).
	buffer.put_u16(ship_count)
	for i in range(ship_count):
		var sw2 = ships[i]
		buffer.put_32(int(sw2.id))
		buffer.put_32(int(maxi(0, int(sw2.next_bomb_tick))))
		buffer.put_32(int(maxi(0, int(sw2.next_mine_tick))))

	# Bombs list (optional trailing; append-only).
	var bomb_count: int = bombs.size()
	if bomb_count < 0:
		bomb_count = 0
	if bomb_count > 65535:
		bomb_count = 65535
	buffer.put_u16(bomb_count)
	for i in range(bomb_count):
		var bmb = bombs[i]
		buffer.put_32(int(bmb.id))
		buffer.put_32(int(bmb.owner_id))
		buffer.put_float(float(bmb.position.x))
		buffer.put_float(float(bmb.position.y))
		buffer.put_float(float(bmb.velocity.x))
		buffer.put_float(float(bmb.velocity.y))
		buffer.put_32(int(bmb.spawn_tick))
		buffer.put_32(int(bmb.die_tick))
		buffer.put_u16(int(clampi(int(bmb.bounces_left), 0, 65535)))
		buffer.put_u8(int(clampi(int(bmb.level), 1, 4)))  # 4 = Thor
		var bflags: int = 0
		if bool(bmb.is_emp):
			bflags |= 1
		buffer.put_u8(bflags)

	# Mines list (optional trailing; append-only).
	var mine_count: int = mines.size()
	if mine_count < 0:
		mine_count = 0
	if mine_count > 65535:
		mine_count = 65535
	buffer.put_u16(mine_count)
	for i in range(mine_count):
		var mn = mines[i]
		buffer.put_32(int(mn.id))
		buffer.put_32(int(mn.owner_id))
		buffer.put_float(float(mn.position.x))
		buffer.put_float(float(mn.position.y))
		buffer.put_32(int(mn.spawn_tick))
		buffer.put_32(int(mn.die_tick))
		buffer.put_u8(int(clampi(int(mn.level), 1, 3)))
		var mflags: int = 0
		if bool(mn.triggered):
			mflags |= 1
		buffer.put_u8(mflags)
		buffer.put_32(int(mn.triggered_by_ship_id))
		buffer.put_32(int(mn.triggered_tick))

	# Ship type v1 (optional trailing; append-only).
	#   u16 ship_type_v1_count
	#   repeated ship_type_v1_count times:
	#     u32 id
	#     u8  ship_type (0-7)
	buffer.put_u16(ship_count)
	for i in range(ship_count):
		var stype = ships[i]
		buffer.put_32(int(stype.id))
		buffer.put_u8(int(clampi(int(stype.ship_type), 0, 255)))

	# Ship items v1 (optional trailing; append-only).
	#   u16 count
	#   repeated count times:
	#     u32 id
	#     u8  repel_count
	#     u8  burst_count
	#     u8  warp_count
	#     u32 shields_until_tick
	#     u8  super_shields (0/1)
	buffer.put_u16(ship_count)
	for i in range(ship_count):
		var si = ships[i]
		buffer.put_32(int(si.id))
		buffer.put_u8(int(clampi(int(si.repel_count), 0, 255)))
		buffer.put_u8(int(clampi(int(si.burst_count), 0, 255)))
		buffer.put_u8(int(clampi(int(si.warp_count), 0, 255)))
		buffer.put_32(int(maxi(0, int(si.shields_until_tick))))
		buffer.put_u8(1 if bool(si.super_shields) else 0)

	# Ship stats v1 (optional trailing; append-only).
	#   u16 count, repeated: u32 id, u16 kills, u16 deaths
	buffer.put_u16(ship_count)
	for i in range(ship_count):
		var ss2 = ships[i]
		buffer.put_32(int(ss2.id))
		buffer.put_u16(int(clampi(int(ss2.kills), 0, 65535)))
		buffer.put_u16(int(clampi(int(ss2.deaths), 0, 65535)))

	# Ship CTF v1 (optional trailing; append-only).
	#   u16 count, repeated: u32 id, i8 carried_flag_team (-1=none, stored as u8 0xFF)
	buffer.put_u16(ship_count)
	for i in range(ship_count):
		var sctf = ships[i]
		buffer.put_32(int(sctf.id))
		var cft: int = int(sctf.carried_flag_team) if ("carried_flag_team" in sctf) else -1
		buffer.put_u8(cft & 0xFF)  # -1 → 0xFF, 1 → 0x01, 2 → 0x02

	# Flag state v1 (optional trailing; append-only).
	#   u16 flag_count
	#   repeated flag_count times:
	#     u8  team
	#     f32 px, py
	#     u32 carrier_ship_id (0xFFFFFFFF = -1)
	#     u8  flags (bit0=at_home)
	#     u32 drop_tick (0xFFFFFFFF = -1)
	if "flags" in extra_data and typeof(extra_data.get("flags")) == TYPE_ARRAY:
		var flag_arr: Array = extra_data.get("flags", [])
		buffer.put_u16(mini(flag_arr.size(), 255))
		for fl in flag_arr:
			buffer.put_u8(int(clampi(int(fl.team), 0, 255)))
			buffer.put_float(float(fl.position.x))
			buffer.put_float(float(fl.position.y))
			buffer.put_32(int(fl.carrier_ship_id))   # -1 = not carried
			var fflags: int = 1 if bool(fl.at_home) else 0
			buffer.put_u8(fflags)
			buffer.put_32(int(fl.drop_tick))          # -1 = not dropped
	else:
		buffer.put_u16(0)

	# Ship items v2 (optional trailing; append-only).
	#   u16 count, repeated: u32 id, u8 thor_count, u8 rocket_count, u8 decoy_count, u8 brick_count, u8 portal_count
	buffer.put_u16(ship_count)
	for i in range(ship_count):
		var si2 = ships[i]
		buffer.put_32(int(si2.id))
		buffer.put_u8(int(clampi(int(si2.thor_count) if ("thor_count" in si2) else 0, 0, 255)))
		buffer.put_u8(int(clampi(int(si2.rocket_count) if ("rocket_count" in si2) else 0, 0, 255)))
		buffer.put_u8(int(clampi(int(si2.decoy_count) if ("decoy_count" in si2) else 0, 0, 255)))
		buffer.put_u8(int(clampi(int(si2.brick_count) if ("brick_count" in si2) else 0, 0, 255)))
		buffer.put_u8(int(clampi(int(si2.portal_count) if ("portal_count" in si2) else 0, 0, 255)))

	# Ship upgrades v2 (optional trailing; append-only).
	#   u16 count, repeated: u32 id, u8 rotation_bonus, u8 shrapnel_bonus, u32 rocket_boost_until_tick
	buffer.put_u16(ship_count)
	for i in range(ship_count):
		var su = ships[i]
		buffer.put_32(int(su.id))
		buffer.put_u8(int(clampi(int(su.rotation_bonus) if ("rotation_bonus" in su) else 0, 0, 255)))
		buffer.put_u8(int(clampi(int(su.shrapnel_bonus) if ("shrapnel_bonus" in su) else 0, 0, 255)))
		buffer.put_32(int(maxi(0, int(su.rocket_boost_until_tick) if ("rocket_boost_until_tick" in su) else 0)))

	# Trailing section: radar_ships_v1
	# Ships outside the client's AOI: position + freq + dead flag only (14 bytes each).
	# Format: u16 count, repeated: u32 id, f32 px, f32 py, u8 freq, u8 flags(bit0=dead)
	if "radar_ships" in extra_data and typeof(extra_data.get("radar_ships")) == TYPE_ARRAY:
		var rs_arr: Array = extra_data.get("radar_ships", [])
		buffer.put_u16(mini(rs_arr.size(), 0xFFFF))
		for rs in rs_arr:
			buffer.put_u32(int(rs.get("id", 0)))
			buffer.put_float(float(rs.get("px", 0.0)))
			buffer.put_float(float(rs.get("py", 0.0)))
			buffer.put_u8(int(clampi(int(rs.get("freq", 0)), 0, 255)))
			buffer.put_u8(1 if bool(rs.get("dead", false)) else 0)
	else:
		buffer.put_u16(0)

	# Decoys trailing section.
	# Format: u16 count, repeated: u32 id, u32 owner_id, u8 freq, u8 ship_type, f32 px, f32 py, f32 vx, f32 vy, f32 rot, u32 die_tick
	buffer.put_u16(mini(decoys.size(), 0xFFFF))
	for dc in decoys:
		buffer.put_32(int(dc.id))
		buffer.put_32(int(dc.owner_id))
		buffer.put_u8(int(clampi(int(dc.freq), 0, 255)))
		buffer.put_u8(int(clampi(int(dc.ship_type), 0, 255)))
		buffer.put_float(float(dc.position.x))
		buffer.put_float(float(dc.position.y))
		buffer.put_float(float(dc.velocity.x))
		buffer.put_float(float(dc.velocity.y))
		buffer.put_float(float(dc.rotation))
		buffer.put_32(int(dc.die_tick))

	# Bricks trailing section.
	# Format: u16 group_count, repeated: u32 die_tick, u8 freq, u16 tile_count, repeated: i16 tx, i16 ty
	buffer.put_u16(mini(bricks.size(), 0xFFFF))
	for br in bricks:
		buffer.put_32(int(br.get("die_tick", 0)))
		buffer.put_u8(clampi(int(br.get("freq", 0)), 0, 255))
		var br_tiles: Array = br.get("tiles", [])
		buffer.put_u16(mini(br_tiles.size(), 0xFFFF))
		for tile in br_tiles:
			buffer.put_16(int(tile.x))
			buffer.put_16(int(tile.y))

	# Effect events trailing section.
	# Format: u16 count, repeated: u8 type, u32 ship_id, f32 px, f32 py  (11 bytes each)
	# type: 0=repel
	buffer.put_u16(mini(effect_events.size(), 0xFFFF))
	for ee in effect_events:
		var ee_type_byte: int = 255
		match StringName(ee.get("type", "")):
			&"repel": ee_type_byte = 0
			&"warp": ee_type_byte = 1
			&"thor": ee_type_byte = 2
		buffer.put_u8(ee_type_byte)
		buffer.put_32(int(ee.get("ship_id", 0)))
		buffer.put_float(float(ee.get("px", 0.0)))
		buffer.put_float(float(ee.get("py", 0.0)))

	# King ship trailing section: i32 king_ship_id (-1 = none).
	buffer.put_32(int(extra_data.get("king_ship_id", -1)))

	# Ship points v1 (optional trailing; append-only).
	#   u16 count, repeated: u32 id, u32 points
	buffer.put_u16(ship_count)
	for i in range(ship_count):
		var sp = ships[i]
		buffer.put_32(int(sp.id))
		buffer.put_u32(maxi(0, int(sp.points) if ("points" in sp) else 0))

	# King of the Hill v1 (optional trailing; append-only).
	#   u16 count, repeated: u32 id, u8 crown_on, u32 crown_ticks_left
	buffer.put_u16(ship_count)
	for i in range(ship_count):
		var sk = ships[i]
		buffer.put_32(int(sk.id))
		buffer.put_u8(1 if bool(sk.crown_on) else 0)
		buffer.put_u32(maxi(0, int(sk.crown_ticks_left)))

	return buffer.data_array


static func pack_welcome_packet(
	ship_id: int,
	map_checksum: PackedByteArray = PackedByteArray(),
	map_path: String = "",
	map_version: int = 0,
	wall_restitution: float = -1.0,
	ruleset_json: String = "",
	tangent_damping: float = -1.0,
	ship_spec_json: String = "",
	all_ship_specs_json: String = "",
) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.seek(0)

	buffer.put_u8(PKT_WELCOME)
	buffer.put_32(ship_id)
	# Optional: deterministic map checksum for handshake verification.
	# Layout extension:
	#   u8 checksum_len (0 or N)
	#   u8[N] checksum
	var checksum_len: int = map_checksum.size()
	if checksum_len < 0:
		checksum_len = 0
	if checksum_len > 255:
		checksum_len = 255
	buffer.put_u8(checksum_len)
	if checksum_len > 0:
		# Write bytes explicitly to avoid any PackedByteArray slicing/put_data edge cases.
		for i in range(checksum_len):
			buffer.put_u8(int(map_checksum[i]))

	# MapManifest extension:
	#   u16 map_path_len
	#   u8[map_path_len] utf8 map_path
	#   u32 map_version
	var path_utf8 := map_path.to_utf8_buffer()
	var path_len: int = path_utf8.size()
	if path_len < 0:
		path_len = 0
	if path_len > 65535:
		path_len = 65535
	buffer.put_u16(path_len)
	if path_len > 0:
		for i in range(path_len):
			buffer.put_u8(int(path_utf8[i]))
	buffer.put_32(map_version)

	# Ruleset extension (optional trailing fields; read only if present).
	#   f32 wall_restitution
	# If the caller supplies a negative value, omit the field.
	if wall_restitution >= 0.0:
		buffer.put_float(wall_restitution)

	# Ruleset JSON extension (optional; read only if present).
	# Layout extension:
	#   u32 ruleset_len (0 or N)
	#   u8[N] utf8 JSON
	var rj := String(ruleset_json)
	if rj.strip_edges() == "":
		buffer.put_32(0)
	else:
		var utf8 := rj.to_utf8_buffer()
		buffer.put_32(utf8.size())
		if utf8.size() > 0:
			for i in range(utf8.size()):
				buffer.put_u8(int(utf8[i]))

	# Tangent damping extension (optional trailing field; read only if present).
	#   f32 tangent_damping
	# If the caller supplies a negative value, omit the field.
	if tangent_damping >= 0.0:
		buffer.put_float(tangent_damping)

	# Ship spec JSON extension (optional; append-only).
	# Layout extension:
	#   u32 ship_spec_len (0 or N)
	#   u8[N] utf8 JSON
	var sj := String(ship_spec_json)
	if sj.strip_edges() == "":
		buffer.put_32(0)
	else:
		var sj_utf8 := sj.to_utf8_buffer()
		buffer.put_32(sj_utf8.size())
		if sj_utf8.size() > 0:
			for i in range(sj_utf8.size()):
				buffer.put_u8(int(sj_utf8[i]))

	# All ship specs JSON array extension (optional; append-only).
	# Contains JSON array of 8 ship spec dictionaries (indexed by ship_type).
	# Layout extension:
	#   u32 all_specs_len (0 or N)
	#   u8[N] utf8 JSON
	var asj := String(all_ship_specs_json)
	if asj.strip_edges() == "":
		buffer.put_32(0)
	else:
		var asj_utf8 := asj.to_utf8_buffer()
		buffer.put_32(asj_utf8.size())
		if asj_utf8.size() > 0:
			for i in range(asj_utf8.size()):
				buffer.put_u8(int(asj_utf8[i]))

	return buffer.data_array


# Minimal convenience API (keeps older code working).
static func pack_welcome(ship_id: int) -> PackedByteArray:
	return pack_welcome_packet(ship_id)


static func unpack_welcome_packet(bytes: PackedByteArray) -> Dictionary:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(0)

	var pkt_type: int = buffer.get_u8()
	if pkt_type != PKT_WELCOME:
		return {}

	var ship_id: int = buffer.get_32()
	var checksum: PackedByteArray = PackedByteArray()
	var map_path: String = ""
	var map_version: int = 0
	var wall_restitution: float = -1.0
	var ruleset_json: String = ""
	var tangent_damping: float = -1.0
	var ship_spec_json: String = ""
	var all_ship_specs_json: String = ""
	# Backward compatible: checksum field may be absent.
	if bytes.size() >= (1 + 4 + 1):
		var checksum_len: int = int(buffer.get_u8())
		if checksum_len > 0 and bytes.size() >= (1 + 4 + 1 + checksum_len):
			checksum.resize(checksum_len)
			for i in range(checksum_len):
				checksum[i] = int(buffer.get_u8())

	# Backward compatible: map manifest fields may be absent.
	# Only read if the buffer still has enough bytes remaining.
	if buffer.get_available_bytes() >= 2:
		var path_len: int = int(buffer.get_u16())
		if path_len > 0 and buffer.get_available_bytes() >= path_len:
			var path_bytes := PackedByteArray()
			path_bytes.resize(path_len)
			for i in range(path_len):
				path_bytes[i] = int(buffer.get_u8())
			map_path = path_bytes.get_string_from_utf8()
		# map_version is optional; only read if present.
		if buffer.get_available_bytes() >= 4:
			map_version = int(buffer.get_32())
		# wall_restitution is optional; only read if present.
		if buffer.get_available_bytes() >= 4:
			wall_restitution = float(buffer.get_float())
		# ruleset_json is optional; only read if present.
		if buffer.get_available_bytes() >= 4:
			var ruleset_len: int = int(buffer.get_32())
			if ruleset_len > 0 and buffer.get_available_bytes() >= ruleset_len:
				var ruleset_bytes := PackedByteArray()
				ruleset_bytes.resize(ruleset_len)
				for i in range(ruleset_len):
					ruleset_bytes[i] = int(buffer.get_u8())
				ruleset_json = ruleset_bytes.get_string_from_utf8()
		# tangent_damping is optional; only read if present.
		if buffer.get_available_bytes() >= 4:
			tangent_damping = float(buffer.get_float())
		# ship_spec_json is optional; only read if present.
		if buffer.get_available_bytes() >= 4:
			var ship_spec_len: int = int(buffer.get_32())
			if ship_spec_len > 0 and buffer.get_available_bytes() >= ship_spec_len:
				var ship_spec_bytes := PackedByteArray()
				ship_spec_bytes.resize(ship_spec_len)
				for i in range(ship_spec_len):
					ship_spec_bytes[i] = int(buffer.get_u8())
				ship_spec_json = ship_spec_bytes.get_string_from_utf8()
		# all_ship_specs_json is optional; only read if present.
		if buffer.get_available_bytes() >= 4:
			var all_specs_len: int = int(buffer.get_32())
			if all_specs_len > 0 and buffer.get_available_bytes() >= all_specs_len:
				var all_specs_bytes := PackedByteArray()
				all_specs_bytes.resize(all_specs_len)
				for i in range(all_specs_len):
					all_specs_bytes[i] = int(buffer.get_u8())
				all_ship_specs_json = all_specs_bytes.get_string_from_utf8()
	return {
		"type": pkt_type,
		"ship_id": ship_id,
		"map_checksum": checksum,
		"map_path": map_path,
		"map_version": map_version,
		"wall_restitution": wall_restitution,
		"ruleset_json": ruleset_json,
		"tangent_damping": tangent_damping,
		"ship_spec_json": ship_spec_json,
		"all_ship_specs_json": all_ship_specs_json,
	}


# Minimal convenience API (returns ship_id or -1).
static func unpack_welcome(bytes: PackedByteArray) -> int:
	var w: Dictionary = unpack_welcome_packet(bytes)
	if w.is_empty():
		return -1
	return int(w["ship_id"])



static func unpack_snapshot_packet(bytes: PackedByteArray) -> Dictionary:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(0)

	var pkt_type: int = buffer.get_u8()
	if pkt_type != PKT_SNAPSHOT:
		return {}

	var tick: int = buffer.get_32()
	var ship_count: int = buffer.get_u16()
	# Ships (24 bytes each) and the ball block (20) are fixed size and always present.
	# Every trailing section already length-checks itself; this covers the header.
	if buffer.get_available_bytes() < (ship_count * 24 + 20):
		return {}
	var ships: Array = []
	ships.resize(ship_count)

	for i in range(ship_count):
		var id: int = buffer.get_32()
		var px: float = buffer.get_float()
		var py: float = buffer.get_float()
		var vx: float = buffer.get_float()
		var vy: float = buffer.get_float()
		var rot: float = buffer.get_float()

		ships[i] = DriftTypes.DriftShipState.new(id, Vector2(px, py), Vector2(vx, vy), rot)

	# Ball state (always present)
	var ball_px: float = buffer.get_float()
	var ball_py: float = buffer.get_float()
	var ball_vx: float = buffer.get_float()
	var ball_vy: float = buffer.get_float()
	var ball_owner_id: int = buffer.get_32()

	# Bullets extension (optional)
	var bullets: Array = []
	if buffer.get_available_bytes() >= 2:
		var bullet_count: int = int(buffer.get_u16())
		bullets.resize(bullet_count)
		for i in range(bullet_count):
			# Each bullet is 4+4+4*4+4+4 = 32 bytes
			if buffer.get_available_bytes() < 32:
				# Truncated packet; fail loudly by returning empty.
				return {}
			var bid: int = int(buffer.get_32())
			var owner_id: int = int(buffer.get_32())
			var bpx: float = buffer.get_float()
			var bpy: float = buffer.get_float()
			var bvx: float = buffer.get_float()
			var bvy: float = buffer.get_float()
			var spawn_tick: int = int(buffer.get_32())
			var die_tick: int = int(buffer.get_32())
			bullets[i] = DriftTypes.DriftBulletState.new(bid, owner_id, 1, Vector2(bpx, bpy), Vector2(bvx, bvy), spawn_tick, die_tick, 0)

		# Optional bullet extras section.
		if buffer.get_available_bytes() >= 2:
			var extras_count: int = int(buffer.get_u16())
			# Each extra is 4+2 = 6 bytes.
			if buffer.get_available_bytes() < (extras_count * 6):
				return {}
			var by_id: Dictionary = {}
			for b in bullets:
				if b == null:
					continue
				by_id[int(b.id)] = b
			for _i in range(extras_count):
				var ebid: int = int(buffer.get_32())
				var bounces_left: int = int(buffer.get_u16())
				if by_id.has(ebid):
					(by_id[ebid] as DriftTypes.DriftBulletState).bounces_left = bounces_left

			# Optional bullet extras v2 section (level).
			if buffer.get_available_bytes() >= 2:
				var extras2_count: int = int(buffer.get_u16())
				# Each extra2 is 4+1 = 5 bytes.
				if buffer.get_available_bytes() < (extras2_count * 5):
					return {}
				for _j in range(extras2_count):
					var ebid2: int = int(buffer.get_32())
					var level: int = int(buffer.get_u8())
					if by_id.has(ebid2):
						(by_id[ebid2] as DriftTypes.DriftBulletState).level = clampi(level, 1, 4)

	# Optional ship extras section.
	if buffer.get_available_bytes() >= 2:
		var ship_extras_count: int = int(buffer.get_u16())
		# Each entry is 4 + 1 + 1 + 1 + 1 + 4 + 4 = 16 bytes.
		if buffer.get_available_bytes() < (ship_extras_count * 16):
			return {}
		var ship_by_id: Dictionary = {}
		for s in ships:
			if s == null:
				continue
			ship_by_id[int(s.id)] = s
		for _i in range(ship_extras_count):
			var sid: int = int(buffer.get_32())
			var gun_level: int = int(buffer.get_u8())
			var bomb_level: int = int(buffer.get_u8())
			var bullet_bounce_bonus: int = int(buffer.get_u8())
			var flags: int = int(buffer.get_u8())
			var engine_shutdown_until_tick: int = int(buffer.get_32())
			var bounty: int = int(buffer.get_32())
			if ship_by_id.has(sid):
				var ss: DriftTypes.DriftShipState = ship_by_id[sid]
				ss.gun_level = clampi(gun_level, 1, 3)
				ss.bomb_level = clampi(bomb_level, 1, 3)
				ss.bullet_bounce_bonus = clampi(bullet_bounce_bonus, 0, 16)
				ss.multi_fire_enabled = (flags & 1) != 0
				ss.bomb_proximity_enabled = (flags & 2) != 0
				ss.multi_fire_capable = (flags & 4) != 0
				ss.has_stealth = (flags & 8) != 0
				ss.has_cloak = (flags & 16) != 0
				ss.has_xradar = (flags & 32) != 0
				ss.has_antiwarp = (flags & 64) != 0
				ss.engine_shutdown_until_tick = maxi(0, engine_shutdown_until_tick)
				ss.bounty = maxi(0, bounty)

	# Optional prizes section.
	var prizes: Array = []
	if buffer.get_available_bytes() >= 2:
		var prize_count: int = int(buffer.get_u16())
		prizes.resize(prize_count)
		# Each entry is 4 + 4 + 4 + 2 + 4 + 1 = 19 bytes.
		if buffer.get_available_bytes() < (prize_count * 19):
			return {}
		for i in range(prize_count):
			var pid: int = int(buffer.get_32())
			var ppx: float = buffer.get_float()
			var ppy: float = buffer.get_float()
			var kind: int = int(buffer.get_u16())
			var despawn_tick: int = int(buffer.get_32())
			var pflags: int = int(buffer.get_u8())
			var is_negative: bool = (pflags & 1) != 0
			var is_death_drop: bool = (pflags & 2) != 0
			prizes[i] = DriftTypes.DriftPrizeState.new(pid, Vector2(ppx, ppy), 0, despawn_tick, kind, is_negative, is_death_drop)

	# Optional ship extras v2 section.
	if buffer.get_available_bytes() >= 2:
		var ship_extras2_count: int = int(buffer.get_u16())
		# Each entry is 4 + 4 + 1 + 1 + 1 = 11 bytes.
		if buffer.get_available_bytes() < (ship_extras2_count * 11):
			return {}
		var ship_by_id2: Dictionary = {}
		for s2 in ships:
			if s2 == null:
				continue
			ship_by_id2[int(s2.id)] = s2
		for _i in range(ship_extras2_count):
			var sid2: int = int(buffer.get_32())
			var energy: float = buffer.get_float()
			var top_speed_bonus: int = int(buffer.get_u8())
			var thruster_bonus: int = int(buffer.get_u8())
			var recharge_bonus: int = int(buffer.get_u8())
			if ship_by_id2.has(sid2):
				var ss2: DriftTypes.DriftShipState = ship_by_id2[sid2]
				# Legacy mirror (ship_extras_v2) is float on the wire.
				ss2.energy = maxi(0, int(round(energy)))
				ss2.top_speed_bonus = clampi(top_speed_bonus, 0, 16)
				ss2.thruster_bonus = clampi(thruster_bonus, 0, 16)
				ss2.recharge_bonus = clampi(recharge_bonus, 0, 16)

	# Optional ship energy v3 section.
	if buffer.get_available_bytes() >= 2:
		var ship_energy3_count: int = int(buffer.get_u16())
		# Each entry is 4 + 4 + 4 + 4 + 2 + 2 + 2 + 2 = 24 bytes.
		if buffer.get_available_bytes() < (ship_energy3_count * 24):
			return {}
		var ship_by_id3: Dictionary = {}
		for s3 in ships:
			if s3 == null:
				continue
			ship_by_id3[int(s3.id)] = s3
		for _i in range(ship_energy3_count):
			var sid3: int = int(buffer.get_32())
			var energy_current: int = int(buffer.get_32())
			var energy_max: int = int(buffer.get_32())
			var recharge_rate_per_sec: int = int(buffer.get_32())
			var recharge_delay_ticks: int = int(buffer.get_u16())
			var recharge_wait_ticks: int = int(buffer.get_u16())
			var recharge_fp_accum: int = int(buffer.get_u16())
			var drain_fp_accum: int = int(buffer.get_u16())
			if ship_by_id3.has(sid3):
				var ss3: DriftTypes.DriftShipState = ship_by_id3[sid3]
				ss3.energy_current = maxi(0, energy_current)
				ss3.energy_max = maxi(0, energy_max)
				ss3.energy_recharge_rate_per_sec = maxi(0, recharge_rate_per_sec)
				ss3.energy_recharge_delay_ticks = maxi(0, recharge_delay_ticks)
				ss3.energy_recharge_wait_ticks = maxi(0, recharge_wait_ticks)
				ss3.energy_recharge_fp_accum = maxi(0, recharge_fp_accum)
				ss3.energy_drain_fp_accum = maxi(0, drain_fp_accum)
				# Keep legacy mirror consistent.
				ss3.energy = int(ss3.energy_current)

	# Optional prize events section.
	var prize_events: Array = []
	if buffer.get_available_bytes() >= 2:
		var ev_count: int = int(buffer.get_u16())
		# Each event is 1 + 4 + 4 = 9 bytes.
		if buffer.get_available_bytes() < (ev_count * 9):
			return {}
		for _i in range(ev_count):
			var et: int = int(buffer.get_u8())
			var sid: int = int(buffer.get_32())
			var pid: int = int(buffer.get_32())
			if et == 1:
				prize_events.append({"type": "pickup", "ship_id": sid, "prize_id": pid})

	# Optional ship abilities v1 section.
	if buffer.get_available_bytes() >= 2:
		var ship_abilities_count: int = int(buffer.get_u16())
		# Each entry is 4 + 1 = 5 bytes.
		if buffer.get_available_bytes() < (ship_abilities_count * 5):
			return {}
		var ship_by_id4: Dictionary = {}
		for s4 in ships:
			if s4 == null:
				continue
			ship_by_id4[int(s4.id)] = s4
		for _i in range(ship_abilities_count):
			var sid4: int = int(buffer.get_32())
			var flags4: int = int(buffer.get_u8())
			if ship_by_id4.has(sid4):
				var ss4: DriftTypes.DriftShipState = ship_by_id4[sid4]
				ss4.stealth_on = (flags4 & 1) != 0
				ss4.cloak_on = (flags4 & 2) != 0
				ss4.xradar_on = (flags4 & 4) != 0
				ss4.antiwarp_on = (flags4 & 8) != 0
				ss4.in_safe_zone = (flags4 & 16) != 0

	# Optional ship damage v1 section.
	if buffer.get_available_bytes() >= 2:
		var ship_damage_count: int = int(buffer.get_u16())
		# Each entry is 4 + 4 = 8 bytes.
		if buffer.get_available_bytes() < (ship_damage_count * 8):
			return {}
		var ship_by_id5: Dictionary = {}
		for s5 in ships:
			if s5 == null:
				continue
			ship_by_id5[int(s5.id)] = s5
		for _i in range(ship_damage_count):
			var sid5: int = int(buffer.get_32())
			var protect_until: int = int(buffer.get_32())
			if ship_by_id5.has(sid5):
				var ss5: DriftTypes.DriftShipState = ship_by_id5[sid5]
				ss5.damage_protect_until_tick = maxi(0, protect_until)

	# Optional ship death v1 section.
	if buffer.get_available_bytes() >= 2:
		var ship_death_count: int = int(buffer.get_u16())
		# Each entry is 4 + 4 = 8 bytes.
		if buffer.get_available_bytes() < (ship_death_count * 8):
			return {}
		var ship_by_id6: Dictionary = {}
		for s6 in ships:
			if s6 == null:
				continue
			ship_by_id6[int(s6.id)] = s6
		for _k in range(ship_death_count):
			var sid6: int = int(buffer.get_32())
			var dead_until: int = int(buffer.get_32())
			if ship_by_id6.has(sid6):
				var ss6: DriftTypes.DriftShipState = ship_by_id6[sid6]
				ss6.dead_until_tick = maxi(0, dead_until)

	# Optional ship safe-zone timer v1 section.
	if buffer.get_available_bytes() >= 2:
		var ship_sz_count: int = int(buffer.get_u16())
		# Each entry is 4 + 4 + 4 = 12 bytes.
		if buffer.get_available_bytes() < (ship_sz_count * 12):
			return {}
		var ship_by_id7: Dictionary = {}
		for s7 in ships:
			if s7 == null:
				continue
			ship_by_id7[int(s7.id)] = s7
		for _m in range(ship_sz_count):
			var sid7: int = int(buffer.get_32())
			var used_ticks: int = int(buffer.get_32())
			var max_ticks: int = int(buffer.get_32())
			if ship_by_id7.has(sid7):
				var ss7: DriftTypes.DriftShipState = ship_by_id7[sid7]
				ss7.safe_zone_time_used_ticks = maxi(0, used_ticks)
				ss7.safe_zone_time_max_ticks = maxi(0, max_ticks)

	# Optional ship freq v1 section.
	if buffer.get_available_bytes() >= 2:
		var ship_freq_count: int = int(buffer.get_u16())
		# Each entry is 4 + 2 = 6 bytes.
		if buffer.get_available_bytes() < (ship_freq_count * 6):
			return {}
		var ship_by_id8: Dictionary = {}
		for s8 in ships:
			if s8 == null:
				continue
			ship_by_id8[int(s8.id)] = s8
		for _n in range(ship_freq_count):
			var sid8: int = int(buffer.get_32())
			var freq: int = int(buffer.get_u16())
			if ship_by_id8.has(sid8):
				var ss8: DriftTypes.DriftShipState = ship_by_id8[sid8]
				ss8.freq = maxi(0, freq)

	# Optional ship weapon cooldown v1 section.
	if buffer.get_available_bytes() >= 2:
		var ship_cd_count: int = int(buffer.get_u16())
		# Each entry is 4 + 4 = 8 bytes.
		if buffer.get_available_bytes() < (ship_cd_count * 8):
			return {}
		var ship_by_id9: Dictionary = {}
		for s9 in ships:
			if s9 == null:
				continue
			ship_by_id9[int(s9.id)] = s9
		for _p in range(ship_cd_count):
			var sid9: int = int(buffer.get_32())
			var next_tick: int = int(buffer.get_32())
			if ship_by_id9.has(sid9):
				var ss9: DriftTypes.DriftShipState = ship_by_id9[sid9]
				ss9.next_bullet_tick = maxi(0, next_tick)

	# Optional ship weapon cooldown v2 section (bomb + mine).
	if buffer.get_available_bytes() >= 2:
		var ship_cd2_count: int = int(buffer.get_u16())
		# Each entry is 4 + 4 + 4 = 12 bytes.
		if buffer.get_available_bytes() < (ship_cd2_count * 12):
			return {}
		var ship_by_id10: Dictionary = {}
		for s10 in ships:
			if s10 == null:
				continue
			ship_by_id10[int(s10.id)] = s10
		for _q in range(ship_cd2_count):
			var sid10: int = int(buffer.get_32())
			var next_bomb: int = int(buffer.get_32())
			var next_mine: int = int(buffer.get_32())
			if ship_by_id10.has(sid10):
				var ss10: DriftTypes.DriftShipState = ship_by_id10[sid10]
				ss10.next_bomb_tick = maxi(0, next_bomb)
				ss10.next_mine_tick = maxi(0, next_mine)

	# Optional bombs list.
	var bombs: Array = []
	if buffer.get_available_bytes() >= 2:
		var bomb_count: int = int(buffer.get_u16())
		# Each entry is 36 bytes.
		if buffer.get_available_bytes() < (bomb_count * 36):
			return {}
		for _i2 in range(bomb_count):
			var bid: int = int(buffer.get_32())
			var owner_id: int = int(buffer.get_32())
			var px: float = float(buffer.get_float())
			var py: float = float(buffer.get_float())
			var vx: float = float(buffer.get_float())
			var vy: float = float(buffer.get_float())
			var spawn_tick: int = int(buffer.get_32())
			var die_tick: int = int(buffer.get_32())
			var bounces_left: int = int(buffer.get_u16())
			var level: int = int(buffer.get_u8())
			var flags: int = int(buffer.get_u8())
			var is_emp: bool = (flags & 1) != 0
			bombs.append(DriftTypes.DriftBombState.new(bid, owner_id, level, Vector2(px, py), Vector2(vx, vy), spawn_tick, die_tick, bounces_left, is_emp))

	# Optional mines list.
	var mines: Array = []
	if buffer.get_available_bytes() >= 2:
		var mine_count: int = int(buffer.get_u16())
		# Each entry is 34 bytes.
		if buffer.get_available_bytes() < (mine_count * 34):
			return {}
		for _j2 in range(mine_count):
			var mid: int = int(buffer.get_32())
			var owner_id2: int = int(buffer.get_32())
			var px2: float = float(buffer.get_float())
			var py2: float = float(buffer.get_float())
			var spawn_tick2: int = int(buffer.get_32())
			var die_tick2: int = int(buffer.get_32())
			var level2: int = int(buffer.get_u8())
			var flags2: int = int(buffer.get_u8())
			var triggered: bool = (flags2 & 1) != 0
			var triggered_by: int = int(buffer.get_32())
			var triggered_tick: int = int(buffer.get_32())
			mines.append(DriftTypes.DriftMineState.new(mid, owner_id2, level2, Vector2(px2, py2), spawn_tick2, die_tick2, triggered, triggered_by, triggered_tick))

	# Optional ship type v1 section.
	if buffer.get_available_bytes() >= 2:
		var ship_type_count: int = int(buffer.get_u16())
		# Each entry is 4 + 1 = 5 bytes.
		if buffer.get_available_bytes() < (ship_type_count * 5):
			return {}
		var ship_by_id_st: Dictionary = {}
		for sst in ships:
			if sst == null:
				continue
			ship_by_id_st[int(sst.id)] = sst
		for _st in range(ship_type_count):
			var sid_st: int = int(buffer.get_32())
			var st_val: int = int(buffer.get_u8())
			if ship_by_id_st.has(sid_st):
				var ss_st: DriftTypes.DriftShipState = ship_by_id_st[sid_st]
				ss_st.ship_type = clampi(st_val, 0, 7)

	# Optional ship items v1 section.
	if buffer.get_available_bytes() >= 2:
		var items_count: int = int(buffer.get_u16())
		# Each entry is 4 + 1 + 1 + 1 + 4 + 1 = 12 bytes.
		if buffer.get_available_bytes() >= (items_count * 12):
			var ship_by_id_it: Dictionary = {}
			for sit in ships:
				if sit == null:
					continue
				ship_by_id_it[int(sit.id)] = sit
			for _it in range(items_count):
				var sid_it: int = int(buffer.get_32())
				var rc: int = int(buffer.get_u8())
				var bc: int = int(buffer.get_u8())
				var wc: int = int(buffer.get_u8())
				var sut: int = int(buffer.get_32())
				var ss: bool = buffer.get_u8() != 0
				if ship_by_id_it.has(sid_it):
					var ss_it: DriftTypes.DriftShipState = ship_by_id_it[sid_it]
					ss_it.repel_count = rc
					ss_it.burst_count = bc
					ss_it.warp_count = wc
					ss_it.shields_until_tick = sut
					ss_it.super_shields = ss

	# Optional ship stats v1 section (kills, deaths).
	if buffer.get_available_bytes() >= 2:
		var stats_count: int = int(buffer.get_u16())
		# Each entry is 4 + 2 + 2 = 8 bytes.
		if buffer.get_available_bytes() >= (stats_count * 8):
			var ship_by_id_stats: Dictionary = {}
			for sst2 in ships:
				if sst2 == null:
					continue
				ship_by_id_stats[int(sst2.id)] = sst2
			for _st2 in range(stats_count):
				var sid_st2: int = int(buffer.get_32())
				var k: int = int(buffer.get_u16())
				var d: int = int(buffer.get_u16())
				if ship_by_id_stats.has(sid_st2):
					var ss_st2: DriftTypes.DriftShipState = ship_by_id_stats[sid_st2]
					ss_st2.kills = k
					ss_st2.deaths = d

	# Optional ship CTF v1 section (carried_flag_team).
	var ship_by_id_ctf: Dictionary = {}
	for sctf in ships:
		if sctf != null:
			ship_by_id_ctf[int(sctf.id)] = sctf
	if buffer.get_available_bytes() >= 2:
		var ctf_count: int = int(buffer.get_u16())
		# Each entry is 4 + 1 = 5 bytes.
		if buffer.get_available_bytes() >= (ctf_count * 5):
			for _ctf in range(ctf_count):
				var sid_ctf: int = int(buffer.get_32())
				var cft_raw: int = int(buffer.get_u8())
				var cft: int = cft_raw if cft_raw != 0xFF else -1
				if ship_by_id_ctf.has(sid_ctf):
					ship_by_id_ctf[sid_ctf].carried_flag_team = cft

	# Optional flag state v1 section.
	var flags: Array = []
	if buffer.get_available_bytes() >= 2:
		var flag_count: int = int(buffer.get_u16())
		# Each entry is 1 + 8 + 4 + 1 + 4 = 18 bytes.
		if buffer.get_available_bytes() >= (flag_count * 18):
			for _fi in range(flag_count):
				var fteam: int = int(buffer.get_u8())
				var fpx: float = buffer.get_float()
				var fpy: float = buffer.get_float()
				var fcarrier: int = buffer.get_32()   # -1 = not carried
				var fflags: int = int(buffer.get_u8())
				var fdrop: int = buffer.get_32()       # -1 = not dropped
				var fs := DriftTypes.DriftFlagState.new(fteam, Vector2(fpx, fpy))
				fs.carrier_ship_id = fcarrier
				fs.at_home = (fflags & 1) != 0
				fs.drop_tick = fdrop
				flags.append(fs)

	# Build a flat id→ship lookup for the trailing sections below.
	var ships_by_id: Dictionary = {}
	for _slu in ships:
		ships_by_id[int(_slu.id)] = _slu

	# Optional ship_items_v2 section (thor_count, rocket_count, decoy_count, brick_count, portal_count).
	if buffer.get_available_bytes() >= 2:
		var si2_count: int = int(buffer.get_u16())
		if buffer.get_available_bytes() >= (si2_count * 9):
			for _si2i in range(si2_count):
				var si2_id: int = int(buffer.get_32())
				var si2_thor: int = int(buffer.get_u8())
				var si2_rock: int = int(buffer.get_u8())
				var si2_dec: int = int(buffer.get_u8())
				var si2_brk: int = int(buffer.get_u8())
				var si2_por: int = int(buffer.get_u8())
				if ships_by_id.has(si2_id):
					ships_by_id[si2_id].thor_count = clampi(si2_thor, 0, 255)
					ships_by_id[si2_id].rocket_count = clampi(si2_rock, 0, 255)
					ships_by_id[si2_id].decoy_count = clampi(si2_dec, 0, 255)
					ships_by_id[si2_id].brick_count = clampi(si2_brk, 0, 255)
					ships_by_id[si2_id].portal_count = clampi(si2_por, 0, 255)

	# Optional ship_upgrades_v2 section.
	if buffer.get_available_bytes() >= 2:
		var su2_count: int = int(buffer.get_u16())
		if buffer.get_available_bytes() >= (su2_count * 10):
			for _su2i in range(su2_count):
				var su2_id: int = int(buffer.get_32())
				var su2_rot: int = int(buffer.get_u8())
				var su2_shrap: int = int(buffer.get_u8())
				var su2_rocket_tick: int = int(buffer.get_32())
				if ships_by_id.has(su2_id):
					ships_by_id[su2_id].rotation_bonus = clampi(su2_rot, 0, 16)
					ships_by_id[su2_id].shrapnel_bonus = clampi(su2_shrap, 0, 16)
					ships_by_id[su2_id].rocket_boost_until_tick = maxi(0, su2_rocket_tick)

	# Optional radar_ships_v1 section.
	var radar_ships: Array = []
	if buffer.get_available_bytes() >= 2:
		var rs_count: int = int(buffer.get_u16())
		if buffer.get_available_bytes() >= (rs_count * 14):
			for _ri in range(rs_count):
				var rs_id: int = int(buffer.get_u32())
				var rs_px: float = buffer.get_float()
				var rs_py: float = buffer.get_float()
				var rs_freq: int = int(buffer.get_u8())
				var rs_flags: int = int(buffer.get_u8())
				radar_ships.append({
					"id": rs_id,
					"position": Vector2(rs_px, rs_py),
					"freq": rs_freq,
					"dead": (rs_flags & 1) != 0,
				})

	# Optional decoys section.
	var decoys: Array = []
	# Each decoy: 4+4+1+1+4+4+4+4+4+4 = 34 bytes
	if buffer.get_available_bytes() >= 2:
		var dc_count: int = int(buffer.get_u16())
		if buffer.get_available_bytes() >= (dc_count * 34):
			for _dci in range(dc_count):
				var dc_id: int = int(buffer.get_32())
				var dc_owner: int = int(buffer.get_32())
				var dc_freq: int = int(buffer.get_u8())
				var dc_type: int = int(buffer.get_u8())
				var dc_px: float = buffer.get_float()
				var dc_py: float = buffer.get_float()
				var dc_vx: float = buffer.get_float()
				var dc_vy: float = buffer.get_float()
				var dc_rot: float = buffer.get_float()
				var dc_die: int = int(buffer.get_32())
				decoys.append(DriftTypes.DriftDecoyState.new(dc_id, dc_owner, dc_freq, dc_type, Vector2(dc_px, dc_py), Vector2(dc_vx, dc_vy), dc_rot, dc_die))

	# Optional bricks section.
	var bricks: Array = []
	if buffer.get_available_bytes() >= 2:
		var br_count: int = int(buffer.get_u16())
		for _bri in range(br_count):
			if buffer.get_available_bytes() < 7:
				break
			var br_die: int = int(buffer.get_32())
			var br_freq: int = int(buffer.get_u8())
			var br_tile_count: int = int(buffer.get_u16())
			var br_tiles: Array[Vector2i] = []
			for _ti in range(br_tile_count):
				if buffer.get_available_bytes() < 4:
					break
				var tx: int = buffer.get_16()
				var ty: int = buffer.get_16()
				br_tiles.append(Vector2i(tx, ty))
			bricks.append({"die_tick": br_die, "freq": br_freq, "tiles": br_tiles})

	# Optional effect events section.
	var effect_events: Array = []
	if buffer.get_available_bytes() >= 2:
		var ee_count: int = int(buffer.get_u16())
		if buffer.get_available_bytes() >= (ee_count * 11):
			for _eei in range(ee_count):
				var ee_type_byte: int = int(buffer.get_u8())
				var ee_ship_id: int = int(buffer.get_32())
				var ee_px: float = buffer.get_float()
				var ee_py: float = buffer.get_float()
				var ee_type: StringName
				match ee_type_byte:
					0: ee_type = &"repel"
					1: ee_type = &"warp"
					2: ee_type = &"thor"
					_: ee_type = &""
				effect_events.append({"type": ee_type, "ship_id": ee_ship_id, "px": ee_px, "py": ee_py})

	# King ship trailing section.
	var king_ship_id: int = -1
	if buffer.get_available_bytes() >= 4:
		king_ship_id = int(buffer.get_32())

	# Optional ship points v1 section.
	if buffer.get_available_bytes() >= 2:
		var pts_count: int = int(buffer.get_u16())
		if buffer.get_available_bytes() >= (pts_count * 8):
			for _pi in range(pts_count):
				var pts_id: int = int(buffer.get_32())
				var pts_val: int = int(buffer.get_u32())
				if ships_by_id.has(pts_id):
					ships_by_id[pts_id].points = pts_val

	# Optional King of the Hill v1 section.
	if buffer.get_available_bytes() >= 2:
		var king_count: int = int(buffer.get_u16())
		if buffer.get_available_bytes() >= (king_count * 9):
			for _ki in range(king_count):
				var k_id: int = int(buffer.get_32())
				var k_on: bool = buffer.get_u8() != 0
				var k_ticks: int = int(buffer.get_u32())
				if ships_by_id.has(k_id):
					ships_by_id[k_id].crown_on = k_on
					ships_by_id[k_id].crown_ticks_left = k_ticks

	return {
		"type": pkt_type,
		"tick": tick,
		"ships": ships,
		"ball_position": Vector2(ball_px, ball_py),
		"ball_velocity": Vector2(ball_vx, ball_vy),
		"ball_owner_id": ball_owner_id,
		"bullets": bullets,
		"bombs": bombs,
		"mines": mines,
		"prizes": prizes,
		"prize_events": prize_events,
		"flags": flags,
		"radar_ships": radar_ships,
		"decoys": decoys,
		"bricks": bricks,
		"effect_events": effect_events,
		"king_ship_id": king_ship_id,
	}


static func snapshot_ships_from_dict(ships_dict: Dictionary) -> Array:
	# Deterministic conversion: sort by ship id.
	var ids: Array = ships_dict.keys()
	ids.sort()
	var ships: Array = []
	ships.resize(ids.size())

	for i in range(ids.size()):
		ships[i] = ships_dict[ids[i]]

	return ships


# --- Kill Event (server -> client, reliable) ---

static func pack_kill_event(attacker_id: int, victim_id: int, weapon_type: int, attacker_name: String, victim_name: String, reward: int = 0) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.seek(0)
	buffer.put_u8(PKT_KILL_EVENT)
	buffer.put_32(attacker_id)
	buffer.put_32(victim_id)
	buffer.put_u8(weapon_type)
	var aname: PackedByteArray = attacker_name.to_utf8_buffer()
	buffer.put_u8(mini(aname.size(), 255))
	if aname.size() > 0:
		buffer.put_data(aname.slice(0, mini(aname.size(), 255)))
	var vname: PackedByteArray = victim_name.to_utf8_buffer()
	buffer.put_u8(mini(vname.size(), 255))
	if vname.size() > 0:
		buffer.put_data(vname.slice(0, mini(vname.size(), 255)))
	# Trailing (append-only): u32 kill reward points.
	buffer.put_u32(maxi(0, int(reward)))
	return buffer.data_array


static func unpack_kill_event(bytes: PackedByteArray) -> Dictionary:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(0)
	if buffer.get_u8() != PKT_KILL_EVENT:
		return {}
	if buffer.get_available_bytes() < 9:
		return {}
	var attacker_id: int = buffer.get_32()
	var victim_id: int = buffer.get_32()
	var weapon_type: int = buffer.get_u8()
	var attacker_name: String = ""
	var victim_name: String = ""
	if buffer.get_available_bytes() >= 1:
		var alen: int = buffer.get_u8()
		if alen > 0 and buffer.get_available_bytes() >= alen:
			attacker_name = buffer.get_data(alen)[1].get_string_from_utf8()
	if buffer.get_available_bytes() >= 1:
		var vlen: int = buffer.get_u8()
		if vlen > 0 and buffer.get_available_bytes() >= vlen:
			victim_name = buffer.get_data(vlen)[1].get_string_from_utf8()
	var reward: int = 0
	if buffer.get_available_bytes() >= 4:
		reward = int(buffer.get_u32())
	return {"attacker_id": attacker_id, "victim_id": victim_id, "weapon_type": weapon_type, "attacker_name": attacker_name, "victim_name": victim_name, "reward": reward}


# --- Chat Message (client -> server, reliable) ---

const CHAT_TYPE_PUBLIC: int = 0
const CHAT_TYPE_TEAM: int = 1
const CHAT_TYPE_PRIVATE: int = 2
const CHAT_TYPE_ARENA: int = 3

static func pack_chat_message(ship_id: int, chat_type: int, text: String, target_name: String = "") -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.seek(0)
	buffer.put_u8(PKT_CHAT_MESSAGE)
	buffer.put_32(ship_id)
	buffer.put_u8(chat_type)
	var txt: PackedByteArray = text.to_utf8_buffer()
	buffer.put_u16(mini(txt.size(), 1000))
	if txt.size() > 0:
		buffer.put_data(txt.slice(0, mini(txt.size(), 1000)))
	var tgt: PackedByteArray = target_name.to_utf8_buffer()
	buffer.put_u8(mini(tgt.size(), 255))
	if tgt.size() > 0:
		buffer.put_data(tgt.slice(0, mini(tgt.size(), 255)))
	return buffer.data_array


static func unpack_chat_message(bytes: PackedByteArray) -> Dictionary:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(0)
	if buffer.get_u8() != PKT_CHAT_MESSAGE:
		return {}
	if buffer.get_available_bytes() < 7:
		return {}
	var ship_id: int = buffer.get_32()
	var chat_type: int = buffer.get_u8()
	var txt_len: int = buffer.get_u16()
	var text: String = ""
	if txt_len > 0 and buffer.get_available_bytes() >= txt_len:
		text = buffer.get_data(txt_len)[1].get_string_from_utf8()
	var target_name: String = ""
	if buffer.get_available_bytes() >= 1:
		var tlen: int = buffer.get_u8()
		if tlen > 0 and buffer.get_available_bytes() >= tlen:
			target_name = buffer.get_data(tlen)[1].get_string_from_utf8()
	return {"ship_id": ship_id, "chat_type": chat_type, "text": text, "target_name": target_name}


# --- Chat Broadcast (server -> client, reliable) ---

static func pack_chat_broadcast(sender_name: String, chat_type: int, text: String, sender_freq: int = 0) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.seek(0)
	buffer.put_u8(PKT_CHAT_BROADCAST)
	buffer.put_u8(chat_type)
	buffer.put_u16(sender_freq)
	var name_bytes: PackedByteArray = sender_name.to_utf8_buffer()
	buffer.put_u8(mini(name_bytes.size(), 255))
	if name_bytes.size() > 0:
		buffer.put_data(name_bytes.slice(0, mini(name_bytes.size(), 255)))
	var txt: PackedByteArray = text.to_utf8_buffer()
	buffer.put_u16(mini(txt.size(), 1000))
	if txt.size() > 0:
		buffer.put_data(txt.slice(0, mini(txt.size(), 1000)))
	return buffer.data_array


static func unpack_chat_broadcast(bytes: PackedByteArray) -> Dictionary:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(0)
	if buffer.get_u8() != PKT_CHAT_BROADCAST:
		return {}
	if buffer.get_available_bytes() < 4:
		return {}
	var chat_type: int = buffer.get_u8()
	var sender_freq: int = buffer.get_u16()
	var nlen: int = buffer.get_u8()
	var sender_name: String = ""
	if nlen > 0 and buffer.get_available_bytes() >= nlen:
		sender_name = buffer.get_data(nlen)[1].get_string_from_utf8()
	var text: String = ""
	if buffer.get_available_bytes() >= 2:
		var tlen: int = buffer.get_u16()
		if tlen > 0 and buffer.get_available_bytes() >= tlen:
			text = buffer.get_data(tlen)[1].get_string_from_utf8()
	return {"sender_name": sender_name, "chat_type": chat_type, "text": text, "sender_freq": sender_freq}


# --- Score Event (server -> client, reliable) ---
# scoring_team: 0 = state sync/reset, 1 or 2 = team that just scored.
# flags bit0 = match_over, bit1 = match_reset.

static func pack_score_event(team1_score: int, team2_score: int, scoring_team: int, match_over: bool = false, match_reset: bool = false, winner_team: int = 0) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.seek(0)
	buffer.put_u8(PKT_SCORE_EVENT)
	buffer.put_u16(clampi(team1_score, 0, 65535))
	buffer.put_u16(clampi(team2_score, 0, 65535))
	buffer.put_u8(clampi(scoring_team, 0, 255))
	var flags: int = 0
	if match_over:
		flags |= 1
	if match_reset:
		flags |= 2
	buffer.put_u8(flags)
	buffer.put_u8(clampi(winner_team, 0, 255))
	return buffer.data_array


static func unpack_score_event(bytes: PackedByteArray) -> Dictionary:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(0)
	if buffer.get_u8() != PKT_SCORE_EVENT:
		return {}
	if buffer.get_available_bytes() < 7:
		return {}
	var t1: int = buffer.get_u16()
	var t2: int = buffer.get_u16()
	var scorer: int = buffer.get_u8()
	var flags: int = buffer.get_u8()
	var winner: int = buffer.get_u8()
	return {
		"team1_score": t1,
		"team2_score": t2,
		"scoring_team": scorer,
		"match_over": (flags & 1) != 0,
		"match_reset": (flags & 2) != 0,
		"winner_team": winner,
	}
