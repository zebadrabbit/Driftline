## Driftline client bootstrap (minimal ENet networking).
##
## Responsibilities:
## - Run a fixed 60 Hz simulation tick loop using an accumulator
## - Collect keyboard input and feed it to DriftWorld as DriftInputCmd
## - Send tick-tagged inputs to server (no reconciliation yet)
## - Receive authoritative snapshots and render a "ghost" ship for comparison
## - Render the ship and debug overlay using _draw() only


extends Node2D

func _enter_tree() -> void:
	z_index = 0 # Ensure this node draws above the starfield (which is -1000)

const DriftWorld = preload("res://shared/drift_world.gd")
const DriftTypes = preload("res://shared/drift_types.gd")
const DriftConstants = preload("res://shared/drift_constants.gd")
const DriftNet = preload("res://shared/drift_net.gd")
const DriftMap = preload("res://shared/drift_map.gd")
const DriftValidate = preload("res://shared/drift_validate.gd")
const DriftTileDefs = preload("res://shared/drift_tile_defs.gd")
const SpriteFontLabelScript = preload("res://client/SpriteFontLabel.gd")
const LevelIO = preload("res://client/scripts/maps/level_io.gd")
const MapEditorScene: PackedScene = preload("res://client/scenes/editor/MapEditor.tscn")
const TilemapEditorScene: PackedScene = preload("res://tools/tilemap_editor/TilemapEditor.tscn")

const PRIZE_TEX: Texture2D = preload("res://client/graphics/entities/prizes.png")
const PRIZE_FRAME_PX: int = 16
const PRIZE_FRAME_COUNT: int = 10
const PRIZE_ANIM_FPS: float = 12.0
const PRIZE_DRAW_SCALE: float = 1.5
const PRIZE_PICKUP_SFX_PATH: String = "res://client/audio/prize.wav"

const VELOCITY_DRAW_SCALE: float = 0.10

const SERVER_HOST: String = "127.0.0.1"
const SERVER_PORT: int = 5000

const CLIENT_MAP_PATH: String = "res://maps/default.json"

const DEBUG_NET: bool = false

# Use a non-zero channel so Godot's high-level multiplayer (RPC/scene cache)
# does not try to parse our custom packets.
const NET_CHANNEL: int = 1

# Temporary dev username (set on the Main node in the Inspector).
@export var player_username: String = "Player"
var _hello_sent: bool = false

# Connection UI state
var show_connect_ui: bool = true
var server_address: String = "127.0.0.1"
var connection_status_message: String = "Not connected"
var allow_offline_mode: bool = false

# In-game ESC menu (non-blocking)
var pause_menu_visible: bool = false
var pause_menu_layer: CanvasLayer
var pause_menu_panel: Panel

# Wall-bounce audio (driven by shared simulation collision events)
@export var bounce_sound_min_speed: float = 160.0
@export var bounce_sound_cooldown: float = 0.10
var _last_bounce_time_s: float = -999.0
@onready var _bounce_audio: AudioStreamPlayer = get_node_or_null("BounceAudio")

var _prize_audio: AudioStreamPlayer = null

var world: DriftWorld

var client_map_checksum: PackedByteArray = PackedByteArray()
var client_map_version: int = 0
var accumulator_seconds: float = 0.0

# Camera2D reference
var cam: Camera2D = null


var local_ship_id: int = -1
# Remote ship tracking
var remote_ships: Dictionary = {} # Dictionary[int, DriftTypes.DriftShipState]
var remote_tick: int = -1



# Ball state from latest authoritative snapshot
var latest_snapshot: DriftTypes.DriftWorldSnapshot
var ball_position: Vector2 = Vector2.ZERO
var ball_velocity: Vector2 = Vector2.ZERO
var authoritative_bullets: Array = [] # Array[DriftTypes.DriftBulletState]
var authoritative_prizes: Array = [] # Array[DriftTypes.DriftPrizeState]

# Interpolation state for remote ships and ball
var snap_a_tick := -1
var snap_b_tick := -1
var snap_a_time_ms := 0
var snap_b_time_ms := 0
var snap_a_ships := {}
var snap_b_ships := {}
var snap_a_ball_pos := Vector2.ZERO
var snap_b_ball_pos := Vector2.ZERO

var enet_peer: ENetMultiplayerPeer
var is_connected: bool = false
var last_connection_status: int = MultiplayerPeer.CONNECTION_DISCONNECTED

var authoritative_tick: int = -1
var authoritative_ship_state: DriftTypes.DriftShipState

var connected: bool = false
var has_authoritative: bool = false

const SPAWN_POSITION: Vector2 = Vector2(512.0, 512.0)

# Client-side prediction history for reconciliation.
# input_history[tick] = input applied when stepping into that tick.
var input_history: Dictionary = {} # Dictionary[int, DriftTypes.DriftInputCmd]

# Optional debugging: store last authoritative state per tick.
var snapshot_history: Dictionary = {} # Dictionary[int, DriftTypes.DriftShipState]


# Door tiles (animated + dynamic collision)
var _door_cells: Array = [] # Array[Dictionary] { cell: Vector2i, orient: String }
var _tilemap_solid: TileMap = null
var _last_door_anim_key: int = -999999



func _ready() -> void:
	z_index = 0
	set_z_as_relative(false)
	for child in get_children():
		if child is CanvasItem:
			# Don't override background layering (Starfield manages its own z_index).
			if child.name != "Starfield":
				child.z_index = 0
				child.set_z_as_relative(false)

	# Don't auto-connect - wait for user to click connect
	world = DriftWorld.new()
	
	# Load map for client-side rendering and collision
	_load_client_map()

	_build_pause_menu_ui()
	_set_pause_menu_visible(false)

	# Camera2D setup
	cam = get_node_or_null("Camera2D")
	if cam:
		# Start camera at origin for connection UI
		cam.position = Vector2.ZERO
		cam.enabled = true

	# Prime snapshot so _draw() has something immediately.
	latest_snapshot = DriftTypes.DriftWorldSnapshot.new(0, {})
	queue_redraw()

	# Prize pickup SFX (client-side). Created programmatically to avoid scene edits.
	_prize_audio = AudioStreamPlayer.new()
	_prize_audio.name = "PrizeAudio"
	var sfx = load(PRIZE_PICKUP_SFX_PATH)
	if sfx is AudioStream:
		_prize_audio.stream = sfx
	add_child(_prize_audio)

	# Optional: unlimited redraw rate for testing
	Engine.max_fps = 0
	
	# Show connection UI and hide game elements
	show_connect_ui = true
	connection_status_message = "Enter server address to connect"
	_update_ui_visibility()


