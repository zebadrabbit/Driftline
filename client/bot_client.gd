## Driftline headless bot client.
##
## Goals:
## - Connects to the authoritative server like a normal client
## - Sends tick-tagged inputs every tick
## - Maintains local prediction + snapshot reconciliation (input replay)
## - No rendering
##
## Run:
##   godot --headless --path . --script res://client/bot_client.gd

extends SceneTree

const DriftWorld = preload("res://shared/drift_world.gd")
const DriftTypes = preload("res://shared/drift_types.gd")
const DriftConstants = preload("res://shared/drift_constants.gd")
const DriftNet = preload("res://shared/drift_net.gd")
const DriftValidate = preload("res://shared/drift_validate.gd")

const SERVER_HOST: String = "127.0.0.1"
const SERVER_PORT: int = 5000

const NET_CHANNEL: int = 1
const DEBUG_NET: bool = false

const QUIT_FLAG_PATH := "user://bot.quit"
const QUIT_POLL_INTERVAL_SECONDS: float = 0.25

const DEFAULT_SPAWN: Vector2 = Vector2(512.0, 512.0)

var world: DriftWorld
var accumulator_seconds: float = 0.0

var enet_peer: ENetMultiplayerPeer
var last_connection_status: int = MultiplayerPeer.CONNECTION_DISCONNECTED
var connected: bool = false

var quit_flag_path: String = QUIT_FLAG_PATH
var quit_after_seconds: float = -1.0
var runtime_seconds: float = 0.0
var shutdown_requested: bool = false

var quit_poll_accumulator_seconds: float = 0.0

var local_ship_id: int = -1

var authoritative_tick: int = -1
var authoritative_ship_state: DriftTypes.DriftShipState
var has_authoritative: bool = false

# input_history[tick] = input applied when stepping into that tick.
var input_history: Dictionary = {} # Dictionary[int, DriftTypes.DriftInputCmd]

# Wander behavior.
var rng: RandomNumberGenerator
var wander_time_left: float = 0.0
var wander_turn: float = 0.0
var wander_thrust: bool = false


func _initialize() -> void:
	_parse_user_args()
	print("Bot soft stop: create ", quit_flag_path, " to quit")
	print("Bot soft stop path (absolute): ", ProjectSettings.globalize_path(quit_flag_path))
	if quit_after_seconds > 0.0:
		print("Bot soft stop: will quit after ", quit_after_seconds, " seconds")

	world = DriftWorld.new()
	
	rng = RandomNumberGenerator.new()
	rng.randomize()
	_set_new_wander_goal()

	enet_peer = ENetMultiplayerPeer.new()
	var err: int = enet_peer.create_client(SERVER_HOST, SERVER_PORT)
	if err != OK:
		push_error("Bot failed to create ENet client (err=%d)" % err)
		quit()
		return

	last_connection_status = enet_peer.get_connection_status()

	print("Bot starting, connecting to ", SERVER_HOST, ":", SERVER_PORT)


func _finalize() -> void:
	shutdown_requested = true
	if enet_peer != null:
		enet_peer.close()
		enet_peer = null
	print("Bot shutdown complete")


func _process(delta: float) -> bool:
	if shutdown_requested:
		return false

	runtime_seconds += delta
	if quit_after_seconds > 0.0 and runtime_seconds >= quit_after_seconds:
		_request_shutdown("quit_after")
		return false

	quit_poll_accumulator_seconds += delta
	if quit_flag_path != "" and quit_poll_accumulator_seconds >= QUIT_POLL_INTERVAL_SECONDS:
		quit_poll_accumulator_seconds -= QUIT_POLL_INTERVAL_SECONDS
		if FileAccess.file_exists(quit_flag_path):
			_request_shutdown("quit_flag")
			return false

	_poll_network_packets()

	# Run fixed 60Hz ticks.
	accumulator_seconds += delta
	while accumulator_seconds >= DriftConstants.TICK_DT:
		accumulator_seconds -= DriftConstants.TICK_DT
		_step_one_tick()

	return false


