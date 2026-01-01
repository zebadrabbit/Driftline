## Driftline server bootstrap (headless).
##
## Run with:
##   godot --headless --script res://server/server_main.gd
##
## Responsibilities:
## - Run a fixed 60 Hz simulation tick loop using an accumulator
## - Run ENet authoritative simulation at 60Hz
## - Receive tick-tagged input packets and apply to simulation
## - Broadcast periodic authoritative snapshots

extends SceneTree

const DriftWorld = preload("res://shared/drift_world.gd")
const DriftTypes = preload("res://shared/drift_types.gd")
const DriftConstants = preload("res://shared/drift_constants.gd")
const DriftNet = preload("res://shared/drift_net.gd")
const DriftMap = preload("res://shared/drift_map.gd")
const DriftTileDefs = preload("res://shared/drift_tile_defs.gd")

const SERVER_PORT: int = 5000
const MAX_CLIENTS: int = 8

const DEBUG_NET: bool = false

var alive_timer := 0.0
var last_printed_tick := -1
var inputs_this_second := 0
var inputs_timer := 0.0


# Use a non-zero channel so Godot's high-level multiplayer (RPC/scene cache)
# does not try to parse our custom packets.
const NET_CHANNEL: int = 1

const SPAWN_POSITION: Vector2 = Vector2(512.0, 512.0)
const SNAPSHOT_INTERVAL_TICKS: int = 6

const QUIT_FLAG_PATH := "user://server.quit"
const QUIT_POLL_INTERVAL_SECONDS: float = 0.25


var world: DriftWorld
var accumulator_seconds: float = 0.0
var latest_snapshot: DriftTypes.DriftWorldSnapshot

var enet_peer: ENetMultiplayerPeer
var next_ship_id: int = 1

var map_checksum: PackedByteArray = PackedByteArray()
var map_entities: Array = []
var map_path: String = ""
var map_version: int = 0

var quit_flag_path: String = QUIT_FLAG_PATH
var quit_after_seconds: float = -1.0
var runtime_seconds: float = 0.0
var shutdown_requested: bool = false

var quit_poll_accumulator_seconds: float = 0.0

# tick -> Dictionary[ship_id, DriftInputCmd]
var inputs_by_tick: Dictionary = {} # Dictionary[int, Dictionary]

# peer_id -> ship_id
var ship_id_by_peer: Dictionary = {} # Dictionary[int, int]

# ship_id -> last known input (fallback when packets are missing)
var last_cmd_by_ship: Dictionary = {} # Dictionary[int, DriftTypes.DriftInputCmd]


func _initialize() -> void:
	_parse_user_args()

	# Set up networking.
	enet_peer = ENetMultiplayerPeer.new()
	var err: int = enet_peer.create_server(SERVER_PORT, MAX_CLIENTS)
	if err != OK:
		push_error("Failed to start ENet server on port %d (err=%d)" % [SERVER_PORT, err])
		# If the port is already in use (e.g., another server instance is running),
		# SceneTree.quit() still allows one more _process() before exiting.
		# Ensure we don't poll an inactive ENet peer in that final frame.
		shutdown_requested = true
		if enet_peer != null:
			enet_peer.close()
			enet_peer = null
		quit()
		return

	# IMPORTANT:
	# Do NOT assign this peer to SceneMultiplayer (multiplayer.multiplayer_peer).
	# We are using raw custom packets, not Godot RPC replication.
	# Assigning it triggers SceneMultiplayer to parse packets and spam:
	#   "Invalid packet received. Size too small."
	enet_peer.peer_connected.connect(_on_peer_connected)
	enet_peer.peer_disconnected.connect(_on_peer_disconnected)

	world = DriftWorld.new()
	if not _load_selected_map_from_config():
		# Map parse/validation failure is fatal.
		_request_shutdown("map_load_failed")
		quit()
		return
	latest_snapshot = DriftTypes.DriftWorldSnapshot.new(0, {})

	print("Driftline server listening on port ", SERVER_PORT)
	print("Soft stop: create ", quit_flag_path, " to quit")
	print("Soft stop path (absolute): ", ProjectSettings.globalize_path(quit_flag_path))
	if quit_after_seconds > 0.0:
		print("Soft stop: will quit after ", quit_after_seconds, " seconds")


func _finalize() -> void:
	# Best-effort cleanup so headless exits don't look like crashes.
	shutdown_requested = true
	if enet_peer != null:
		enet_peer.close()
		enet_peer = null
	inputs_by_tick.clear()
	ship_id_by_peer.clear()
	last_cmd_by_ship.clear()
	print("Driftline server shutdown complete")