func _load_client_map() -> void:
	"""Load map for client-side rendering and collision detection."""
	var tilemaps := {
		"bg": get_node_or_null("TileMapBG"),
		"solid": get_node_or_null("TileMapSolid"),
		"fg": get_node_or_null("TileMapFG")
	}
	_tilemap_solid = tilemaps.get("solid", null)

	# Apply tiles to the TileMaps.
	var meta_applied := LevelIO.load_map_from_json(CLIENT_MAP_PATH, tilemaps)
	if meta_applied.is_empty():
		push_error("Failed to load client map")
		return

	# Also read raw map for checksum/manifest verification and canonical layers for collision.
	var raw := LevelIO.read_map_data(CLIENT_MAP_PATH)
	var validated := DriftMap.validate_and_canonicalize(raw)
	if not bool(validated.get("ok", false)):
		push_error("Failed to validate client map: " + CLIENT_MAP_PATH)
		for e in (validated.get("errors", []) as Array):
			push_error(" - " + String(e))
		return
	var canonical: Dictionary = validated.get("map", {})
	client_map_version = int(canonical.get("schema_version", 0))
	client_map_checksum = DriftMap.checksum_sha256_canonical(canonical)
	print("Client map checksum (sha256): ", DriftMap.bytes_to_hex(client_map_checksum))
	print("Client map path: ", CLIENT_MAP_PATH)
	print("Client map version: ", client_map_version)
	var meta: Dictionary = canonical.get("meta", {})
	var tileset_name: String = String(meta.get("tileset", "")).strip_edges()
	if tileset_name == "":
		push_error("Client map meta.tileset is required (empty)")
		return
	var tileset_def := DriftTileDefs.load_tileset(tileset_name)
	if not bool(tileset_def.get("ok", false)):
		push_warning("[TILES] " + String(tileset_def.get("error", "Failed to load tiles_def")))
	else:
		print("Tile defs: ", String(tileset_def.get("path", "")))

	var canonical_layers: Dictionary = canonical.get("layers", {})
	var solid_layer_cells: Array = canonical_layers.get("solid", [])
	var solid_cells: Array = DriftTileDefs.build_solid_cells_from_layer_cells(solid_layer_cells, tileset_def)
	var door_cells_raw: Array = DriftTileDefs.build_door_cells_from_layer_cells(solid_layer_cells, tileset_def)
	world.set_solid_tiles(solid_cells)
	world.set_door_tiles(door_cells_raw)
	var door_open_s: float = float(meta.get("door_open_seconds", DriftConstants.DOOR_OPEN_SECONDS))
	var door_closed_s: float = float(meta.get("door_closed_seconds", DriftConstants.DOOR_CLOSED_SECONDS))
	var door_frame_s: float = float(meta.get("door_frame_seconds", DriftConstants.DOOR_FRAME_SECONDS))
	var door_start_open: bool = bool(meta.get("door_start_open", DriftConstants.DOOR_START_OPEN))
	world.configure_doors(door_open_s, door_closed_s, door_frame_s, door_start_open)

	# Cache door cells for TileMap animation.
	_door_cells.clear()
	for d in door_cells_raw:
		if not (d is Array) or (d as Array).size() != 4:
			continue
		var arr: Array = d
		var ax: int = int(arr[2])
		var ay: int = int(arr[3])
		var orient: String = ""
		# Door atlas coords are fixed across tilesets.
		if ay == 8 and ax >= 9 and ax <= 12:
			orient = "v"
		elif ay == 8 and ax >= 13 and ax <= 16:
			orient = "h"
		_door_cells.append({"cell": Vector2i(int(arr[0]), int(arr[1])), "orient": orient})
	
	world.add_boundary_tiles(int(meta.get("w", 0)), int(meta.get("h", 0)))
	
	print("Client map loaded: ", meta.get("w", 0), "x", meta.get("h", 0), " tiles")
	_update_door_tilemap_visual()


func _update_door_tilemap_visual() -> void:
	if _tilemap_solid == null:
		return
	if _door_cells.is_empty():
		return
	if world == null:
		return

	var anim: Dictionary = world.get_door_anim_for_tick(world.tick)
	var is_open: bool = bool(anim.get("open", true))
	var frame: int = int(anim.get("frame", -1))

	# Build a tiny key so we only touch the TileMap when the visible state changes.
	var key: int = (world.tick << 4) ^ (1 if is_open else 0) ^ (frame << 1)
	if key == _last_door_anim_key:
		return
	_last_door_anim_key = key

	var v_frames := [Vector2i(9, 8), Vector2i(10, 8), Vector2i(11, 8), Vector2i(12, 8)]
	var h_frames := [Vector2i(13, 8), Vector2i(14, 8), Vector2i(15, 8), Vector2i(16, 8)]
	var frame_idx: int = clampi(frame, 0, 3)

	for entry in _door_cells:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = entry
		var cell: Vector2i = e.get("cell", Vector2i.ZERO)
		var orient: String = String(e.get("orient", ""))
		if is_open:
			# Clear tile graphic.
			_tilemap_solid.set_cell(0, cell, -1)
		else:
			var atlas: Vector2i = v_frames[frame_idx] if orient == "v" else h_frames[frame_idx]
			_tilemap_solid.set_cell(0, cell, 0, atlas)


func _setup_networking() -> void:
	enet_peer = ENetMultiplayerPeer.new()
	var err: int = enet_peer.create_client(server_address, SERVER_PORT)
	if err != OK:
		push_error("Failed to create ENet client (err=%d)" % err)
		connection_status_message = "Connection failed (error " + str(err) + ")"
		queue_redraw()
		return

	# IMPORTANT:
	# Do NOT assign this peer to SceneMultiplayer (multiplayer.multiplayer_peer).
	# We are using raw custom packets, not Godot RPC replication.
	# Assigning it triggers SceneMultiplayer to parse packets and spam:
	#   "Invalid packet received. Size too small."
	#
	# ENetMultiplayerPeer does not expose the same connection signals as SceneMultiplayer,
	# so we detect connection state changes by polling get_connection_status().
	last_connection_status = enet_peer.get_connection_status()


func _process(delta: float) -> void:
	# Always poll network even when showing UI
	if enet_peer != null:
		_poll_network_packets()

	# Keep door tiles visually in sync with the local simulation tick.
	_update_door_tilemap_visual()
	
	# Show connection UI if not connected and not in offline mode
	if show_connect_ui:
		queue_redraw()
		return
	
	# Only run game simulation when connected or in offline mode
	if not is_connected and not allow_offline_mode:
		queue_redraw()
		return

	accumulator_seconds += delta

	var did_step: bool = false
	while accumulator_seconds >= DriftConstants.TICK_DT:
		accumulator_seconds -= DriftConstants.TICK_DT
		_latest_tick_step()
		did_step = true

	# Always redraw every frame, not just on sim tick
	queue_redraw()

	# Camera follow and clamp (only when playing)
	if not show_connect_ui and cam and local_ship_id >= 0 and world.ships.has(local_ship_id):
		var ship = world.ships[local_ship_id]
		# Always center camera on ship - no clamping
		cam.global_position = ship.position

	# Demo HUD line (SpriteFontLabel): feed it simple live values.
	var hud := get_node_or_null("HUD")
	if hud != null and hud.has_method("set_values"):
		var name_value := player_username
		var bounty_value := 0
		if latest_snapshot != null and latest_snapshot.ships.has(local_ship_id):
			var s = latest_snapshot.ships.get(local_ship_id)
			if s != null:
				if typeof(s.username) == TYPE_STRING and s.username != "":
					name_value = String(s.username)
				bounty_value = int(s.bounty)
		hud.call("set_values", name_value, bounty_value, 0, local_ship_id)
		if hud.has_method("set_ship_stats") and latest_snapshot != null and latest_snapshot.ships.has(local_ship_id):
			var ss = latest_snapshot.ships.get(local_ship_id)
			if ss != null:
				hud.call("set_ship_stats", float(ss.velocity.length()), float(rad_to_deg(ss.rotation)), float(ss.energy))