func _request_shutdown(reason: String) -> void:
	if shutdown_requested:
		return
	shutdown_requested = true
	print("[BOT] shutdown requested (", reason, ")")
	if enet_peer != null:
		enet_peer.close()
		enet_peer = null
	quit(0)


func _parse_user_args() -> void:
	# User args come after `--`.
	# Supported:
	#   --quit_after=SECONDS
	#   --quit_flag=user://bot.quit
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


func _step_one_tick() -> void:
	if not connected:
		return
	if local_ship_id < 0:
		# Waiting for welcome packet.
		return

	# Ensure local ship exists (it may have been reset on reconnect).
	if not world.ships.has(local_ship_id):
		world.add_ship(local_ship_id, DEFAULT_SPAWN)

	wander_time_left -= DriftConstants.TICK_DT
	if wander_time_left <= 0.0:
		_set_new_wander_goal()

	var cmd: DriftTypes.DriftInputCmd = DriftTypes.DriftInputCmd.new(1.0 if wander_thrust else 0.0, wander_turn, false, false, false)
	var next_tick: int = world.tick + 1

	input_history[next_tick] = cmd
	_send_input(next_tick, cmd)

	# Predict locally.
	world.step_tick({ local_ship_id: cmd })


func _set_new_wander_goal() -> void:
	wander_time_left = rng.randf_range(0.5, 1.5)
	wander_turn = rng.randf_range(-1.0, 1.0)
	wander_thrust = rng.randf() < 0.7

	# Occasionally stop thrust briefly.
	if wander_thrust and rng.randf() < 0.15:
		wander_thrust = false
		wander_time_left = rng.randf_range(0.15, 0.35)


func _send_input(tick: int, cmd: DriftTypes.DriftInputCmd) -> void:
	var packet: PackedByteArray = DriftNet.pack_input_packet(tick, local_ship_id, cmd)
	# Server peer id is always 1.
	enet_peer.set_transfer_channel(NET_CHANNEL)
	enet_peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	enet_peer.set_target_peer(1)
	enet_peer.put_packet(packet)


func _poll_network_packets() -> void:
	if enet_peer == null:
		return

	enet_peer.poll()
	_update_connection_state()

	var best_snapshot_tick: int = -1
	var best_snapshot_dict: Dictionary = {}

	while enet_peer.get_available_packet_count() > 0:
		var channel: int = enet_peer.get_packet_channel()
		var _sender_id: int = enet_peer.get_packet_peer()
		var bytes: PackedByteArray = enet_peer.get_packet()
		if channel != NET_CHANNEL:
			continue

		var pkt_type: int = DriftNet.get_packet_type(bytes)
		if pkt_type == DriftNet.PKT_WELCOME:
			var w: Dictionary = DriftNet.unpack_welcome_packet(bytes)
			if not w.is_empty():
				local_ship_id = w["ship_id"]
				print("Bot assigned ship_id=", local_ship_id)
				# Reset local state for clean start.
				world.tick = 0
				world.ships.clear()
				world.add_ship(local_ship_id, DEFAULT_SPAWN)
				input_history.clear()
				authoritative_tick = -1
				authoritative_ship_state = null
				has_authoritative = false
				var ruleset_json: String = String(w.get("ruleset_json", "")).strip_edges()
				if ruleset_json != "":
					var json := JSON.new()
					var parse_err := json.parse(ruleset_json)
					if parse_err == OK and typeof(json.data) == TYPE_DICTIONARY:
						var validated := DriftValidate.validate_ruleset(json.data)
						if bool(validated.get("ok", false)):
							world.apply_ruleset(validated.get("ruleset", {}))
				else:
					# Backward compat: accept wall_restitution-only handshake.
					var wr: float = float(w.get("wall_restitution", -1.0))
					if wr >= 0.0:
						world.wall_restitution = wr
				# Optional: tangent damping (present in newer handshakes).
				var td: float = float(w.get("tangent_damping", -1.0))
				if td >= 0.0:
					world.tangent_damping = td
			continue

		if pkt_type == DriftNet.PKT_SNAPSHOT:
			var snap_dict: Dictionary = DriftNet.unpack_snapshot_packet(bytes)
			if snap_dict.is_empty():
				continue

			var snap_tick: int = snap_dict["tick"]
			if snap_tick > best_snapshot_tick:
				best_snapshot_tick = snap_tick
				best_snapshot_dict = snap_dict

	if best_snapshot_tick != -1:
		_apply_snapshot_dict(best_snapshot_dict)


