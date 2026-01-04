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
	var length = buffer.get_u16()
	var data = buffer.get_data(length)
	return data.get_string_from_utf8()


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

	return buffer.data_array


static func unpack_input_packet(bytes: PackedByteArray) -> Dictionary:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	buffer.seek(0)

	var pkt_type: int = buffer.get_u8()
	if pkt_type != PKT_INPUT:
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
	}



# Extended: ships + ball (+ optional bullets)
static func pack_snapshot_packet(
	tick: int,
	ships: Array,
	ball_pos: Vector2 = Vector2.ZERO,
	ball_vel: Vector2 = Vector2.ZERO,
	ball_owner_id: int = -1,
	bullets: Array = [],
	prizes: Array = [],
	prize_events: Array = [],
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
	#     u8 flags (bit0=multi_fire_enabled)
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
		buffer.put_u8(int(clampi(int(b2.level), 1, 3)))

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
		buffer.put_float(float(s2.energy))
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

	return buffer.data_array


static func pack_welcome_packet(
	ship_id: int,
	map_checksum: PackedByteArray = PackedByteArray(),
	map_path: String = "",
	map_version: int = 0,
	wall_restitution: float = -1.0,
	ruleset_json: String = "",
	tangent_damping: float = -1.0,
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
	return {
		"type": pkt_type,
		"ship_id": ship_id,
		"map_checksum": checksum,
		"map_path": map_path,
		"map_version": map_version,
		"wall_restitution": wall_restitution,
		"ruleset_json": ruleset_json,
		"tangent_damping": tangent_damping,
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
						(by_id[ebid2] as DriftTypes.DriftBulletState).level = clampi(level, 1, 3)

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
				ss2.energy = maxf(0.0, energy)
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
				ss3.energy = float(ss3.energy_current)

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

	return {
		"type": pkt_type,
		"tick": tick,
		"ships": ships,
		"ball_position": Vector2(ball_px, ball_py),
		"ball_velocity": Vector2(ball_vx, ball_vy),
		"ball_owner_id": ball_owner_id,
		"bullets": bullets,
		"prizes": prizes,
		"prize_events": prize_events,
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