func _latest_tick_step() -> void:
	if local_ship_id < 0:
		return
	if not world.ships.has(local_ship_id):
		world.add_ship(local_ship_id, SPAWN_POSITION)
	# Keep local ship identity in sync for rendering.
	var local_state: DriftTypes.DriftShipState = world.ships.get(local_ship_id)
	if local_state != null:
		local_state.username = player_username

	var input_cmd: DriftTypes.DriftInputCmd = _collect_input_cmd()
	var next_tick: int = world.tick + 1
	input_history[next_tick] = input_cmd
	_send_input_for_tick(next_tick, input_cmd)
	latest_snapshot = world.step_tick({ local_ship_id: input_cmd })
	_play_local_collision_sounds()

	if DEBUG_NET and world.tick != next_tick:
		print("[NET] local tick mismatch after step: intended=", next_tick, " actual=", world.tick)


func _play_local_collision_sounds() -> void:
	if world == null:
		return
	if local_ship_id < 0:
		return
	if _bounce_audio == null or _bounce_audio.stream == null:
		return

	var events: Array = world.collision_events
	if events.is_empty():
		return

	var now_s: float = float(Time.get_ticks_msec()) / 1000.0
	if now_s - _last_bounce_time_s < bounce_sound_cooldown:
		return

	for ev in events:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = ev
		if int(d.get("ship_id", -1)) != local_ship_id:
			continue
		if String(d.get("type", "")) != "wall":
			continue
		var impact_speed: float = float(d.get("impact_speed", 0.0))
		if impact_speed < bounce_sound_min_speed:
			continue

		var speed_norm: float = clampf((impact_speed - bounce_sound_min_speed) / 650.0, 0.0, 1.0)
		_bounce_audio.volume_db = lerpf(-16.0, -4.0, speed_norm)
		_bounce_audio.pitch_scale = lerpf(0.95, 1.15, speed_norm)
		_bounce_audio.play()
		_last_bounce_time_s = now_s
		break


func _send_input_for_tick(next_tick: int, cmd: DriftTypes.DriftInputCmd) -> void:
	if not is_connected:
		return
	if local_ship_id < 0:
		return

	# Input packet tick refers to the simulation tick that will be stepped next using this input.
	var packet: PackedByteArray = DriftNet.pack_input_packet(next_tick, local_ship_id, cmd)

	# In Godot, the server's peer ID is always 1.
	enet_peer.set_transfer_channel(NET_CHANNEL)
	enet_peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	enet_peer.set_target_peer(1)
	enet_peer.put_packet(packet)


func _collect_input_cmd() -> DriftTypes.DriftInputCmd:
	var rotate_axis: float = Input.get_action_strength("drift_rotate_right") - Input.get_action_strength("drift_rotate_left")
	var thrust_axis: float = Input.get_action_strength("drift_thrust_forward") - Input.get_action_strength("drift_thrust_reverse")
	var fire_primary: bool = Input.is_action_pressed("drift_fire_primary")
	var fire_secondary: bool = Input.is_action_pressed("drift_fire_secondary")
	var modifier: bool = Input.is_action_pressed("drift_modifier_ability")
	return DriftTypes.DriftInputCmd.new(thrust_axis, rotate_axis, fire_primary, fire_secondary, modifier)


func _unhandled_input(_event):
	# Intentionally empty: gameplay input is collected via _collect_input_cmd().
	# UI inputs are handled in _input().
	return


func _draw() -> void:
	# Show connection UI if not connected
	if show_connect_ui:
		_draw_connection_ui()
		return
	
	# HUD: Ball possession
	if latest_snapshot != null and latest_snapshot.ball_owner_id != null:
		if latest_snapshot.ball_owner_id == local_ship_id:
			var font: Font = ThemeDB.fallback_font
			var font_size: int = 24
			var text_color: Color = Color(1.0, 1.0, 0.2, 1.0)
			draw_string(font, Vector2(32, 48), "BALL: YOU", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, text_color)

	# Draw indicator for ball owner (if not free)
	if latest_snapshot != null and latest_snapshot.ball_owner_id != null and latest_snapshot.ball_owner_id != -1:
		var owner_id = latest_snapshot.ball_owner_id
		if latest_snapshot.ships.has(owner_id):
			var owner = latest_snapshot.ships[owner_id]
			var indicator_pos = owner.position + Vector2(0, -24)
			draw_circle(indicator_pos, 8.0, Color(1.0, 0.8, 0.2, 0.7))
			draw_circle(indicator_pos, 12.0, Color(0.2, 0.2, 0.0, 0.3), 2.0)
	# Optionally draw arena bounds
	var min = DriftConstants.ARENA_MIN
	var max = DriftConstants.ARENA_MAX
	var rect_points = [
		min,
		Vector2(max.x, min.y),
		max,
		Vector2(min.x, max.y),
		min
	]
	draw_polyline(rect_points, Color(0.5, 0.5, 0.5, 1.0), 2.0)

	if latest_snapshot == null:
		return

	if local_ship_id < 0:
		_draw_debug_overlay(DriftTypes.DriftShipState.new(-1, Vector2.ZERO), 0)
		return

	var ship_state: DriftTypes.DriftShipState = latest_snapshot.ships.get(local_ship_id)
	if ship_state == null:
		return

	var font: Font = ThemeDB.fallback_font
	var font_size: int = 16
	var name_offset := Vector2(24, 16)
	var king_id := -1
	if latest_snapshot != null and "king_ship_id" in latest_snapshot:
		king_id = latest_snapshot.king_ship_id

	# Interpolated remote ships
	if snap_a_tick >= 0 and snap_b_tick > snap_a_tick:
		var now = Time.get_ticks_msec()
		var denom = float(snap_b_time_ms - snap_a_time_ms)
		var alpha = 1.0
		if denom > 1.0:
			alpha = clamp((now - snap_b_time_ms) / denom, 0.0, 1.0)
		var ids = []
		for id in snap_a_ships.keys():
			if snap_b_ships.has(id):
				ids.append(id)
		ids.sort()
		for ship_id in ids:
			if ship_id == local_ship_id:
				continue
			var a = snap_a_ships[ship_id]
			var b = snap_b_ships[ship_id]
			if a == null or b == null:
				continue
			var interp_pos = a.position.lerp(b.position, alpha)
			var interp_rot = lerp_angle(a.rotation, b.rotation, alpha)
			var interp_state = DriftTypes.DriftShipState.new(ship_id, interp_pos, Vector2.ZERO, interp_rot)
			_draw_remote_ship_triangle(interp_state)
			# Draw username and bounty
			var remote_state = latest_snapshot.ships.get(ship_id)
			if remote_state != null:
				var label = "%s (%d)" % [remote_state.username, remote_state.bounty]
				SpriteFontLabelScript.draw_text(self, interp_pos + name_offset, label, SpriteFontLabelScript.FontSize.SMALL, 2, 0)
				# Draw crown if king
				if king_id == ship_id:
					_draw_crown(interp_pos + Vector2(0, -48))
		# Interpolated ball
		if latest_snapshot.ball_owner_id != local_ship_id:
			var interp_ball_pos = snap_a_ball_pos.lerp(snap_b_ball_pos, alpha)
			_draw_ball_at(interp_ball_pos)
	else:
		# Fallback: draw last known remote ships and ball
		var remote_ids := remote_ships.keys()
		remote_ids.sort()
		for ship_id in remote_ids:
			if ship_id == local_ship_id:
				continue
			var remote_state: DriftTypes.DriftShipState = remote_ships[ship_id]
			_draw_remote_ship_triangle(remote_state)
			# Draw username and bounty
			var snap_state = latest_snapshot.ships.get(ship_id)
			if snap_state != null:
				var label = "%s (%d)" % [snap_state.username, snap_state.bounty]
				SpriteFontLabelScript.draw_text(self, remote_state.position + name_offset, label, SpriteFontLabelScript.FontSize.SMALL, 2, 0)
				# Draw crown if king
				if king_id == ship_id:
					_draw_crown(remote_state.position + Vector2(0, -48))
		if latest_snapshot.ball_owner_id != local_ship_id:
			_draw_ball_at(ball_position)

	# Local ship (predicted)
	_draw_ship_triangle(ship_state)
	_draw_prizes()
	_draw_bullets()
	
	# ⚠️ ALWAYS VISIBLE: Draw username and bounty for local ship (blue sprite font)
	# This element must never be hidden or removed.
	var local_state = latest_snapshot.ships.get(local_ship_id)
	if local_state != null:
		var label = "%s(%d)" % [local_state.username, local_state.bounty]
		SpriteFontLabelScript.draw_text(self, ship_state.position + name_offset, label, SpriteFontLabelScript.FontSize.SMALL, 2, 0)
		if king_id == local_ship_id:
			_draw_crown(ship_state.position + Vector2(0, -48))

	# _draw_authoritative_ghost_ship()  # Disabled - no ghost ship
	_draw_debug_overlay(ship_state, latest_snapshot.tick)

	# HUD: King
	var king_label = "KING: none"
	if king_id != -1 and latest_snapshot.ships.has(king_id):
		var king_state = latest_snapshot.ships[king_id]
		king_label = "KING: %s (%d)" % [king_state.username, king_state.bounty]
	draw_string(font, Vector2(32, 80), king_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color(1, 1, 0.4, 1))


	# Local ship (predicted)
	# (Removed duplicate local ship drawing and overlays)