func _process(delta: float) -> bool:

	if shutdown_requested:
		# Returning true ends the SceneTree main loop (and triggers _finalize).
		return true

	runtime_seconds += delta
	if quit_after_seconds > 0.0 and runtime_seconds >= quit_after_seconds:
		_request_shutdown("quit_after")
		return true

	quit_poll_accumulator_seconds += delta
	if quit_flag_path != "" and quit_poll_accumulator_seconds >= QUIT_POLL_INTERVAL_SECONDS:
		quit_poll_accumulator_seconds -= QUIT_POLL_INTERVAL_SECONDS
		if FileAccess.file_exists(quit_flag_path):
			_request_shutdown("quit_flag")
			return true

	_poll_network_packets()

	accumulator_seconds += delta

	while accumulator_seconds >= DriftConstants.TICK_DT:
		accumulator_seconds -= DriftConstants.TICK_DT

		if world != null and world.ships.size() > 0:
			_step_authoritative_tick()

	# Keep running.
	return false


func _request_shutdown(reason: String) -> void:
	if shutdown_requested:
		return
	shutdown_requested = true
	print("[SERVER] shutdown requested (", reason, ")")
	# Close the socket before quitting.
	if enet_peer != null:
		enet_peer.close()
		enet_peer = null
	# _process() will return true on the next call to end the main loop.


func _parse_user_args() -> void:
	# User args come after `--`.
	# Supported:
	#   --quit_after=SECONDS
	#   --quit_flag=user://server.quit
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for raw in args:
		var s: String = String(raw)
		if s.begins_with("--"):
			s = s.substr(2)
		if not s.contains("="):
			continue
		var parts: PackedStringArray = s.split("=", false, 2)
		if parts.size() != 2:
			continue
		var key: String = parts[0]
		var value: String = parts[1]
		if key == "quit_after":
			quit_after_seconds = float(value)
		elif key == "quit_flag":
			quit_flag_path = value


func _load_map(path: String) -> void:
	push_warning("_load_map() is deprecated; use _load_selected_map_from_config()")


func _load_selected_map_from_config() -> bool:
	var cfg_res: Dictionary = DriftServerConfig.load_config()
	if not bool(cfg_res.get("ok", false)):
		push_error("[CFG] " + String(cfg_res.get("error", "Failed to load server_config.json")))
		return false

	var cfg: Dictionary = cfg_res.get("config", {})
	var selected_path: String = String(cfg.get("default_map", "")).strip_edges()
	if selected_path == "":
		push_error("[CFG] server_config.json default_map is empty")
		return false

	# Strict: no fallback map. Missing/invalid is fatal.
	var res: Dictionary = DriftMapLoader.load_map(selected_path)
	if not bool(res.get("ok", false)):
		push_error("[MAP] " + String(res.get("error", "map load failed")))
		return false

	# Apply warnings (non-fatal)
	for w in (res.get("warnings", []) as Array):
		print("[MAP] warning: ", String(w))

	var canonical: Dictionary = res.get("map", {})
	var meta: Dictionary = canonical.get("meta", {})
	map_entities = canonical.get("entities", [])
	map_checksum = res.get("checksum", PackedByteArray())
	map_path = String(res.get("path", ""))
	map_version = int(res.get("map_version", 0))

	var w_tiles: int = int(meta.get("w", 64))
	var h_tiles: int = int(meta.get("h", 64))

	var tileset_name: String = String(meta.get("tileset", "")).strip_edges()
	if tileset_name == "":
		push_error("[MAP] meta.tileset is required (empty)")
		return false
	var tileset_def := DriftTileDefs.load_tileset(tileset_name)
	if not bool(tileset_def.get("ok", false)):
		push_warning("[TILES] " + String(tileset_def.get("error", "Failed to load tiles_def")))
	else:
		print("Tile defs: ", String(tileset_def.get("path", "")))

	var canonical_layers: Dictionary = canonical.get("layers", {})
	var solid_layer_cells: Array = canonical_layers.get("solid", [])
	var solid_cells: Array = DriftTileDefs.build_solid_cells_from_layer_cells(solid_layer_cells, tileset_def)
	var door_cells: Array = DriftTileDefs.build_door_cells_from_layer_cells(solid_layer_cells, tileset_def)
	world.set_solid_tiles(solid_cells)
	world.set_door_tiles(door_cells)
	var door_open_s: float = float(meta.get("door_open_seconds", DriftConstants.DOOR_OPEN_SECONDS))
	var door_closed_s: float = float(meta.get("door_closed_seconds", DriftConstants.DOOR_CLOSED_SECONDS))
	var door_frame_s: float = float(meta.get("door_frame_seconds", DriftConstants.DOOR_FRAME_SECONDS))
	var door_start_open: bool = bool(meta.get("door_start_open", DriftConstants.DOOR_START_OPEN))
	world.configure_doors(door_open_s, door_closed_s, door_frame_s, door_start_open)
	world.add_boundary_tiles(w_tiles, h_tiles)

	print("Loaded map: ", w_tiles, "x", h_tiles, " tiles, ", world.solid_tiles.size(), " solid tiles")
	print("Map path: ", map_path)
	print("Map checksum (sha256): ", DriftMap.bytes_to_hex(map_checksum))
	print("Map version: ", map_version)
	var spawn_count: int = 0
	for e in map_entities:
		if typeof(e) == TYPE_DICTIONARY and String((e as Dictionary).get("type", "")) == "spawn":
			spawn_count += 1
	print("Map entities: ", map_entities.size(), " (spawns=", spawn_count, ")")
	return true


