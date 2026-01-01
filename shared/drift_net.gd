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
	buffer.put_u8(1 if cmd.thrust else 0)
	buffer.put_u8(1 if cmd.reverse else 0)
	buffer.put_float(cmd.turn)
	buffer.put_u8(1 if cmd.fire else 0)

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
	var thrust: bool = buffer.get_u8() != 0
	var reverse: bool = buffer.get_u8() != 0
	var turn: float = buffer.get_float()
	var fire: bool = buffer.get_u8() != 0

	return {
		"type": pkt_type,
		"tick": tick,
		"ship_id": ship_id,
		"thrust": thrust,
		"reverse": reverse,
		"turn": turn,
		"fire": fire,
	}



# Extended: ships + ball
static func pack_snapshot_packet(tick: int, ships: Array, ball_pos: Vector2 = Vector2.ZERO, ball_vel: Vector2 = Vector2.ZERO, ball_owner_id: int = -1) -> PackedByteArray:
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

	return buffer.data_array


static func pack_welcome_packet(ship_id: int, map_checksum: PackedByteArray = PackedByteArray(), map_path: String = "", map_version: int = 0) -> PackedByteArray:
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
	return {
		"type": pkt_type,
		"ship_id": ship_id,
		"map_checksum": checksum,
		"map_path": map_path,
		"map_version": map_version,
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

	return {
		"type": pkt_type,
		"tick": tick,
		"ships": ships,
		"ball_position": Vector2(ball_px, ball_py),
		"ball_velocity": Vector2(ball_vx, ball_vy),
		"ball_owner_id": ball_owner_id,
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