func _draw_ball_at(pos: Vector2) -> void:
	var color := Color(1.0, 0.6, 0.9, 1.0) # bright white/pink
	var outline := Color(1.0, 0.2, 0.7, 1.0) # pink outline
	var radius := 6.0
	draw_circle(pos, radius, color)
	draw_circle(pos, radius, outline, 2.0)


func _draw_bullets() -> void:
	# Remote bullets: authoritative snapshots.
	for b in authoritative_bullets:
		if b == null:
			continue
		if local_ship_id >= 0 and int(b.owner_id) == local_ship_id:
			continue
		_draw_bullet_at(Vector2(b.position.x, b.position.y))

	# Local bullets: predicted world state (shows shots immediately).
	if local_ship_id >= 0 and world != null and typeof(world.bullets) == TYPE_DICTIONARY:
		var ids: Array = world.bullets.keys()
		ids.sort()
		for bid in ids:
			var pb = world.bullets.get(bid)
			if pb == null:
				continue
			if int(pb.owner_id) != local_ship_id:
				continue
			_draw_bullet_at(Vector2(pb.position.x, pb.position.y))


func _draw_bullet_at(pos: Vector2) -> void:
	# Simple, readable bullet marker.
	draw_circle(pos, 2.5, Color(0.95, 0.95, 1.0, 0.9))


func _draw_prizes() -> void:
	for p in authoritative_prizes:
		if p == null:
			continue
		_draw_prize_at(int(p.id), Vector2(p.pos.x, p.pos.y), int(p.kind), bool(p.is_negative), bool(p.is_death_drop))


func _draw_prize_at(prize_id: int, pos: Vector2, _kind: int, is_negative: bool, is_death_drop: bool) -> void:
	# Sprite sheet: 10 frames, each 16x16, rotating animation.
	# We do not currently vary icon by kind; this is the classic rotating green.
	if PRIZE_TEX == null:
		# Fallback: draw simple marker.
		draw_circle(pos, 6.0, Color(0.35, 1.0, 0.55, 0.95))
		return

	var tex_w := int(PRIZE_TEX.get_width())
	var tex_h := int(PRIZE_TEX.get_height())
	if tex_w <= 0 or tex_h <= 0:
		return
	var cols := maxi(1, tex_w / PRIZE_FRAME_PX)
	var rows := maxi(1, tex_h / PRIZE_FRAME_PX)

	var t_s: float = float(Time.get_ticks_msec()) / 1000.0
	# Per-prize phase offset so they don't animate in lockstep.
	var frame: int = int(floor(t_s * PRIZE_ANIM_FPS) + (prize_id * 3)) % PRIZE_FRAME_COUNT
	var col: int = frame % cols
	var row: int = (frame / cols) % rows
	var src := Rect2(float(col * PRIZE_FRAME_PX), float(row * PRIZE_FRAME_PX), float(PRIZE_FRAME_PX), float(PRIZE_FRAME_PX))

	var size := Vector2(float(PRIZE_FRAME_PX), float(PRIZE_FRAME_PX)) * PRIZE_DRAW_SCALE
	var dst := Rect2(pos - size * 0.5, size)

	var modulate := Color(1.0, 1.0, 1.0, 1.0)
	if is_negative:
		modulate = modulate.darkened(0.55)
	if is_death_drop:
		# Slight boost so death drops pop.
		modulate = modulate.lightened(0.25)

	draw_texture_rect_region(PRIZE_TEX, dst, src, modulate)

func _draw_ball() -> void:
	# Draw the authoritative ball from the latest snapshot
	var color := Color(1.0, 0.85, 0.2, 1.0)
	var outline := Color(0.3, 0.3, 0.1, 1.0)
	var radius := 6.0
	draw_circle(ball_position, radius, color)
	draw_circle(ball_position, radius, outline, 2.0)
	# Optionally, draw velocity vector
	var vel_end := ball_position + ball_velocity * VELOCITY_DRAW_SCALE
	draw_line(ball_position, vel_end, Color(1.0, 0.7, 0.2, 1.0), 2.0)
func _draw_remote_ship_triangle(ship_state: DriftTypes.DriftShipState) -> void:
	# Smaller triangle for remote ships
	var local_points: PackedVector2Array = PackedVector2Array([
		Vector2(10.0, 0.0),
		Vector2(-7.0, -6.0),
		Vector2(-7.0, 6.0),
	])
	var world_points: PackedVector2Array = PackedVector2Array()
	world_points.resize(local_points.size())
	for i in range(local_points.size()):
		world_points[i] = local_points[i].rotated(ship_state.rotation) + ship_state.position
	draw_colored_polygon(world_points, Color(0.7, 0.7, 1.0, 1.0))


