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
	if buffer.get_available_bytes() >= 1:
		fire_secondary = buffer.get_u8() != 0
	if buffer.get_available_bytes() >= 1:
		modifier = buffer.get_u8() != 0
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
	}



# Extended: ships + ball (+ optional bullets)
static func pack_snapshot_packet(
	tick: int,
	ships: Array,
	ball_pos: Vector2 = Vector2.ZERO,
	ball_vel: Vector2 = Vector2.ZERO,
	ball_owner_id: int = -1,
	bullets: Array = [],
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
			bullets[i] = DriftTypes.DriftBulletState.new(bid, owner_id, Vector2(bpx, bpy), Vector2(bvx, bvy), spawn_tick, die_tick)

	return {
		"type": pkt_type,
		"tick": tick,
		"ships": ships,
		"ball_position": Vector2(ball_px, ball_py),
		"ball_velocity": Vector2(ball_vx, ball_vy),
		"ball_owner_id": ball_owner_id,
		"bullets": bullets,
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