func _on_peer_connected(peer_id: int) -> void:
	if world == null:
		push_error("Cannot handle peer connection: world not initialized")
		return
	
	var ship_id: int = next_ship_id
	next_ship_id += 1
	ship_id_by_peer[peer_id] = ship_id
	print("Client connected: ", peer_id, " ship_id=", ship_id)

	# Spawn point spread by ship_id to avoid overlap.
	var spawn: Vector2 = _spawn_for_ship_id(ship_id)

	# Always reset ship state on connect.
	if world.ships.has(ship_id):
		var ship_state: DriftTypes.DriftShipState = world.ships[ship_id]
		ship_state.position = spawn
		ship_state.velocity = Vector2.ZERO
		ship_state.rotation = 0.0
	else:
		world.add_ship(ship_id, spawn)

	# Clear buffered inputs for this ship and reset last cmd.
	_remove_buffered_inputs_for_ship(ship_id)
	last_cmd_by_ship[ship_id] = DriftTypes.DriftInputCmd.new(false, 0.0, false, false)

	_send_welcome(peer_id, ship_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if world == null:
		return
		
	if ship_id_by_peer.has(peer_id):
		var ship_id: int = ship_id_by_peer[peer_id]
		ship_id_by_peer.erase(peer_id)

		# Simplest option: remove ship entirely on disconnect.
		if world.ships.has(ship_id):
			world.ships.erase(ship_id)

		# Clear buffers for that ship.
		last_cmd_by_ship.erase(ship_id)
		_remove_buffered_inputs_for_ship(ship_id)

	print("Client disconnected: ", peer_id)


func _poll_network_packets() -> void:
	if enet_peer == null:
		return

	# Required when not using SceneMultiplayer.
	enet_peer.poll()

	while enet_peer.get_available_packet_count() > 0:
		# Read channel/peer BEFORE consuming the packet.
		var channel: int = enet_peer.get_packet_channel()
		var sender_id: int = enet_peer.get_packet_peer()
		var bytes: PackedByteArray = enet_peer.get_packet()
		if channel != NET_CHANNEL:
			continue
		_handle_packet(sender_id, bytes)


func _handle_packet(sender_id: int, bytes: PackedByteArray) -> void:

	inputs_this_second += 1

	var pkt_type: int = DriftNet.get_packet_type(bytes)
	if pkt_type == DriftNet.PKT_INPUT:
		var input_dict: Dictionary = DriftNet.unpack_input_packet(bytes)
		if input_dict.is_empty():
			return

		if not ship_id_by_peer.has(sender_id):
			return

		var tick: int = input_dict["tick"]
		var ship_id: int = input_dict["ship_id"]
		if ship_id_by_peer[sender_id] != ship_id:
			return

		# Ignore stale inputs.
		if tick <= world.tick:
			return

		if not inputs_by_tick.has(tick):
			inputs_by_tick[tick] = {}
		var tick_inputs: Dictionary = inputs_by_tick[tick]
		tick_inputs[ship_id] = DriftTypes.DriftInputCmd.new(
			input_dict["thrust"],
			input_dict["turn"],
			input_dict["fire"],
			input_dict.get("reverse", false)
		)

		if DEBUG_NET:
			print("[NET] recv input tick=", tick, " world.tick=", world.tick, " from=", sender_id)


func _step_authoritative_tick() -> void:
	# We are about to step into T = world.tick + 1.
	var intended_tick: int = world.tick + 1

	var tick_inputs: Dictionary = inputs_by_tick.get(intended_tick, {})
	var inputs_for_step: Dictionary = {}

	var ship_ids: Array = world.ships.keys()
	ship_ids.sort()
	for ship_id in ship_ids:
		var cmd: DriftTypes.DriftInputCmd
		if tick_inputs.has(ship_id):
			cmd = tick_inputs[ship_id]
			last_cmd_by_ship[ship_id] = cmd
		elif last_cmd_by_ship.has(ship_id):
			cmd = last_cmd_by_ship[ship_id]
		else:
			cmd = DriftTypes.DriftInputCmd.new(false, 0.0, false, false)
			last_cmd_by_ship[ship_id] = cmd

		inputs_for_step[ship_id] = cmd

	if inputs_by_tick.has(intended_tick):
		inputs_by_tick.erase(intended_tick)

	latest_snapshot = world.step_tick(inputs_for_step)

	if world.tick % DriftConstants.TICK_RATE == 0 and world.tick != last_printed_tick:
		last_printed_tick = world.tick
		print("[SERVER] SIM TICK:", world.tick, " ships=", world.ships.size())


	# After stepping, world.tick must now equal the intended tick.
	if DEBUG_NET and world.tick != intended_tick:
		print("[NET] tick mismatch after step: intended=", intended_tick, " actual=", world.tick)

	if (latest_snapshot.tick % SNAPSHOT_INTERVAL_TICKS) == 0:
		_send_snapshot(latest_snapshot)

	if (latest_snapshot.tick % DriftConstants.TICK_RATE) == 0:
		var snapshot_ship_ids: Array = latest_snapshot.ships.keys()
		snapshot_ship_ids.sort()
		if snapshot_ship_ids.size() > 0:
			var ship_id: int = int(snapshot_ship_ids[0])
			var ship_state: DriftTypes.DriftShipState = latest_snapshot.ships[ship_id]
			print("tick=", latest_snapshot.tick,
				" ship_id=", ship_id,
				" pos=", ship_state.position,
				" vel=", ship_state.velocity)



func _send_snapshot(snapshot: DriftTypes.DriftWorldSnapshot) -> void:

	

	if ship_id_by_peer.size() == 0:
		return

	var ships_array: Array = DriftNet.snapshot_ships_from_dict(snapshot.ships)
	var packet: PackedByteArray = DriftNet.pack_snapshot_packet(
		snapshot.tick,
		ships_array,
		snapshot.ball_position,
		snapshot.ball_velocity,
		snapshot.ball_owner_id
	)

	# Broadcast to all connected clients.
	enet_peer.set_transfer_channel(NET_CHANNEL)
	enet_peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	for peer_id in ship_id_by_peer.keys():
		enet_peer.set_target_peer(int(peer_id))
		enet_peer.put_packet(packet)


func _send_welcome(peer_id: int, ship_id: int) -> void:
	var packet: PackedByteArray = DriftNet.pack_welcome_packet(ship_id, map_checksum, map_path, map_version)
	enet_peer.set_transfer_channel(NET_CHANNEL)
	enet_peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	enet_peer.set_target_peer(peer_id)
	enet_peer.put_packet(packet)


func _spawn_for_ship_id(ship_id: int) -> Vector2:
	# Prefer authored spawn entities if present.
	# Deterministic choice: index by (ship_id-1) modulo spawn count.
	var spawn_cells: Array = []
	for e in map_entities:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		if String(d.get("type", "")) != "spawn":
			continue
		spawn_cells.append(Vector2i(int(d.get("x", 0)), int(d.get("y", 0))))

	var index: int = ship_id - 1
	var dx: float = float(index % 4) * 48.0
	var dy: float = float(index / 4) * 48.0
	if spawn_cells.size() > 0:
		var c: Vector2i = spawn_cells[index % spawn_cells.size()]
		# Place at tile center.
		var base := Vector2(float(c.x) + 0.5, float(c.y) + 0.5) * float(DriftMap.TILE_SIZE)
		return base + Vector2(dx, dy)

	# Fallback: original deterministic grid around a fixed point.
	return SPAWN_POSITION + Vector2(dx, dy)


func _remove_buffered_inputs_for_ship(ship_id: int) -> void:
	# Remove ship_id entries from any tick buckets.
	var ticks: Array = inputs_by_tick.keys()
	for t in ticks:
		var tick_inputs: Dictionary = inputs_by_tick[t]
		if tick_inputs.has(ship_id):
			tick_inputs.erase(ship_id)
			if tick_inputs.is_empty():
				inputs_by_tick.erase(t)