func _draw_ship_triangle(ship_state: DriftTypes.DriftShipState) -> void:
	# Local triangle points pointing to +X (Vector2.RIGHT).
	var local_points: PackedVector2Array = PackedVector2Array([
		Vector2(18.0, 0.0),
		Vector2(-12.0, -10.0),
		Vector2(-12.0, 10.0),
	])

	var world_points: PackedVector2Array = PackedVector2Array()
	world_points.resize(local_points.size())
	for i in range(local_points.size()):
		world_points[i] = local_points[i].rotated(ship_state.rotation) + ship_state.position

	draw_colored_polygon(world_points, Color(0.9, 0.9, 0.9, 1.0))


func _draw_authoritative_ghost_ship() -> void:
	if authoritative_ship_state == null:
		return

	# Ghost ship: outline triangle (different shape), using the same color as the predicted ship.
	# This avoids introducing a separate color choice.
	var local_points: PackedVector2Array = PackedVector2Array([
		Vector2(14.0, 0.0),
		Vector2(-10.0, -8.0),
		Vector2(-10.0, 8.0),
		Vector2(14.0, 0.0),
	])

	var world_points: PackedVector2Array = PackedVector2Array()
	world_points.resize(local_points.size())
	for i in range(local_points.size()):
		world_points[i] = local_points[i].rotated(authoritative_ship_state.rotation) + authoritative_ship_state.position

	draw_polyline(world_points, Color(0.9, 0.9, 0.9, 1.0), 2.0)


func _draw_crown(pos: Vector2) -> void:
	# Draw a simple yellow crown above the ship at the given position.
	# Crown: triangle points and a base line
	var crown_color = Color(1.0, 0.9, 0.2, 1.0)
	var base_y = pos.y + 8
	var points = [
		pos + Vector2(-12, 8),
		pos + Vector2(-6, -8),
		pos + Vector2(0, 4),
		pos + Vector2(6, -8),
		pos + Vector2(12, 8)
	]
	draw_polyline(points, crown_color, 3.0)
	draw_line(points[0], points[4], crown_color, 3.0)
	# Optionally, draw small circles for crown jewels
	for i in [1, 2, 3]:
		draw_circle(points[i], 2.5, Color(1.0, 0.7, 0.2, 1.0))

func _draw_debug_overlay(ship_state: DriftTypes.DriftShipState, tick: int) -> void:
	# 1) Predicted position marker (same as current sim position in this phase).
	var predicted_position: Vector2 = ship_state.position
	draw_circle(predicted_position, 3.5, Color(0.2, 0.9, 1.0, 1.0))

	# 2) Velocity vector line (direction + magnitude).
	var velocity_end: Vector2 = predicted_position + ship_state.velocity * VELOCITY_DRAW_SCALE
	draw_line(predicted_position, velocity_end, Color(0.2, 1.0, 0.2, 1.0), 2.0)

	# 3) Text (local tick, next tick, authoritative tick, drift, position, velocity) in top-left.
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 14
	var text_color: Color = Color(1.0, 1.0, 1.0, 1.0)

	var next_tick: int = tick + 1
	var peer_id_text: String = "n/a"
	if enet_peer != null:
		var pid: int = enet_peer.get_unique_id()
		if pid != 0:
			peer_id_text = str(pid)

	var pos_text: String = "(%.2f, %.2f)" % [ship_state.position.x, ship_state.position.y]
	var vel_text: String = "(%.2f, %.2f)" % [ship_state.velocity.x, ship_state.velocity.y]
	var drift_distance: float = 0.0
	if authoritative_ship_state != null:
		drift_distance = ship_state.position.distance_to(authoritative_ship_state.position)

	var ship_id_text: String = "n/a"
	if local_ship_id >= 0:
		ship_id_text = str(local_ship_id)

	draw_string(font, Vector2(8.0, 18.0), "Conn: %s  Auth: %s  Peer: %s  Ship: %s" % [str(connected), str(has_authoritative), peer_id_text, ship_id_text], HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, text_color)
	if not has_authoritative:
		draw_string(font, Vector2(8.0, 36.0), "WAITING FOR SNAPSHOT...", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, text_color)

	draw_string(font, Vector2(8.0, 54.0), "Local: %d" % tick, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, text_color)
	draw_string(font, Vector2(8.0, 72.0), "Send:  %d" % next_tick, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, text_color)
	draw_string(font, Vector2(8.0, 90.0), "Auth:  %d" % authoritative_tick, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, text_color)
	draw_string(font, Vector2(8.0, 108.0), "Drift: %.2f" % drift_distance, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, text_color)
	draw_string(font, Vector2(8.0, 126.0), "Pos:   %s" % pos_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, text_color)
	draw_string(font, Vector2(8.0, 144.0), "Vel:   %s" % vel_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, text_color)

	# Remote ships debug
	draw_string(font, Vector2(8.0, 162.0), "Remote ships: %d (tick %d)" % [remote_ships.size(), remote_tick], HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, text_color)


func _on_connected_to_server() -> void:
	connected = true
	is_connected = true
	_hello_sent = false

	# Reset client net/sim sync state on connect.
	authoritative_tick = -1
	has_authoritative = false
	authoritative_ship_state = null
	input_history.clear()
	snapshot_history.clear()

	# Wait for welcome packet to assign ship_id.
	local_ship_id = -1
	world.tick = 0
	world.ships.clear()
	latest_snapshot = DriftTypes.DriftWorldSnapshot.new(0, {})
	queue_redraw()

	print("Connected to server ", SERVER_HOST, ":", SERVER_PORT)
	_send_hello()
	
	# Hide connection UI and start playing
	show_connect_ui = false
	connection_status_message = "Connected to " + SERVER_HOST
	_update_ui_visibility()


func _draw_connection_ui() -> void:
	var viewport_size := get_viewport_rect().size
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 20
	var title_size: int = 32
	
	# Get camera offset to draw in screen space
	var cam_offset := Vector2.ZERO
	if cam:
		cam_offset = cam.position - viewport_size * 0.5
	
	# Dark background
	draw_rect(Rect2(cam_offset, viewport_size), Color(0.1, 0.1, 0.15, 0.95))
	
	# Title
	var title := "DRIFTLINE - SERVER CONNECTION"
	var title_pos := cam_offset + Vector2(0.0, 100.0)
	draw_string(font, title_pos, title, HORIZONTAL_ALIGNMENT_CENTER, viewport_size.x, title_size, Color.WHITE)
	
	# Server address display
	var addr_label := "Server Address: " + server_address
	var addr_pos := cam_offset + Vector2(0.0, 200.0)
	draw_string(font, addr_pos, addr_label, HORIZONTAL_ALIGNMENT_CENTER, viewport_size.x, font_size, Color(0.8, 0.8, 1.0))
	
	# Status message
	var status_pos := cam_offset + Vector2(0.0, 250.0)
	var status_color := Color(1.0, 1.0, 0.5) if is_connected else Color(0.7, 0.7, 0.7)
	draw_string(font, status_pos, connection_status_message, HORIZONTAL_ALIGNMENT_CENTER, viewport_size.x, font_size, status_color)
	
	# Instructions
	var instructions := [
		"",
		"Press ENTER to connect to server",
		"Press O for offline mode (local play only)",
		"Press M to open Map Editor",
		"Press T to open Tilemap Editor",
		"",
		"In offline mode: no server sync, collision still works"
	]
	
	var y := 320.0
	for line in instructions:
		var line_pos := cam_offset + Vector2(0.0, y)
		var color := Color(0.6, 0.6, 0.6) if line == "" else Color(0.9, 0.9, 0.9)
		draw_string(font, line_pos, line, HORIZONTAL_ALIGNMENT_CENTER, viewport_size.x, font_size - 2, color)
		y += 30