func _update_connection_state() -> void:
	var status: int = enet_peer.get_connection_status()
	if status == last_connection_status:
		return

	if status == MultiplayerPeer.CONNECTION_CONNECTED:
		connected = true
		print("Bot connected")
	elif status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		if last_connection_status == MultiplayerPeer.CONNECTION_CONNECTING:
			push_error("Bot connection failed")
			quit()
			return
		elif last_connection_status == MultiplayerPeer.CONNECTION_CONNECTED:
			print("Bot disconnected")
			connected = false
			local_ship_id = -1
			has_authoritative = false
			authoritative_tick = -1
			authoritative_ship_state = null
			input_history.clear()

	last_connection_status = status


func _apply_snapshot_dict(snap_dict: Dictionary) -> void:
	var snap_tick: int = snap_dict["tick"]
	if snap_tick <= authoritative_tick:
		return
	var auth_bullets: Array = []
	if snap_dict.has("bullets") and (snap_dict.get("bullets") is Array):
		auth_bullets = snap_dict.get("bullets")

	var ships: Array = snap_dict["ships"]
	for ship_state in ships:
		if ship_state.id == local_ship_id:
			authoritative_tick = snap_tick
			authoritative_ship_state = ship_state
			has_authoritative = true
			_reconcile_to_authoritative_snapshot(snap_tick, ship_state, auth_bullets)
			break


func _reconcile_to_authoritative_snapshot(snapshot_tick: int, auth_state: DriftTypes.DriftShipState, auth_bullets_for_tick: Array) -> void:
	var current_tick: int = world.tick

	if not world.ships.has(local_ship_id):
		world.add_ship(local_ship_id, auth_state.position)

	var local_state: DriftTypes.DriftShipState = world.ships[local_ship_id]
	local_state.position = auth_state.position
	local_state.velocity = auth_state.velocity
	local_state.rotation = auth_state.rotation

	world.tick = snapshot_tick

	# Reset predicted bullets baseline for this bot.
	if world != null:
		world.bullets.clear()
		for b in auth_bullets_for_tick:
			if b == null:
				continue
			if int(b.owner_id) != local_ship_id:
				continue
			world.bullets[int(b.id)] = DriftTypes.DriftBulletState.new(int(b.id), int(b.owner_id), b.position, b.velocity, int(b.spawn_tick), int(b.die_tick))
		var base_cmd: DriftTypes.DriftInputCmd = input_history.get(snapshot_tick, DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false))
		world._prev_fire_by_ship[local_ship_id] = bool(base_cmd.fire_primary)

	# If snapshot is ahead, snap forward and stop.
	if snapshot_tick >= current_tick:
		_prune_input_history(authoritative_tick)
		return

	for t in range(snapshot_tick + 1, current_tick + 1):
		var cmd: DriftTypes.DriftInputCmd = input_history.get(t, DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false))
		world.step_tick({ local_ship_id: cmd })

	_prune_input_history(authoritative_tick)

	if DEBUG_NET:
		var drift: float = world.ships[local_ship_id].position.distance_to(auth_state.position)
		print("[BOT] reconciled tick=", snapshot_tick, " world.tick=", world.tick, " drift=", drift)


func _prune_input_history(upto_tick_inclusive: int) -> void:
	var keys: Array = input_history.keys()
	for k in keys:
		if int(k) <= upto_tick_inclusive:
			input_history.erase(k)