func _input(event: InputEvent) -> void:
	# In-game ESC menu toggle (does not pause the sim)
	if not show_connect_ui:
		if event.is_action_pressed("drift_toggle_pause_menu"):
			_set_pause_menu_visible(not pause_menu_visible)
			get_viewport().set_input_as_handled()
			return

	if show_connect_ui:
		if event.is_action_pressed("drift_menu_connect"):
			_attempt_server_connection()
		elif event.is_action_pressed("drift_menu_offline"):
			_start_offline_mode()
		elif event.is_action_pressed("drift_open_map_editor"):
			_open_map_editor()
		elif event.is_action_pressed("drift_open_tilemap_editor"):
			_open_tilemap_editor()


func _build_pause_menu_ui() -> void:
	pause_menu_layer = CanvasLayer.new()
	pause_menu_layer.layer = 100
	pause_menu_layer.visible = false
	add_child(pause_menu_layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_menu_layer.add_child(root)

	pause_menu_panel = Panel.new()
	pause_menu_panel.custom_minimum_size = Vector2(360, 140)
	pause_menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_menu_panel.position = -pause_menu_panel.custom_minimum_size * 0.5
	pause_menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(pause_menu_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	vbox.add_theme_constant_override("margin_left", 14)
	vbox.add_theme_constant_override("margin_right", 14)
	vbox.add_theme_constant_override("margin_top", 14)
	vbox.add_theme_constant_override("margin_bottom", 14)
	pause_menu_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Menu"
	vbox.add_child(title)

	var back_btn := Button.new()
	back_btn.text = "Back to Menu"
	back_btn.pressed.connect(_on_pause_back_to_menu_pressed)
	vbox.add_child(back_btn)

	var hint := Label.new()
	hint.text = "(Esc to close)"
	hint.modulate = Color(0.8, 0.8, 0.8, 1.0)
	vbox.add_child(hint)


func _set_pause_menu_visible(visible: bool) -> void:
	pause_menu_visible = visible
	if pause_menu_layer != null:
		pause_menu_layer.visible = visible and not show_connect_ui


func _on_pause_back_to_menu_pressed() -> void:
	_return_to_menu()


func _return_to_menu() -> void:
	# Close networking.
	if enet_peer != null:
		# Best-effort close; server will see disconnect.
		enet_peer.close()
		enet_peer = null

	connected = false
	is_connected = false
	has_authoritative = false
	authoritative_tick = -1
	authoritative_ship_state = null
	local_ship_id = -1
	input_history.clear()
	snapshot_history.clear()
	allow_offline_mode = false

	# Reset world state to a clean baseline.
	world = DriftWorld.new()
	_load_client_map()
	latest_snapshot = DriftTypes.DriftWorldSnapshot.new(0, {})

	show_connect_ui = true
	connection_status_message = "Enter server address to connect"
	_set_pause_menu_visible(false)
	_update_ui_visibility()
	queue_redraw()


func _open_map_editor() -> void:
	# Leave the startup screen and open the map editor scene.
	show_connect_ui = false
	_update_ui_visibility()
	get_tree().change_scene_to_packed(MapEditorScene)


func _open_tilemap_editor() -> void:
	# Leave the startup screen and open the runtime Tilemap Editor tool.
	show_connect_ui = false
	_update_ui_visibility()
	get_tree().change_scene_to_packed(TilemapEditorScene)


func _attempt_server_connection() -> void:
	connection_status_message = "Connecting to " + server_address + "..."
	queue_redraw()
	_setup_networking()


func _start_offline_mode() -> void:
	show_connect_ui = false
	allow_offline_mode = true
	local_ship_id = 1
	world.add_ship(local_ship_id, DriftConstants.ARENA_CENTER)
	connection_status_message = "OFFLINE MODE"
	print("Starting offline mode (no server)")
	_update_ui_visibility()


func _update_ui_visibility() -> void:
	"""Hide/show HUD and other game elements based on connection UI state."""
	var hud := get_node_or_null("HUD")
	if hud:
		hud.visible = not show_connect_ui
	
	var starfield := get_node_or_null("Starfield")
	if starfield:
		starfield.visible = not show_connect_ui

	var tilemap_bg := get_node_or_null("TileMapBG")
	if tilemap_bg:
		tilemap_bg.visible = not show_connect_ui
	var tilemap_solid := get_node_or_null("TileMapSolid")
	if tilemap_solid:
		tilemap_solid.visible = not show_connect_ui
	var tilemap_fg := get_node_or_null("TileMapFG")
	if tilemap_fg:
		tilemap_fg.visible = not show_connect_ui
	
	var label := get_node_or_null("Label")
	if label:
		label.visible = not show_connect_ui

	# Pause menu is never shown over the connection UI.
	_set_pause_menu_visible(pause_menu_visible)


func _send_hello() -> void:
	if _hello_sent:
		return
	if not is_connected:
		return
	if enet_peer == null:
		return
	if player_username.strip_edges() == "":
		return

	var packet: PackedByteArray = DriftNet.pack_hello(player_username)
	enet_peer.set_transfer_channel(NET_CHANNEL)
	enet_peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	enet_peer.set_target_peer(1)
	enet_peer.put_packet(packet)
	_hello_sent = true


func _on_connection_failed() -> void:
	connected = false
	is_connected = false
	has_authoritative = false
	authoritative_tick = -1
	authoritative_ship_state = null
	local_ship_id = -1
	input_history.clear()
	snapshot_history.clear()
	push_error("Failed to connect to server")
	
	# Show connection UI again
	show_connect_ui = true
	connection_status_message = "Connection failed. Press ENTER to retry."
	_update_ui_visibility()
	queue_redraw()


func _on_server_disconnected() -> void:
	connected = false
	is_connected = false
	has_authoritative = false
	authoritative_tick = -1
	authoritative_ship_state = null
	local_ship_id = -1
	input_history.clear()
	snapshot_history.clear()
	print("Disconnected from server")
	
	# Show connection UI again
	show_connect_ui = true
	allow_offline_mode = false
	connection_status_message = "Disconnected from server. Press ENTER to reconnect."
	_update_ui_visibility()
	queue_redraw()


func _poll_network_packets() -> void:
	if enet_peer == null:
		return

	# Required when not using SceneMultiplayer.
	enet_peer.poll()
	_update_connection_state()

	# Drain ALL pending packets this frame.
	# - Apply welcome packets immediately (ship_id assignment)
	# - If multiple snapshots arrive at once, keep only the newest (highest tick)
	#   and apply it once at the end.
	var best_snapshot_tick: int = -1
	var best_snapshot_dict: Dictionary = {}

	while enet_peer.get_available_packet_count() > 0:
		# Read channel/peer BEFORE consuming the packet.
		var channel: int = enet_peer.get_packet_channel()
		var _sender_id: int = enet_peer.get_packet_peer()
		var bytes: PackedByteArray = enet_peer.get_packet()
		if channel != NET_CHANNEL:
			continue

		var pkt_type: int = DriftNet.get_packet_type(bytes)
		if pkt_type == DriftNet.PKT_WELCOME:
			var w: Dictionary = DriftNet.unpack_welcome_packet(bytes)
			if not w.is_empty():
				var server_map_path: String = String(w.get("map_path", ""))
				var server_map_version: int = int(w.get("map_version", 0))
				var server_checksum: PackedByteArray = w.get("map_checksum", PackedByteArray())
				if server_map_path != "" and server_map_path != CLIENT_MAP_PATH:
					push_error("Map path mismatch. server='" + server_map_path + "' client='" + CLIENT_MAP_PATH + "'")
					connection_status_message = "Map mismatch with server. Load the same map path." 
					show_connect_ui = true
					allow_offline_mode = false
					is_connected = false
					_update_ui_visibility()
					if enet_peer != null:
						enet_peer.close()
						enet_peer = null
					return
				if server_map_version != 0 and client_map_version != 0 and server_map_version != client_map_version:
					push_error("Map version mismatch. server=" + str(server_map_version) + " client=" + str(client_map_version))
					connection_status_message = "Map mismatch with server. Map version differs." 
					show_connect_ui = true
					allow_offline_mode = false
					is_connected = false
					_update_ui_visibility()
					if enet_peer != null:
						enet_peer.close()
						enet_peer = null
					return
				if server_checksum.size() > 0 and client_map_checksum.size() > 0 and server_checksum != client_map_checksum:
					var server_hex := DriftMap.bytes_to_hex(server_checksum)
					var client_hex := DriftMap.bytes_to_hex(client_map_checksum)
					push_error("Map checksum mismatch. server=" + server_hex + " client=" + client_hex)
					connection_status_message = "Map mismatch with server. Load the same map JSON." 
					show_connect_ui = true
					allow_offline_mode = false
					is_connected = false
					_update_ui_visibility()
					if enet_peer != null:
						enet_peer.close()
						enet_peer = null
					return

				local_ship_id = w["ship_id"]
				# Authoritative rules (must match server for prediction).
				var ruleset_json: String = String(w.get("ruleset_json", "")).strip_edges()
				if ruleset_json != "":
					var json := JSON.new()
					var parse_err := json.parse(ruleset_json)
					if parse_err != OK or typeof(json.data) != TYPE_DICTIONARY:
						push_error("Ruleset JSON parse failed from welcome packet")
						connection_status_message = "Ruleset mismatch with server."
						show_connect_ui = true
						allow_offline_mode = false
						is_connected = false
						_update_ui_visibility()
						if enet_peer != null:
							enet_peer.close()
							enet_peer = null
						return
					var root: Dictionary = json.data
					var validated := DriftValidate.validate_ruleset(root)
					if not bool(validated.get("ok", false)):
						push_error("Ruleset validation failed from welcome packet")
						connection_status_message = "Ruleset mismatch with server."
						show_connect_ui = true
						allow_offline_mode = false
						is_connected = false
						_update_ui_visibility()
						if enet_peer != null:
							enet_peer.close()
							enet_peer = null
						return
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
				if DEBUG_NET:
					print("[NET] assigned ship_id=", local_ship_id)
				# Reset local baseline.
				world.tick = 0
				world.ships.clear()
				world.add_ship(local_ship_id, SPAWN_POSITION)
				input_history.clear()
				authoritative_tick = -1
				authoritative_ship_state = null
				has_authoritative = false
			continue

		if pkt_type == DriftNet.PKT_PRIZE_EVENT:
			var ev: Dictionary = DriftNet.unpack_prize_event_packet(bytes)
			if ev.is_empty():
				continue
			if int(ev.get("event_type", 0)) == DriftNet.PRIZE_EVENT_PICKUP and int(ev.get("ship_id", -1)) == local_ship_id:
				if _prize_audio != null and _prize_audio.stream != null:
					_prize_audio.play()
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

	# Transition handling.
	if status == MultiplayerPeer.CONNECTION_CONNECTED:
		_on_connected_to_server()
	elif status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		if last_connection_status == MultiplayerPeer.CONNECTION_CONNECTING:
			_on_connection_failed()
		elif last_connection_status == MultiplayerPeer.CONNECTION_CONNECTED:
			_on_server_disconnected()

	last_connection_status = status


func _handle_packet(bytes: PackedByteArray) -> void:
	var pkt_type: int = DriftNet.get_packet_type(bytes)
	if pkt_type == DriftNet.PKT_SNAPSHOT:
		var snap_dict: Dictionary = DriftNet.unpack_snapshot_packet(bytes)
		if snap_dict.is_empty():
			return

		_apply_snapshot_dict(snap_dict)



func _apply_snapshot_dict(snap_dict: Dictionary) -> void:
	var snap_tick: int = snap_dict["tick"]
	if snap_tick <= authoritative_tick:
		return
	if local_ship_id < 0:
		return

	# --- Interpolation snapshot shift ---
	# Shift A <- B, then B <- new snapshot
	snap_a_tick = snap_b_tick
	snap_a_time_ms = snap_b_time_ms
	snap_a_ships = snap_b_ships.duplicate(true)
	snap_a_ball_pos = snap_b_ball_pos

	snap_b_tick = snap_tick
	snap_b_time_ms = Time.get_ticks_msec()
	snap_b_ships = {}

	var ships: Array = snap_dict["ships"]
	# Prize pickup SFX: driven by authoritative prize_events when present.
	if _prize_audio != null and snap_dict.has("prize_events") and (snap_dict.get("prize_events") is Array):
		for ev in (snap_dict.get("prize_events") as Array):
			if ev == null or typeof(ev) != TYPE_DICTIONARY:
				continue
			var d: Dictionary = ev
			if String(d.get("type", "")) != "pickup":
				continue
			if int(d.get("ship_id", -1)) == local_ship_id:
				_prize_audio.play()
				break
	# Authoritative bullets (render remote bullets; local bullets are predicted).
	authoritative_bullets.clear()
	if snap_dict.has("bullets") and (snap_dict.get("bullets") is Array):
		var bs: Array = snap_dict.get("bullets")
		for b in bs:
			if b == null:
				continue
			authoritative_bullets.append(DriftTypes.DriftBulletState.new(int(b.id), int(b.owner_id), b.position, b.velocity, int(b.spawn_tick), int(b.die_tick), int(b.bounces_left)))
	# Authoritative prizes (render only; no client simulation).
	authoritative_prizes.clear()
	if snap_dict.has("prizes") and (snap_dict.get("prizes") is Array):
		var ps: Array = snap_dict.get("prizes")
		for p in ps:
			if p == null:
				continue
			authoritative_prizes.append(DriftTypes.DriftPrizeState.new(int(p.id), p.pos, snap_tick, int(p.despawn_tick), int(p.kind), bool(p.is_negative), bool(p.is_death_drop)))
	# Track remote ships
	remote_ships.clear()
	var local_pos_found: bool = false
	var local_pos: Vector2 = Vector2.ZERO
	for ship_state in ships:
		if ship_state.id == local_ship_id:
			local_pos_found = true
			local_pos = ship_state.position
			authoritative_tick = snap_tick
			authoritative_ship_state = ship_state
			has_authoritative = true
			snapshot_history[snap_tick] = DriftTypes.DriftShipState.new(
				ship_state.id,
				ship_state.position,
				ship_state.velocity,
				ship_state.rotation,
				"",
				int(ship_state.bounty),
				int(ship_state.gun_level),
				int(ship_state.bomb_level),
				bool(ship_state.multi_fire_enabled),
				int(ship_state.bullet_bounce_bonus),
				int(ship_state.engine_shutdown_until_tick),
				int(ship_state.top_speed_bonus),
				int(ship_state.thruster_bonus),
				int(ship_state.recharge_bonus),
				float(ship_state.energy)
			)
			_reconcile_to_authoritative_snapshot(snap_tick, ship_state, authoritative_bullets)
		else:
			# Store a deep copy for remote rendering
			var state_copy = DriftTypes.DriftShipState.new(
				ship_state.id,
				ship_state.position,
				ship_state.velocity,
				ship_state.rotation,
				"",
				int(ship_state.bounty),
				int(ship_state.gun_level),
				int(ship_state.bomb_level),
				bool(ship_state.multi_fire_enabled),
				int(ship_state.bullet_bounce_bonus),
				int(ship_state.engine_shutdown_until_tick),
				int(ship_state.top_speed_bonus),
				int(ship_state.thruster_bonus),
				int(ship_state.recharge_bonus),
				float(ship_state.energy)
			)
			remote_ships[ship_state.id] = state_copy
			snap_b_ships[ship_state.id] = state_copy
	remote_tick = snap_tick

	# Store authoritative ball state from snapshot
	if snap_dict.has("ball_position"):
		ball_position = snap_dict["ball_position"]
		snap_b_ball_pos = ball_position
	else:
		ball_position = Vector2.ZERO
		snap_b_ball_pos = Vector2.ZERO
	if snap_dict.has("ball_velocity"):
		ball_velocity = snap_dict["ball_velocity"]
	else:
		ball_velocity = Vector2.ZERO


func _reconcile_to_authoritative_snapshot(snapshot_tick: int, auth_state: DriftTypes.DriftShipState, auth_bullets_for_tick: Array) -> void:
	# If the snapshot tick is ahead of our current tick (e.g. after reconnect),
	# snap to the authoritative tick/state and continue from there.
	var current_tick: int = world.tick

	if DEBUG_NET:
		print("[NET] RECONCILING ", snapshot_tick, " -> ", current_tick)

	# 1) Overwrite local ship state with authoritative.
	var local_state: DriftTypes.DriftShipState = world.ships.get(local_ship_id)
	if local_state == null:
		return

	local_state.position = auth_state.position
	local_state.velocity = auth_state.velocity
	local_state.rotation = auth_state.rotation
	local_state.bounty = int(auth_state.bounty)
	local_state.gun_level = int(auth_state.gun_level)
	local_state.bomb_level = int(auth_state.bomb_level)
	local_state.multi_fire_enabled = bool(auth_state.multi_fire_enabled)
	local_state.bullet_bounce_bonus = int(auth_state.bullet_bounce_bonus)
	local_state.engine_shutdown_until_tick = int(auth_state.engine_shutdown_until_tick)
	local_state.top_speed_bonus = int(auth_state.top_speed_bonus)
	local_state.thruster_bonus = int(auth_state.thruster_bonus)
	local_state.recharge_bonus = int(auth_state.recharge_bonus)
	local_state.energy = float(auth_state.energy)

	# 2) Rewind/snap world.tick to the snapshot tick.
	world.tick = snapshot_tick

	# Reset predicted bullets to the authoritative baseline for the LOCAL player.
	if world != null:
		world.bullets.clear()
		for b in auth_bullets_for_tick:
			if b == null:
				continue
			if int(b.owner_id) != local_ship_id:
				continue
			world.bullets[int(b.id)] = DriftTypes.DriftBulletState.new(int(b.id), int(b.owner_id), b.position, b.velocity, int(b.spawn_tick), int(b.die_tick), int(b.bounces_left))
		# Ensure edge-triggered fire state matches the snapshot baseline.
		var base_cmd: DriftTypes.DriftInputCmd = input_history.get(snapshot_tick, DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false))
		world._prev_fire_by_ship[local_ship_id] = bool(base_cmd.fire_primary)

	# If we're snapping forward (snapshot_tick >= previous current_tick), no replay is needed.
	if snapshot_tick >= current_tick:
		latest_snapshot = _build_snapshot_from_current_world()
		queue_redraw()
		_prune_input_history(authoritative_tick)
		return

	# 3) Replay stored inputs from snapshot_tick+1 up to the original current_tick.
	var replay_snapshot: DriftTypes.DriftWorldSnapshot = DriftTypes.DriftWorldSnapshot.new(world.tick, {})
	for t in range(snapshot_tick + 1, current_tick + 1):
		var cmd: DriftTypes.DriftInputCmd = input_history.get(t, DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false))
		replay_snapshot = world.step_tick({ local_ship_id: cmd })

	# After replay, world.tick should equal current_tick again.
	if DEBUG_NET and world.tick != current_tick:
		print("[NET] replay tick mismatch: expected=", current_tick, " actual=", world.tick)

	# Update the rendered snapshot to match the post-replay predicted world.
	if replay_snapshot.ships.size() > 0:
		latest_snapshot = replay_snapshot
	else:
		latest_snapshot = _build_snapshot_from_current_world()
	queue_redraw()

	# 4) Prune history up to the authoritative tick (inclusive).
	_prune_input_history(authoritative_tick)


func _build_snapshot_from_current_world() -> DriftTypes.DriftWorldSnapshot:
	var ships_dict: Dictionary = {}
	if local_ship_id < 0:
		return DriftTypes.DriftWorldSnapshot.new(world.tick, ships_dict)
	var state: DriftTypes.DriftShipState = world.ships.get(local_ship_id)
	if state != null:
		ships_dict[local_ship_id] = DriftTypes.DriftShipState.new(
			state.id,
			state.position,
			state.velocity,
			state.rotation,
			state.username,
			state.bounty,
			state.gun_level,
			state.bomb_level,
			state.multi_fire_enabled,
			state.bullet_bounce_bonus,
			state.engine_shutdown_until_tick,
			state.top_speed_bonus,
			state.thruster_bonus,
			state.recharge_bonus,
			state.energy
		)
	# Include predicted local bullets for debug/prediction.
	var local_bullets: Array = []
	if world != null and typeof(world.bullets) == TYPE_DICTIONARY:
		var ids: Array = world.bullets.keys()
		ids.sort()
		for bid in ids:
			var b = world.bullets.get(bid)
			if b == null:
				continue
			if int(b.owner_id) != local_ship_id:
				continue
			local_bullets.append(DriftTypes.DriftBulletState.new(int(b.id), int(b.owner_id), b.position, b.velocity, int(b.spawn_tick), int(b.die_tick), int(b.bounces_left)))
	return DriftTypes.DriftWorldSnapshot.new(world.tick, ships_dict, Vector2.ZERO, Vector2.ZERO, -1, local_bullets)


func _prune_input_history(upto_tick_inclusive: int) -> void:
	if upto_tick_inclusive < 0:
		return

	var keys: Array = input_history.keys()
	for k in keys:
		if int(k) <= upto_tick_inclusive:
			input_history.erase(k)
