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
const DriftActions = preload("res://client/input/actions.gd")
const ReplayRingBuffer = preload("res://client/replay/replay_ring_buffer.gd")
const ReplayDumpWriter = preload("res://client/replay/replay_dump_writer.gd")
const ReplayMeta = preload("res://client/replay/replay_meta.gd")
const BugReportWriter = preload("res://client/replay/bug_report_writer.gd")
const SpriteFontLabelScript = preload("res://client/SpriteFontLabel.gd")
const DriftTeamColors = preload("res://client/team_colors.gd")
const DriftShipAtlas = preload("res://client/ship_atlas.gd")
const SHIPS_TEX_FALLBACK: Texture2D = preload("res://client/graphics/ships/ships.png")

var _ships_tex: Texture2D = null
const LevelIO = preload("res://client/scripts/maps/level_io.gd")
const MapEditorScene: PackedScene = preload("res://client/scenes/editor/MapEditor.tscn")
const TilemapEditorScene: PackedScene = preload("res://tools/tilemap_editor/TilemapEditor.tscn")
const EscMenuScene: PackedScene = preload("res://client/scenes/EscMenu.tscn")
const OptionsMenuScene: PackedScene = preload("res://client/ui/options_menu.tscn")
const PrizeFeedbackPipeline = preload("res://client/ui/prize_feedback_pipeline.gd")
const DriftPrizeTypes = preload("res://client/ui/prize_types.gd")

const PRIZE_TEX: Texture2D = preload("res://client/graphics/entities/prizes.png")
const PRIZE_FRAME_PX: int = 16
const PRIZE_FRAME_COUNT: int = 10
const PRIZE_ANIM_FPS: float = 12.0
const PRIZE_DRAW_SCALE: float = 1.5
const PRIZE_PICKUP_SFX_PATH: String = "res://client/audio/prize.wav"
const THRUSTER_LOOP_SFX_PATH: String = "res://client/audio/rev.wav"
const BOOST_LOOP_SFX_PATH: String = "res://client/audio/thrust.ogg"

const GUN_SFX_LEVEL_1_PATH: String = "res://client/audio/gun1.wav"
const GUN_SFX_LEVEL_2_PATH: String = "res://client/audio/gun2.wav"
const GUN_SFX_LEVEL_3_PATH: String = "res://client/audio/gun3.wav"
const GUN_SFX_LEVEL_4_PATH: String = "res://client/audio/gun4.wav"

const VELOCITY_DRAW_SCALE: float = 0.10

const SERVER_HOST: String = "127.0.0.1"
const SERVER_PORT: int = 5000

const CLIENT_MAP_PATH: String = "res://maps/default.json"

const DEBUG_NET: bool = false

# Client-only debug UI (must not affect sim determinism).
@export var debug_show_overlay: bool = false

# Optional local debugging: print key/button events received by the client.
@export var debug_log_input_events: bool = false

# Optional local debugging: sanity-check ThrustAudio at runtime.
# If enabled, pressing F8 will attempt to play ThrustAudio and print state.
@export var debug_probe_thrust_audio: bool = false

# Optional local debugging: print thruster audio state transitions.
@export var debug_log_thruster_audio: bool = false

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

var esc_menu: CanvasLayer = null

# Main-menu (connection screen) options UI overlay.
var _main_menu_ui_layer: CanvasLayer = null
var _main_menu_options_panel: Control = null
var _main_menu_options_btn: Button = null
var _options_menu_instance: Control = null

# Wall-bounce audio (driven by shared simulation collision events)
@export var bounce_sound_min_speed: float = 160.0
@export var bounce_sound_cooldown: float = 0.10
var _last_bounce_time_s: float = -999.0
@onready var _bounce_audio: AudioStreamPlayer = get_node_or_null("BounceAudio")

@onready var _rev_audio: AudioStreamPlayer = get_node_or_null("RevAudio")
@onready var _thrust_audio: AudioStreamPlayer = get_node_or_null("ThrustAudio")

var _prize_audio: AudioStreamPlayer = null

# Client-only combat feedback (must not affect sim determinism).
var _gun_audio: AudioStreamPlayer = null
var _gun_streams_by_level: Dictionary = {} # Dictionary[int, AudioStream]
var _muzzle_flashes: Array = [] # Array[Dictionary] {pos: Vector2, expire_tick: int}
var _hit_markers: Array = [] # Array[Dictionary] {pos: Vector2, damage: int, start_tick: int, expire_tick: int}
var _hit_confirm_until_tick: int = -1

var world: DriftWorld

var client_map_checksum: PackedByteArray = PackedByteArray()
var client_map_version: int = 0
var accumulator_seconds: float = 0.0

# Minimap static geometry cache (client-only UI)
var client_map_meta: Dictionary = {}
var client_map_solid_cells: Array = []
var client_map_safe_cells: Array = []

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

# UI thresholds (server-authoritative via validated ruleset).
var ui_low_energy_frac: float = 0.33
var ui_critical_energy_frac: float = 0.15

# Help ticker interrupt edge-trigger flags (client-only; no net/sim changes).
var _help_interrupt_seen_safe_zone_entry: bool = false
var _help_interrupt_seen_first_death: bool = false
var _help_interrupt_seen_energy_critical: bool = false
var _help_interrupt_prev_in_safe_zone: bool = false
var _help_interrupt_prev_dead: bool = false
var _help_interrupt_prev_energy_frac: float = 1.0

# Prize pickup UI feedback (client-only; driven by authoritative snapshots).
var _prize_feedback_pipeline = PrizeFeedbackPipeline.new()

# Client-only inventory counts for HUD left-stack.
# NOTE: The authoritative sim does not currently replicate inventory counts,
# so we derive these from authoritative prize_events (and later can decrement
# on authoritative use events when those exist).
var _ui_inventory_counts: Dictionary = {
	&"burst": 0,
	&"repel": 0,
	&"decoy": 0,
	&"thor": 0,
	&"brick": 0,
	&"rocket": 0,
	&"teleport": 0,
}


# Toast duration (~1s) in deterministic ticks.
const PRIZE_TOAST_DURATION_MS: int = 1000
const PRIZE_TOAST_DURATION_TICKS: int = int((PRIZE_TOAST_DURATION_MS * DriftConstants.TICK_RATE + 999) / 1000)


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

# Client-only replay capture (debug/dev tooling).
var _replay_ring: ReplayRingBuffer = null
var _replay_ring_enabled: bool = false
var _replay_toggle_keycode: int = 0
var _replay_save_keycode: int = 0

# Last known mismatch (best-effort) to include in manual bug reports.
var _last_mismatch_reason: String = ""
var _last_mismatch_detail: Dictionary = {}

# Optional debugging: store last authoritative state per tick.
var snapshot_history: Dictionary = {} # Dictionary[int, DriftTypes.DriftShipState]


# Door tiles (animated + dynamic collision)
var _door_cells: Array = [] # Array[Dictionary] { cell: Vector2i, orient: String }
var _tilemap_solid: TileMap = null
var _last_door_anim_key: int = -999999



func _ready() -> void:
	# Ensure this node receives global input events.
	# Some platforms/scenes can end up with input processing disabled, which would
	# leave the client stuck on the connection UI (HUD hidden).
	set_process_input(true)

	_ships_tex = DriftShipAtlas.get_ships_texture()
	if _ships_tex == null:
		_ships_tex = SHIPS_TEX_FALLBACK
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
	_build_main_menu_ui()

	_ensure_ui_escape_menu_action_has_escape_binding()
	esc_menu = EscMenuScene.instantiate()
	add_child(esc_menu)
	# Make sure the overlay starts closed.
	if esc_menu.has_method("close"):
		esc_menu.call("close")
	# Debug: allow saving replay ring from the ESC menu without pausing.
	if esc_menu != null and esc_menu.has_signal("save_bug_report_requested"):
		esc_menu.connect("save_bug_report_requested", Callable(self, "_on_esc_menu_save_bug_report_requested"))

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

	# Gun SFX (client-side). Created programmatically to avoid scene edits.
	_gun_audio = AudioStreamPlayer.new()
	_gun_audio.name = "GunAudio"
	_gun_streams_by_level = {
		1: load(GUN_SFX_LEVEL_1_PATH),
		2: load(GUN_SFX_LEVEL_2_PATH),
		3: load(GUN_SFX_LEVEL_3_PATH),
		4: load(GUN_SFX_LEVEL_4_PATH),
	}
	# Default to level 1 stream when present.
	if _gun_streams_by_level.has(1) and _gun_streams_by_level[1] is AudioStream:
		_gun_audio.stream = _gun_streams_by_level[1]
	add_child(_gun_audio)

	# Input regression guard for local UX: ensure the boost modifier action is bound to Shift.
	# Some platforms/layouts may not match a purely-physical SHIFT binding; using keycode here
	# preserves the action-based input contract without hardcoding keys in gameplay logic.
	_ensure_modifier_action_has_shift_binding()
	# Input UX guard: core actions should continue to work while Shift is held (Shift is a modifier
	# for abilities/afterburner, but should not cancel movement/fire bindings).
	_ensure_actions_work_with_shift_held()

	# Client-only replay ring buffer.
	_replay_ring = ReplayRingBuffer.new(int(30 * DriftConstants.TICK_RATE), int(DriftConstants.TICK_RATE))
	# Dev hotkeys (avoid hardcoded key constants).
	_replay_toggle_keycode = int(OS.find_keycode_from_string("F9"))
	_replay_save_keycode = int(OS.find_keycode_from_string("F10"))

	if debug_probe_thrust_audio:
		_ensure_debug_probe_action()

	# Thruster loop SFX (W/S). Prefer scene-provided player, but ensure stream loops.
	if _rev_audio != null:
		if _rev_audio.stream == null:
			var rev_sfx := load(THRUSTER_LOOP_SFX_PATH)
			if rev_sfx is AudioStream:
				_rev_audio.stream = rev_sfx
		if _rev_audio.stream is AudioStreamWAV:
			var wav: AudioStreamWAV = _rev_audio.stream
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		# Ensure we start silent.
		_rev_audio.stop()

	# Boost loop SFX (Shift + thrust). Prefer scene-provided player, but ensure stream loops.
	if _thrust_audio != null:
		if _thrust_audio.stream == null:
			var boost_sfx := load(BOOST_LOOP_SFX_PATH)
			if boost_sfx is AudioStream:
				_thrust_audio.stream = boost_sfx
		if _thrust_audio.stream is AudioStreamWAV:
			var wav2: AudioStreamWAV = _thrust_audio.stream
			wav2.loop_mode = AudioStreamWAV.LOOP_FORWARD
		elif _thrust_audio.stream is AudioStreamOggVorbis:
			var ogg: AudioStreamOggVorbis = _thrust_audio.stream
			ogg.loop = true
		# Ensure we start silent.
		_thrust_audio.stop()

	# Optional: unlimited redraw rate for testing
	Engine.max_fps = 0
	
	# Show connection UI and hide game elements
	show_connect_ui = true
	connection_status_message = "Enter server address to connect"
	_update_ui_visibility()
	_update_main_menu_ui_visibility()


func _ensure_actions_work_with_shift_held() -> void:
	# Godot key events include modifier flags (shift/ctrl/alt/meta). If an action is bound to a key
	# with shift_pressed=false, it may stop matching while Shift is held. Duplicate key bindings with
	# shift_pressed=true so movement/fire continues during afterburner and chorded inputs.
	for action in [
		StringName("drift_thrust_forward"),
		StringName("drift_thrust_reverse"),
		StringName("drift_rotate_left"),
		StringName("drift_rotate_right"),
		StringName("drift_fire_primary"),
		StringName("drift_fire_secondary"),
	]:
		_ensure_action_has_shift_variant(action)


func _ensure_action_has_shift_variant(action: StringName) -> void:
	if not InputMap.has_action(action):
		return
	var events: Array = InputMap.action_get_events(action)
	# Build a small set of signatures so we don't add duplicates.
	var have: Dictionary = {}
	for ev in events:
		if ev is InputEventKey:
			var k := ev as InputEventKey
			var sig := "%d|%d|%d|%d|%d|%d" % [int(k.keycode), int(k.physical_keycode), int(k.shift_pressed), int(k.ctrl_pressed), int(k.alt_pressed), int(k.meta_pressed)]
			have[sig] = true

	for ev in events:
		if ev is InputEventKey:
			var k2 := ev as InputEventKey
			# Only add a Shift-held variant if the binding is not already Shift-specific.
			if bool(k2.shift_pressed):
				continue
			# Skip invalid "empty" key bindings.
			if int(k2.keycode) == 0 and int(k2.physical_keycode) == 0:
				continue
			var shifted := InputEventKey.new()
			shifted.keycode = k2.keycode
			shifted.physical_keycode = k2.physical_keycode
			# Some project bindings use keycode=0 with physical_keycode set.
			# That works for plain keys, but can fail to match when modifiers are held.
			# For the Shift-variant, prefer a concrete keycode when available.
			if int(shifted.keycode) == 0 and int(shifted.physical_keycode) != 0:
				shifted.keycode = shifted.physical_keycode
			shifted.shift_pressed = true
			shifted.ctrl_pressed = k2.ctrl_pressed
			shifted.alt_pressed = k2.alt_pressed
			shifted.meta_pressed = k2.meta_pressed
			var sig2 := "%d|%d|%d|%d|%d|%d" % [int(shifted.keycode), int(shifted.physical_keycode), 1, int(shifted.ctrl_pressed), int(shifted.alt_pressed), int(shifted.meta_pressed)]
			if have.has(sig2):
				continue
			InputMap.action_add_event(action, shifted)
			have[sig2] = true


func _ensure_modifier_action_has_shift_binding() -> void:
	var action := StringName("drift_modifier_ability")
	if not InputMap.has_action(action):
		return
	var shift_keycode: int = int(DriftActions.SHIFT_KEYCODE)
	var events: Array = InputMap.action_get_events(action)
	for ev in events:
		if ev is InputEventKey:
			var k := ev as InputEventKey
			# Accept either keycode or physical_keycode bindings.
			if (int(k.keycode) != 0 and int(k.keycode) == shift_keycode) or int(k.physical_keycode) == shift_keycode:
				return

	# Add a keycode-based SHIFT binding (applies to either shift key and survives layout differences).
	var shift := InputEventKey.new()
	shift.keycode = shift_keycode
	shift.physical_keycode = 0
	InputMap.action_add_event(action, shift)


func _ensure_ui_escape_menu_action_has_escape_binding() -> void:
	var action := StringName("ui_escape_menu")
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var escape_keycode: int = int(DriftActions.ESCAPE_KEYCODE)
	var events: Array = InputMap.action_get_events(action)
	for ev in events:
		if ev is InputEventKey:
			var k := ev as InputEventKey
			if int(k.keycode) == escape_keycode or int(k.physical_keycode) == escape_keycode:
				return

	var esc := InputEventKey.new()
	esc.keycode = escape_keycode
	esc.physical_keycode = 0
	InputMap.action_add_event(action, esc)


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

	# Cache validated map meta + derived solid/safe cells for UI consumers (e.g., minimap).
	var raw_map: Dictionary = LevelIO.read_map_data(CLIENT_MAP_PATH)
	if not raw_map.is_empty():
		var validated := DriftMap.validate_and_canonicalize(raw_map)
		if bool(validated.get("ok", false)):
			var canonical: Dictionary = validated.get("map", {})
			client_map_meta = canonical.get("meta", {})
			var tileset_name: String = String(client_map_meta.get("tileset", "")).strip_edges()
			var tileset_def := DriftTileDefs.load_tileset(tileset_name)
			if bool(tileset_def.get("ok", false)):
				client_map_solid_cells = DriftTileDefs.build_solid_cells(canonical, tileset_def)
				client_map_safe_cells = DriftTileDefs.build_safe_zone_cells(canonical, tileset_def)
			else:
				client_map_solid_cells = []
				client_map_safe_cells = []
		else:
			client_map_meta = {}
			client_map_solid_cells = []
			client_map_safe_cells = []

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

	# Deterministic RNG seeds for client-side prediction.
	# Must match server logic so spawns/respawns (including safe-zone-first) predict consistently.
	var prize_seed: int = 1
	if client_map_checksum != null and client_map_checksum.size() > 0:
		var acc: int = 0
		var n: int = mini(8, client_map_checksum.size())
		for i in range(n):
			acc = int((acc * 31 + int(client_map_checksum[i])) & 0x7fffffff)
		if acc != 0:
			prize_seed = acc
	world.set_prize_rng_seed(prize_seed)
	var spawn_seed: int = int((prize_seed ^ 0x2f7a3d19) & 0x7fffffff)
	if spawn_seed == 0:
		spawn_seed = 1
	world.set_spawn_rng_seed(spawn_seed)
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
	var safe_zone_cells: Array = DriftTileDefs.build_safe_zone_cells(canonical, tileset_def)
	world.set_solid_tiles(solid_cells)
	world.set_door_tiles(door_cells_raw)
	world.set_safe_zone_tiles(safe_zone_cells)
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
	
	var w_tiles: int = int(meta.get("w", 0))
	var h_tiles: int = int(meta.get("h", 0))
	world.add_boundary_tiles(w_tiles, h_tiles)
	world.set_map_dimensions(w_tiles, h_tiles)
	
	print("Client map loaded: ", w_tiles, "x", h_tiles, " tiles")
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


func _update_thruster_audio() -> void:
	# Only play while in-game and thrusting.
	var thrust_axis: float = 0.0
	var boosting: bool = false
	if not show_connect_ui and (is_connected or allow_offline_mode):
		thrust_axis = Input.get_action_strength("drift_thrust_forward") - Input.get_action_strength("drift_thrust_reverse")
		boosting = Input.is_action_pressed("drift_modifier_ability")
	var is_thrusting: bool = absf(thrust_axis) > 0.01

	# Intended behavior:
	# - Normal thrust (W/S): play rev.wav
	# - Boost thrust (Shift + thrust): play thrust.ogg
	# When boosting, play boost loop and stop the normal rev loop.
	if boosting and is_thrusting and _thrust_audio != null and _thrust_audio.stream != null:
		if _rev_audio != null and _rev_audio.playing:
			_rev_audio.stop()
		if not _thrust_audio.playing:
			_thrust_audio.play()
		return

	# Otherwise, stop boost loop and (optionally) play normal rev loop.
	if _thrust_audio != null and _thrust_audio.playing:
		_thrust_audio.stop()

	if _rev_audio == null or _rev_audio.stream == null:
		return
	if is_thrusting:
		if not _rev_audio.playing:
			_rev_audio.play()
	else:
		if _rev_audio.playing:
			_rev_audio.stop()


func _process(delta: float) -> void:
	# Always poll network even when showing UI
	if enet_peer != null:
		_poll_network_packets()

	# Keep door tiles visually in sync with the local simulation tick.
	_update_door_tilemap_visual()
	
	# Show connection UI if not connected and not in offline mode
	if show_connect_ui:
		_update_thruster_audio()
		queue_redraw()
		return
	
	# Only run game simulation when connected or in offline mode
	if not is_connected and not allow_offline_mode:
		_update_thruster_audio()
		queue_redraw()
		return

	_update_thruster_audio()

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
		# Minimap static geometry (client-only UI)
		if hud.has_method("set_minimap_static") and not client_map_meta.is_empty():
			hud.call("set_minimap_static", client_map_meta, client_map_solid_cells, client_map_safe_cells)

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
				var ec: int = int(ss.energy_current) if ("energy_current" in ss) else int(round(float(ss.energy)))
				var em: int = int(ss.energy_max) if ("energy_max" in ss) else 0
				var wt: int = int(ss.energy_recharge_wait_ticks) if ("energy_recharge_wait_ticks" in ss) else 0
				var ab_on: bool = bool(ss.afterburner_on) if ("afterburner_on" in ss) else false
				var st_on: bool = bool(ss.stealth_on) if ("stealth_on" in ss) else false
				var ck_on: bool = bool(ss.cloak_on) if ("cloak_on" in ss) else false
				var xr_on: bool = bool(ss.xradar_on) if ("xradar_on" in ss) else false
				var aw_on: bool = bool(ss.antiwarp_on) if ("antiwarp_on" in ss) else false
				var in_sz: bool = bool(ss.in_safe_zone) if ("in_safe_zone" in ss) else false
				var sz_used: int = int(ss.safe_zone_time_used_ticks) if ("safe_zone_time_used_ticks" in ss) else 0
				var sz_max: int = int(ss.safe_zone_time_max_ticks) if ("safe_zone_time_max_ticks" in ss) else 0
				var now_tick: int = int(world.tick)
				var dpt: int = int(ss.damage_protect_until_tick) if ("damage_protect_until_tick" in ss) else 0
				var dut: int = int(ss.dead_until_tick) if ("dead_until_tick" in ss) else 0
				var gun_lvl: int = int(ss.gun_level) if ("gun_level" in ss) else 1
				var bomb_lvl: int = int(ss.bomb_level) if ("bomb_level" in ss) else 1
				var mf: bool = bool(ss.multi_fire_enabled) if ("multi_fire_enabled" in ss) else false
				var bb: int = int(ss.bullet_bounce_bonus) if ("bullet_bounce_bonus" in ss) else 0
				# Proximity bombs are not implemented yet; keep false.
				var prox: bool = false
				hud.call(
					"set_ship_stats",
					float(ss.velocity.length()),
					float(rad_to_deg(ss.rotation)),
					float(ec),
					float(em),
					wt,
					ab_on,
					st_on,
					ck_on,
					xr_on,
					aw_on,
					in_sz,
					sz_used,
					sz_max,
					now_tick,
					dpt,
					dut,
					gun_lvl,
					bomb_lvl,
					mf,
					prox,
					bb
				)
				# Minimap dynamic state (client-only UI; uses authoritative snapshot)
				if hud.has_method("set_minimap_dynamic"):
					var my_freq: int = int(ss.freq) if ("freq" in ss) else 0
					var xr_on2: bool = bool(ss.xradar_on) if ("xradar_on" in ss) else false
					var pos2: Vector2 = ss.position if ("position" in ss) else Vector2.ZERO
					hud.call("set_minimap_dynamic", latest_snapshot, local_ship_id, my_freq, pos2, xr_on2)
				# New HUD UX: edge icon stacks.
				if hud.has_method("set_ball_possession") and latest_snapshot != null and ("ball_owner_id" in latest_snapshot):
					hud.call("set_ball_possession", int(latest_snapshot.ball_owner_id) == int(local_ship_id))
				if hud.has_method("set_inventory_counts"):
					hud.call("set_inventory_counts", _ui_inventory_counts)
				# Help ticker interrupt events are driven from authoritative snapshot state,
				# and are edge-triggered (fire once per event type per session).
				if hud.has_method("show_help_interrupt"):
					var now_in_sz: bool = in_sz
					if (not _help_interrupt_seen_safe_zone_entry) and now_in_sz and (not _help_interrupt_prev_in_safe_zone):
						_help_interrupt_seen_safe_zone_entry = true
						hud.call("show_help_interrupt", "Entered safe zone", 3.0)
					_help_interrupt_prev_in_safe_zone = now_in_sz

					var now_dead: bool = (dut > 0 and int(world.tick) < dut)
					if (not _help_interrupt_seen_first_death) and now_dead and (not _help_interrupt_prev_dead):
						_help_interrupt_seen_first_death = true
						hud.call("show_help_interrupt", "You died", 3.0)
					_help_interrupt_prev_dead = now_dead

					var frac: float = 1.0
					if em > 0:
						frac = clampf(float(ec) / float(em), 0.0, 1.0)
					if (not _help_interrupt_seen_energy_critical) and frac <= ui_critical_energy_frac and _help_interrupt_prev_energy_frac > ui_critical_energy_frac:
						_help_interrupt_seen_energy_critical = true
						hud.call("show_help_interrupt", "Energy critical", 3.0)
					_help_interrupt_prev_energy_frac = frac


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

	# Record authoritative input command (pre-prediction mutations) for this tick.
	if _replay_ring_enabled and _replay_ring != null:
		var cmds_for_tick: Dictionary = {local_ship_id: input_cmd}
		_replay_ring.push_tick(next_tick, _encode_input_cmds_sorted(cmds_for_tick))

	input_history[next_tick] = input_cmd
	_send_input_for_tick(next_tick, input_cmd)
	latest_snapshot = world.step_tick({ local_ship_id: input_cmd })
	_play_local_collision_sounds()
	_consume_local_combat_events()

	if DEBUG_NET and world.tick != next_tick:
		on_desync_detected("local_tick_contract_violation", {
			"intended_tick": int(next_tick),
			"actual_tick": int(world.tick),
		})


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


func _consume_local_combat_events() -> void:
	# Drive client-only muzzle flash / shot SFX / hit confirm from predicted sim events.
	if world == null:
		return
	if latest_snapshot == null:
		return
	if local_ship_id < 0:
		return
	var events: Array = world.collision_events
	if events.is_empty():
		_prune_local_combat_fx(int(latest_snapshot.tick))
		return

	var cur_tick: int = int(latest_snapshot.tick)
	for ev in events:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = ev
		var ty: String = String(d.get("type", ""))
		if ty == "bullet_fire":
			if int(d.get("ship_id", -1)) != local_ship_id:
				continue
			var pos_any: Variant = d.get("pos", Vector2.ZERO)
			var pos: Vector2 = pos_any if pos_any is Vector2 else Vector2.ZERO
			_muzzle_flashes.append({
				"pos": pos,
				"expire_tick": cur_tick + 2,
			})
			_play_gun_sfx(int(d.get("level", 1)))
		elif ty == "bullet_hit":
			if int(d.get("attacker_id", -1)) != local_ship_id:
				continue
			var pos2_any: Variant = d.get("pos", Vector2.ZERO)
			var pos2: Vector2 = pos2_any if pos2_any is Vector2 else Vector2.ZERO
			var dmg: int = maxi(0, int(d.get("damage", 0)))
			_hit_confirm_until_tick = maxi(_hit_confirm_until_tick, cur_tick + 6)
			_hit_markers.append({
				"pos": pos2,
				"damage": dmg,
				"start_tick": cur_tick,
				"expire_tick": cur_tick + 20,
			})

	_prune_local_combat_fx(cur_tick)
	queue_redraw()


func _play_gun_sfx(level: int) -> void:
	if _gun_audio == null:
		return
	var lvl: int = clampi(int(level), 1, 4)
	var stream_any: Variant = _gun_streams_by_level.get(lvl)
	if stream_any is AudioStream:
		_gun_audio.stream = stream_any
	# Conservative mix: avoid being too loud.
	_gun_audio.volume_db = -10.0
	_gun_audio.pitch_scale = 1.0
	_gun_audio.play()


func _prune_local_combat_fx(cur_tick: int) -> void:
	# Remove expired transient visuals.
	var kept_flashes: Array = []
	for f in _muzzle_flashes:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		if int((f as Dictionary).get("expire_tick", -1)) >= cur_tick:
			kept_flashes.append(f)
	_muzzle_flashes = kept_flashes

	var kept_hits: Array = []
	for h in _hit_markers:
		if typeof(h) != TYPE_DICTIONARY:
			continue
		if int((h as Dictionary).get("expire_tick", -1)) >= cur_tick:
			kept_hits.append(h)
	_hit_markers = kept_hits


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
	# Ability toggle buttons (edge detection happens in shared sim).
	var stealth_btn: bool = Input.is_action_pressed("drift_ability_stealth")
	var cloak_btn: bool = Input.is_action_pressed("drift_ability_cloak")
	var xradar_btn: bool = Input.is_action_pressed("drift_ability_xradar")
	var antiwarp_btn: bool = Input.is_action_pressed("drift_ability_antiwarp")
	return DriftTypes.DriftInputCmd.new(thrust_axis, rotate_axis, fire_primary, fire_secondary, modifier, stealth_btn, cloak_btn, xradar_btn, antiwarp_btn)


func _ensure_debug_probe_action() -> void:
	var action := StringName("drift_debug_probe_thrust_audio")
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.keycode = int(DriftActions.debug_probe_keycode())
	ev.physical_keycode = ev.keycode
	InputMap.action_add_event(action, ev)


func _debug_print_audio_player_state(p: AudioStreamPlayer, label: String) -> void:
	if p == null:
		print("[audio-probe] %s: null" % label)
		return
	var stream_class := "<null>"
	var stream_len := -1.0
	if p.stream != null:
		stream_class = p.stream.get_class()
		if p.stream.has_method("get_length"):
			stream_len = float(p.stream.call("get_length"))
	var bus_name := p.bus
	var bus_idx := AudioServer.get_bus_index(bus_name)
	var bus_mute := false
	var bus_vol := 0.0
	if bus_idx >= 0:
		bus_mute = AudioServer.is_bus_mute(bus_idx)
		bus_vol = AudioServer.get_bus_volume_db(bus_idx)
	print("[audio-probe] %s: playing=%s vol_db=%.1f pitch=%.2f bus='%s'(idx=%d mute=%s vol_db=%.1f) stream=%s len=%.3f" % [
		label,
		str(p.playing),
		float(p.volume_db),
		float(p.pitch_scale),
		bus_name,
		bus_idx,
		str(bus_mute),
		bus_vol,
		stream_class,
		stream_len,
	])


func _debug_probe_thrust_audio_now() -> void:
	print("[audio-probe] ---- probe start ----")
	_debug_print_audio_player_state(_rev_audio, "RevAudio(before)")
	_debug_print_audio_player_state(_thrust_audio, "ThrustAudio(before)")
	if _thrust_audio == null or _thrust_audio.stream == null:
		push_warning("ThrustAudio missing or has null stream")
		return
	_thrust_audio.play()
	_debug_print_audio_player_state(_thrust_audio, "ThrustAudio(after_play)")
	await get_tree().create_timer(0.10).timeout
	_debug_print_audio_player_state(_thrust_audio, "ThrustAudio(+100ms)")
	print("[audio-probe] ---- probe end ----")


func _unhandled_input(event: InputEvent) -> void:
	# Gameplay input is collected via _collect_input_cmd(); this hook is only for local debugging.
	if debug_probe_thrust_audio and event.is_action_pressed("drift_debug_probe_thrust_audio"):
		_debug_probe_thrust_audio_now()
		return

	# Dev-only: replay ring controls.
	if OS.is_debug_build() and event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and (not k.echo):
			var code: int = int(k.physical_keycode) if int(k.physical_keycode) != 0 else int(k.keycode)
			if _replay_toggle_keycode != 0 and code == _replay_toggle_keycode:
				_replay_ring_enabled = not _replay_ring_enabled
				print("[replay-ring] recording=", str(_replay_ring_enabled))
				get_viewport().set_input_as_handled()
				return
			if _replay_save_keycode != 0 and code == _replay_save_keycode:
				_save_replay_ring_manual()
				get_viewport().set_input_as_handled()
				return

	if not debug_log_input_events:
		return

	# Avoid spamming from mouse motion.
	if event is InputEventMouseMotion:
		return

	var parts: Array[String] = []
	parts.append(event.as_text())

	if event is InputEventKey:
		var k := event as InputEventKey
		var key_name := OS.get_keycode_string(k.keycode) if int(k.keycode) != 0 else ""
		var phys_name := OS.get_keycode_string(k.physical_keycode) if int(k.physical_keycode) != 0 else ""
		parts.append("pressed=%s" % str(k.pressed))
		parts.append("keycode=%d(%s)" % [int(k.keycode), key_name])
		parts.append("physical=%d(%s)" % [int(k.physical_keycode), phys_name])
		parts.append("mods=S%s C%s A%s M%s" % [
			str(int(k.shift_pressed)),
			str(int(k.ctrl_pressed)),
			str(int(k.alt_pressed)),
			str(int(k.meta_pressed)),
		])
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		parts.append("mouse_button=%d pressed=%s" % [int(mb.button_index), str(mb.pressed)])
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		parts.append("joy_button=%d pressed=%s" % [int(jb.button_index), str(jb.pressed)])

	print("[input] ", " | ".join(parts))


func _encode_input_cmds_sorted(cmds_by_ship_id: Dictionary) -> Array:
	# Deterministic encoding: array of [ship_id, cmd_payload] pairs sorted by ship_id.
	# cmd_payload is an array of primitives in a stable field order.
	var ship_ids: Array = cmds_by_ship_id.keys()
	ship_ids.sort()
	var out: Array = []
	out.resize(ship_ids.size())
	for i in range(ship_ids.size()):
		var sid: int = int(ship_ids[i])
		var cmd: DriftTypes.DriftInputCmd = cmds_by_ship_id.get(sid)
		out[i] = [sid, _encode_input_cmd_payload(cmd)]
	return out


func _encode_input_cmd_payload(cmd: DriftTypes.DriftInputCmd) -> Array:
	if cmd == null:
		return [0.0, 0.0, false, false, false, false, false, false, false]
	return [
		float(cmd.thrust),
		float(cmd.rotation),
		bool(cmd.fire_primary),
		bool(cmd.fire_secondary),
		bool(cmd.modifier),
		bool(cmd.stealth_btn),
		bool(cmd.cloak_btn),
		bool(cmd.xradar_btn),
		bool(cmd.antiwarp_btn),
	]


func _save_replay_ring_manual() -> void:
	if _replay_ring == null:
		push_warning("[replay-ring] ring is null")
		return
	var records: Array = _replay_ring.snapshot()
	if records.is_empty():
		print("[replay-ring] No replay buffer data")
		var hud0 := get_node_or_null("HUD")
		if hud0 != null and hud0.has_method("show_help_interrupt"):
			hud0.call("show_help_interrupt", "No replay buffer data", 2.5)
		return
	var stamp := _timestamp_for_path()
	var dir_path: String = "user://replays/manual/%s" % stamp
	var file_path: String = "%s/replay.jsonl" % dir_path

	var abs_dir: String = ProjectSettings.globalize_path(dir_path)
	DirAccess.make_dir_recursive_absolute(abs_dir)

	var f: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		push_error("[replay-ring] failed to open %s" % file_path)
		return
	for rec_any in records:
		if typeof(rec_any) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_any
		var t: int = int(rec.get("t", 0))
		var inputs: Variant = rec.get("inputs", [])
		# Stable JSONL line: fixed key order (t, inputs).
		var inputs_json: String = JSON.stringify(inputs)
		f.store_string("{\"t\":%d,\"inputs\":%s}\n" % [t, inputs_json])
	f.flush()
	f.close()
	print("[replay-ring] saved ", file_path, " (ticks=", str(records.size()), ")")
	var hud := get_node_or_null("HUD")
	if hud != null and hud.has_method("show_help_interrupt"):
		hud.call("show_help_interrupt", "Saved last 30s replay: " + dir_path, 3.0)


func _on_esc_menu_save_replay_requested() -> void:
	# Backward compat (in case the scene/script is older).
	_save_bug_report_manual("manual")


func _on_esc_menu_save_bug_report_requested() -> void:
	_save_bug_report_manual("manual")


func _save_bug_report_manual(trigger: String) -> void:
	if _replay_ring == null:
		push_warning("[bugreport] replay ring is null")
		return
	var records: Array = _replay_ring.snapshot()
	if records.is_empty():
		var hud0 := get_node_or_null("HUD")
		if hud0 != null and hud0.has_method("show_help_interrupt"):
			hud0.call("show_help_interrupt", "No replay buffer data", 2.5)
		return

	var reason: String = _last_mismatch_reason
	var detail: Dictionary = _last_mismatch_detail
	if reason.strip_edges() == "":
		reason = String(trigger)
		detail = {}

	var net_state: Dictionary = _build_bugreport_net_state()
	var meta: Dictionary = ReplayMeta.build_replay_meta(world, net_state)
	meta["bugreport_trigger"] = String(trigger)

	var mismatch: Dictionary = {
		"reason": String(reason),
		"detail": detail if detail != null else {},
	}

	var res: Dictionary = BugReportWriter.save_bug_report(String(reason), meta, records, mismatch, {
		# Prefer repo-local artifacts when possible; fall back to user://.
		"root": "res://.ci_artifacts/bugreports",
		"fallback_root": "user://.ci_artifacts/bugreports",
		# Zip is best-effort; folder is always written.
		"zip": true,
	})
	if not bool(res.get("ok", false)):
		print("[bugreport] Failed: ", String(res.get("error", "unknown")))
		return
	var folder: String = String(res.get("folder", ""))
	var zip_path: String = String(res.get("zip", ""))
	print("[bugreport] Saved: ", folder, (" (zip=" + zip_path + ")" if zip_path != "" else ""))
	var hud := get_node_or_null("HUD")
	if hud != null and hud.has_method("show_help_interrupt"):
		var msg := "Saved bug report: " + folder
		if zip_path != "":
			msg = "Saved bug report: " + zip_path
		hud.call("show_help_interrupt", msg, 3.0)


func _build_bugreport_net_state() -> Dictionary:
	var ruleset_hash: int = 0
	if world != null and "ruleset" in world and typeof(world.ruleset) == TYPE_DICTIONARY:
		# DriftValidate returns canonical ordering; JSON.stringify should be stable.
		var rs_json: String = JSON.stringify(world.ruleset)
		ruleset_hash = int(DriftHash.int31_from_string_sha256("ruleset_json=" + rs_json))

	return {
		"server_addr": "%s:%d" % [server_address, int(SERVER_PORT)],
		"map_path": String(CLIENT_MAP_PATH),
		"map_version": int(client_map_version),
		"map_checksum": DriftMap.bytes_to_hex(client_map_checksum) if client_map_checksum.size() > 0 else "",
		"ruleset_path": "",
		"ruleset_hash": ruleset_hash,
	}


func on_desync_detected(reason: String, detail: Dictionary) -> void:
	# Central desync handler:
	# - snapshot ring
	# - build meta
	# - write bugreport bundle
	# - log one concise line
	# - optionally show HUD toast
	_last_mismatch_reason = String(reason)
	_last_mismatch_detail = detail if detail != null else {}

	var records: Array = []
	if _replay_ring != null:
		records = _replay_ring.snapshot()
	var net_state: Dictionary = _build_bugreport_net_state()
	var meta: Dictionary = ReplayMeta.build_replay_meta(world, net_state)
	meta["bugreport_trigger"] = "desync"
	var mismatch: Dictionary = {
		"reason": String(reason),
		"detail": detail if detail != null else {},
	}

	var res: Dictionary = BugReportWriter.save_bug_report(String(reason), meta, records, mismatch, {
		"root": "res://.ci_artifacts/bugreports",
		"fallback_root": "user://.ci_artifacts/bugreports",
		"zip": true,
	})
	if not bool(res.get("ok", false)):
		print("[DESYNC] Failed to save bug report (", String(res.get("error", "unknown")), ")")
		return

	var folder: String = String(res.get("folder", ""))
	var zip_path: String = String(res.get("zip", ""))
	print("[DESYNC] Saved bug report: ", folder, (" (zip=" + zip_path + ")" if zip_path != "" else ""))
	var hud := get_node_or_null("HUD")
	if hud != null and hud.has_method("show_help_interrupt"):
		var msg := "Saved bug report: " + folder
		if zip_path != "":
			msg = "Saved bug report: " + zip_path
		hud.call("show_help_interrupt", msg, 3.0)


func _timestamp_for_path() -> String:
	# Windows-safe timestamp: YYYYMMDD_HHMMSS_mmm
	var d: Dictionary = Time.get_datetime_dict_from_system()
	var ms: int = int(Time.get_ticks_msec() % 1000)
	return "%04d%02d%02d_%02d%02d%02d_%03d" % [
		int(d.get("year", 0)),
		int(d.get("month", 0)),
		int(d.get("day", 0)),
		int(d.get("hour", 0)),
		int(d.get("minute", 0)),
		int(d.get("second", 0)),
		ms,
	]


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
		if debug_show_overlay:
			_draw_debug_overlay(DriftTypes.DriftShipState.new(-1, Vector2.ZERO), 0)
		return

	var ship_state: DriftTypes.DriftShipState = latest_snapshot.ships.get(local_ship_id)
	if ship_state == null:
		return

	# Pickup feed is now screen-space HUD-only (not drawn in world space).

	# Friend/enemy colors are derived from replicated team frequency.
	var my_freq: int = int(ship_state.freq)

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
			# Determine friendliness from authoritative snapshot state.
			var remote_state = latest_snapshot.ships.get(ship_id)
			var remote_freq: int = int(remote_state.freq) if remote_state != null else -1
			_draw_remote_ship_triangle(interp_state, DriftTeamColors.ship_marker_color(my_freq, remote_freq))
			# Draw username and bounty
			if remote_state != null:
				var label = "%s (%d)" % [remote_state.username, remote_state.bounty]
				var color_index: int = DriftTeamColors.get_nameplate_color_index(my_freq, remote_freq, 0)
				SpriteFontLabelScript.draw_text(self, interp_pos + name_offset, label, SpriteFontLabelScript.FontSize.SMALL, color_index, 0)
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
			var snap_state = latest_snapshot.ships.get(ship_id)
			var remote_freq: int = int(snap_state.freq) if snap_state != null else -1
			_draw_remote_ship_triangle(remote_state, DriftTeamColors.ship_marker_color(my_freq, remote_freq))
			# Draw username and bounty
			if snap_state != null:
				var label = "%s (%d)" % [snap_state.username, snap_state.bounty]
				var color_index: int = DriftTeamColors.get_nameplate_color_index(my_freq, remote_freq, 0)
				SpriteFontLabelScript.draw_text(self, remote_state.position + name_offset, label, SpriteFontLabelScript.FontSize.SMALL, color_index, 0)
				# Draw crown if king
				if king_id == ship_id:
					_draw_crown(remote_state.position + Vector2(0, -48))
		if latest_snapshot.ball_owner_id != local_ship_id:
			_draw_ball_at(ball_position)

	# Local ship (predicted)
	_draw_ship_triangle(ship_state)
	_draw_prizes()
	_draw_bullets()
	_draw_local_combat_fx(ship_state)
	
	# ⚠️ ALWAYS VISIBLE: Draw username and bounty for local ship (blue sprite font)
	# This element must never be hidden or removed.
	var local_state = latest_snapshot.ships.get(local_ship_id)
	if local_state != null:
		var label = "%s(%d)" % [local_state.username, local_state.bounty]
		SpriteFontLabelScript.draw_text(self, ship_state.position + name_offset, label, SpriteFontLabelScript.FontSize.SMALL, 2, 0)
		if king_id == local_ship_id:
			_draw_crown(ship_state.position + Vector2(0, -48))

	# _draw_authoritative_ghost_ship()  # Disabled - no ghost ship
	if debug_show_overlay:
		_draw_debug_overlay(ship_state, latest_snapshot.tick)

	# Critical-energy in-world readout (authoritative snapshot state).
	var local_snap = latest_snapshot.ships.get(local_ship_id)
	if local_snap != null:
		var ec: int = int(local_snap.energy_current) if ("energy_current" in local_snap) else int(round(float(local_snap.energy)))
		var em: int = int(local_snap.energy_max) if ("energy_max" in local_snap) else 0
		if em > 0:
			var frac := clampf(float(ec) / float(em), 0.0, 1.0)
			if frac <= ui_critical_energy_frac:
				SpriteFontLabelScript.draw_text(self, ship_state.position + Vector2(-8, 28), "%d" % ec, SpriteFontLabelScript.FontSize.SMALL, 3, 0)

	# HUD: King
	var king_label = "KING: none"
	if king_id != -1 and latest_snapshot.ships.has(king_id):
		var king_state = latest_snapshot.ships[king_id]
		king_label = "KING: %s (%d)" % [king_state.username, king_state.bounty]
	draw_string(font, Vector2(32, 80), king_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color(1, 1, 0.4, 1))


	# Local ship (predicted)
	# (Removed duplicate local ship drawing and overlays)


func _draw_local_combat_fx(local_ship_state: DriftTypes.DriftShipState) -> void:
	if latest_snapshot == null:
		return
	var cur_tick: int = int(latest_snapshot.tick)
	# Muzzle flashes.
	for f_any in _muzzle_flashes:
		if typeof(f_any) != TYPE_DICTIONARY:
			continue
		var f: Dictionary = f_any
		var exp: int = int(f.get("expire_tick", -1))
		if exp < cur_tick:
			continue
		var pos_any: Variant = f.get("pos", Vector2.ZERO)
		var pos: Vector2 = pos_any if pos_any is Vector2 else Vector2.ZERO
		var a: float = clampf(float(exp - cur_tick + 1) / 3.0, 0.0, 1.0)
		draw_circle(pos, 6.0, Color(1.0, 0.9, 0.3, 0.65 * a))
		draw_circle(pos, 10.0, Color(1.0, 0.8, 0.2, 0.25 * a), 2.0)

	# Hit confirm ring around local ship.
	if _hit_confirm_until_tick >= cur_tick:
		var a2: float = clampf(float(_hit_confirm_until_tick - cur_tick + 1) / 6.0, 0.0, 1.0)
		draw_circle(local_ship_state.position, 18.0, Color(1.0, 1.0, 1.0, 0.15 * a2), 2.0)

	# Floating damage numbers at hit position.
	var font: Font = ThemeDB.fallback_font
	for h_any in _hit_markers:
		if typeof(h_any) != TYPE_DICTIONARY:
			continue
		var h: Dictionary = h_any
		var exp2: int = int(h.get("expire_tick", -1))
		if exp2 < cur_tick:
			continue
		var start: int = int(h.get("start_tick", cur_tick))
		var t: float = 0.0
		var denom: float = maxf(1.0, float(exp2 - start))
		t = clampf(float(cur_tick - start) / denom, 0.0, 1.0)
		var pos3_any: Variant = h.get("pos", Vector2.ZERO)
		var pos3: Vector2 = pos3_any if pos3_any is Vector2 else Vector2.ZERO
		var dmg: int = maxi(0, int(h.get("damage", 0)))
		var yoff: float = lerpf(0.0, -24.0, t)
		var alpha: float = lerpf(0.9, 0.0, t)
		draw_string(font, pos3 + Vector2(-8.0, yoff), "%d" % dmg, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(1.0, 0.9, 0.9, alpha))

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
func _draw_remote_ship_triangle(ship_state: DriftTypes.DriftShipState, fill_color: Color) -> void:
	# Atlas-based ship sprite (no SpriteFrames assets).
	# Ship selection is currently a single default (0=Warbird) until ship choice is replicated.
	var ship_index := 0
	# Godot 2D rotation increases clockwise on screen; convert to CCW degrees for the atlas mapper.
	var heading_deg := -rad_to_deg(float(ship_state.rotation))
	var tex := _ships_tex if _ships_tex != null else SHIPS_TEX_FALLBACK
	var src := DriftShipAtlas.region_rect_px(tex, ship_index, heading_deg)
	if src.size.x <= 0.0 or src.size.y <= 0.0:
		# Fallback to old triangle if the atlas is invalid.
		var local_points: PackedVector2Array = PackedVector2Array([
			Vector2(10.0, 0.0),
			Vector2(-7.0, -6.0),
			Vector2(-7.0, 6.0),
		])
		var world_points: PackedVector2Array = PackedVector2Array()
		world_points.resize(local_points.size())
		for i in range(local_points.size()):
			world_points[i] = local_points[i].rotated(ship_state.rotation) + ship_state.position
		draw_colored_polygon(world_points, fill_color)
		return

	var dst := Rect2(ship_state.position - src.size * 0.5, src.size)
	draw_texture_rect_region(tex, dst, src, Color(1, 1, 1, 1))


func _draw_ship_triangle(ship_state: DriftTypes.DriftShipState) -> void:
	# Atlas-based ship sprite (no SpriteFrames assets).
	var ship_index := 0
	# Godot 2D rotation increases clockwise on screen; convert to CCW degrees for the atlas mapper.
	var heading_deg := -rad_to_deg(float(ship_state.rotation))
	var tex := _ships_tex if _ships_tex != null else SHIPS_TEX_FALLBACK
	var src := DriftShipAtlas.region_rect_px(tex, ship_index, heading_deg)
	if src.size.x <= 0.0 or src.size.y <= 0.0:
		# Fallback to old triangle if the atlas is invalid.
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
		return

	var dst := Rect2(ship_state.position - src.size * 0.5, src.size)
	draw_texture_rect_region(tex, dst, src, Color(1, 1, 1, 1))


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
	# ESC menu overlay (client-only UI; must not pause the sim)
	if not show_connect_ui and esc_menu != null and esc_menu.has_method("is_open"):
		var menu_open: bool = bool(esc_menu.call("is_open"))
		if event.is_action_pressed("ui_escape_menu"):
			if esc_menu.has_method("toggle"):
				esc_menu.call("toggle")
			get_viewport().set_input_as_handled()
			return
		# While the menu is open, do not handle any other global UI hotkeys here.
		# The menu itself enforces click-away and "unbound input dismiss" in _unhandled_input.
		if menu_open:
			return

	# Help ticker (client-only UI). Does not affect sim/input cmd collection.
	if not show_connect_ui:
		if event.is_action_pressed("drift_help_next"):
			var hud := get_node_or_null("HUD")
			if hud != null and hud.has_method("help_ticker_next_page"):
				hud.call("help_ticker_next_page")
				get_viewport().set_input_as_handled()
				return
		if event.is_action_pressed("drift_help_toggle"):
			# SubSpace-style chord: Esc+F6. We avoid hardcoded key polling by
			# checking the existing pause-menu action state.
			var esc_down := Input.is_action_pressed("drift_toggle_pause_menu")
			if not esc_down and not pause_menu_visible:
				return
			var hud2 := get_node_or_null("HUD")
			if hud2 != null and hud2.has_method("help_ticker_toggle"):
				hud2.call("help_ticker_toggle")
				get_viewport().set_input_as_handled()
				return

	# NOTE: legacy pause menu toggle is intentionally not bound here.
	# The new EscMenu overlay owns ESC behavior via ui_escape_menu.

	if show_connect_ui:
		# Accept the project-specific action and the engine default accept action.
		# This makes the connection screen resilient to keybinding differences.
		if event.is_action_pressed("drift_menu_connect") or event.is_action_pressed("ui_accept"):
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
	_update_main_menu_ui_visibility()


func _build_main_menu_ui() -> void:
	# Minimal, client-only UI overlay for the connection screen.
	_main_menu_ui_layer = CanvasLayer.new()
	_main_menu_ui_layer.layer = 90
	add_child(_main_menu_ui_layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main_menu_ui_layer.add_child(root)

	_main_menu_options_panel = PanelContainer.new()
	_main_menu_options_panel.custom_minimum_size = Vector2(220, 70)
	_main_menu_options_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# For bottom-right anchors (all == 1.0), you must set BOTH left/top and right/bottom
	# offsets to get a positive rect size; otherwise the control ends up with negative size
	# and will be invisible.
	var pad: float = 16.0
	_main_menu_options_panel.offset_right = -pad
	_main_menu_options_panel.offset_bottom = -pad
	_main_menu_options_panel.offset_left = -pad - _main_menu_options_panel.custom_minimum_size.x
	_main_menu_options_panel.offset_top = -pad - _main_menu_options_panel.custom_minimum_size.y
	_main_menu_options_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_main_menu_options_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	_main_menu_options_panel.add_child(vbox)

	_main_menu_options_btn = Button.new()
	_main_menu_options_btn.text = "Options"
	_main_menu_options_btn.pressed.connect(_on_main_menu_options_pressed)
	vbox.add_child(_main_menu_options_btn)

	_update_main_menu_ui_visibility()


func _update_main_menu_ui_visibility() -> void:
	if _main_menu_ui_layer == null:
		return
	var show: bool = show_connect_ui and (_options_menu_instance == null)
	_main_menu_ui_layer.visible = show


func _on_main_menu_options_pressed() -> void:
	_open_options_menu_from_main_menu()


func _open_options_menu_from_main_menu() -> void:
	if _options_menu_instance != null:
		return
	if OptionsMenuScene == null:
		return
	_options_menu_instance = OptionsMenuScene.instantiate()
	add_child(_options_menu_instance)
	if _options_menu_instance.has_signal("back_requested"):
		_options_menu_instance.connect("back_requested", _on_options_menu_back_requested)
	_update_main_menu_ui_visibility()


func _on_options_menu_back_requested() -> void:
	_options_menu_instance = null
	_update_main_menu_ui_visibility()


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
		if pkt_type == DriftNet.PKT_SET_FREQ_RESULT:
			var r: Dictionary = DriftNet.unpack_set_freq_result(bytes)
			if r.is_empty():
				continue
			var ok: bool = bool(r.get("ok", false))
			var f: int = int(r.get("freq", 0))
			var reason: int = int(r.get("reason", DriftNet.SET_FREQ_REASON_NOT_ALLOWED))
			if ok:
				print("[NET] set freq ok freq=", f)
			else:
				print("[NET] set freq rejected freq=", f, " reason=", _set_freq_reason_to_string(reason))
			continue
		if pkt_type == DriftNet.PKT_WELCOME:
			var w: Dictionary = DriftNet.unpack_welcome_packet(bytes)
			if not w.is_empty():
				var server_map_path: String = String(w.get("map_path", ""))
				var server_map_version: int = int(w.get("map_version", 0))
				var server_checksum: PackedByteArray = w.get("map_checksum", PackedByteArray())
				if server_map_path != "" and server_map_path != CLIENT_MAP_PATH:
					on_desync_detected("handshake_map_path_mismatch", {
						"server_map_path": server_map_path,
						"client_map_path": String(CLIENT_MAP_PATH),
					})
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
					on_desync_detected("handshake_map_version_mismatch", {
						"server_map_version": int(server_map_version),
						"client_map_version": int(client_map_version),
					})
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
					on_desync_detected("handshake_map_checksum_mismatch", {
						"server_map_checksum": server_hex,
						"client_map_checksum": client_hex,
					})
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
						on_desync_detected("handshake_ruleset_parse_failed", {
							"parse_err": int(parse_err),
							"ruleset_json_len": int(ruleset_json.length()),
						})
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
						on_desync_detected("handshake_ruleset_validation_failed", {
							"error": String(validated.get("error", "")),
						})
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
					var canon: Dictionary = validated.get("ruleset", {})
					world.apply_ruleset(canon)
					# UI thresholds are client-side, but must come from the validated server ruleset.
					var ui: Dictionary = canon.get("ui", {})
					if typeof(ui) == TYPE_DICTIONARY:
						if ui.has("low_energy_frac"):
							ui_low_energy_frac = clampf(float(ui.get("low_energy_frac")), 0.0, 1.0)
						if ui.has("critical_energy_frac"):
							ui_critical_energy_frac = clampf(float(ui.get("critical_energy_frac")), 0.0, 1.0)
						if ui_critical_energy_frac > ui_low_energy_frac:
							ui_critical_energy_frac = ui_low_energy_frac
					var hud := get_node_or_null("HUD")
					if hud != null and hud.has_method("set_ui_thresholds"):
						hud.call("set_ui_thresholds", ui_low_energy_frac, ui_critical_energy_frac)
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
				on_desync_detected("snapshot_contract_violation", {
					"packet_len": int(bytes.size()),
				})
				continue

			var snap_tick: int = snap_dict["tick"]
			if snap_tick > best_snapshot_tick:
				best_snapshot_tick = snap_tick
				best_snapshot_dict = snap_dict

	if best_snapshot_tick != -1:
		_apply_snapshot_dict(best_snapshot_dict)


func request_set_freq(desired_freq: int) -> void:
	# Client helper to request a manual team/frequency change.
	# Security: ship_id comes from the locally assigned welcome packet, not UI.
	if enet_peer == null or not is_connected:
		print("[NET] request_set_freq ignored (not connected)")
		return
	if local_ship_id < 0:
		print("[NET] request_set_freq ignored (no local_ship_id)")
		return
	var packet: PackedByteArray = DriftNet.pack_set_freq_request(int(local_ship_id), int(desired_freq))
	enet_peer.set_transfer_channel(NET_CHANNEL)
	enet_peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	enet_peer.set_target_peer(1)
	enet_peer.put_packet(packet)
	print("[NET] request_set_freq sent desired_freq=", int(desired_freq))


func _set_freq_reason_to_string(reason: int) -> String:
	match int(reason):
		DriftNet.SET_FREQ_REASON_OUT_OF_BOUNDS:
			return "OUT_OF_BOUNDS"
		DriftNet.SET_FREQ_REASON_UNEVEN_TEAMS:
			return "UNEVEN_TEAMS"
		DriftNet.SET_FREQ_REASON_COOLDOWN:
			return "COOLDOWN"
		DriftNet.SET_FREQ_REASON_NOT_ALLOWED:
			return "NOT_ALLOWED"
		_:
			return "UNKNOWN"


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


func notify_prize_awarded(prize_type: int) -> void:
	# Single entry point for prize feedback.
	# Called after gameplay state is updated.
	# - Resolves UI metadata from PrizeType.
	# - Triggers PrizeToast.
	# - No-ops when UI is disabled or running headless.
	if OS.has_feature("headless"):
		return
	var hud := get_node_or_null("HUD")
	if hud == null:
		return
	# If toast is disabled, do nothing.
	if ("prize_toast_enabled" in hud) and (not bool(hud.get("prize_toast_enabled"))):
		return
	if not hud.has_method("set_prize_toast"):
		return
	var pt: int = int(prize_type)
	var label: String = DriftPrizeTypes.label_for_type(pt)
	var icon: Vector2i = DriftPrizeTypes.icon_atlas_coords_for_type(pt)
	# Deterministic expiry in sim ticks.
	var now_tick: int = int(world.tick)
	var until_tick: int = now_tick + int(PRIZE_TOAST_DURATION_TICKS)
	hud.call("set_prize_toast", pt, icon, label, until_tick)


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

	# Cache last-known prize metadata by id so we can label pickup events.
	# Pickup events only carry prize_id, and the prize itself may already be removed
	# from the current snapshot list.
	if not authoritative_prizes.is_empty() and _prize_feedback_pipeline != null:
		_prize_feedback_pipeline.cache_prize_states(authoritative_prizes)

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
	# Prize pickup feedback: driven by authoritative prize_events when present.
	# Pipeline is UI-only; it emits a one-shot SFX trigger and a stable label we reuse for the
	# pickup feed and client-only inventory counts.
	if snap_dict.has("prize_events") and (snap_dict.get("prize_events") is Array) and _prize_feedback_pipeline != null:
		_prize_feedback_pipeline.consume_prize_events(snap_tick, (snap_dict.get("prize_events") as Array), local_ship_id)

		# NEW UX:
		# - No prize icons/messages in chat/help ticker.
		# - Append text-only pickup line into the screen-space HUD pickup feed.
		# - Update left inventory counts (client-only; derived from pickups).
		var toast_label2: String = _prize_feedback_pipeline.take_toast_label_trigger()
		var pt2: int = _prize_feedback_pipeline.take_awarded_prize_type_trigger()
		if toast_label2 != "":
			# Optional transient UI toast (only if HUD has it enabled).
			if not OS.has_feature("headless"):
				var hud_toast := get_node_or_null("HUD")
				if hud_toast != null and hud_toast.has_method("set_prize_toast"):
					var icon2: Vector2i = DriftPrizeTypes.icon_atlas_coords_for_type(pt2)
					var until2: int = int(world.tick) + int(PRIZE_TOAST_DURATION_TICKS)
					hud_toast.call("set_prize_toast", pt2, icon2, toast_label2, until2)

			if not OS.has_feature("headless"):
				var hud_feed := get_node_or_null("HUD")
				if hud_feed != null and hud_feed.has_method("add_pickup_feed_line_until_tick"):
					var feed_until2: int = int(snap_tick) + int(PrizeFeedbackPipeline.PRIZE_FEEDBACK_DURATION_TICKS)
					hud_feed.call("add_pickup_feed_line_until_tick", toast_label2, feed_until2)
				elif hud_feed != null and hud_feed.has_method("add_pickup_feed_line"):
					hud_feed.call("add_pickup_feed_line", toast_label2)

			# Only update inventory counts when we can classify the pickup.
			if pt2 >= 0:
				var delta: int = -1 if toast_label2.begins_with("-") else 1
				var key: StringName = &""
				match int(pt2):
					int(DriftPrizeTypes.PrizeType.BURST):
						key = &"burst"
					int(DriftPrizeTypes.PrizeType.REPEL):
						key = &"repel"
					int(DriftPrizeTypes.PrizeType.DECOY):
						key = &"decoy"
					int(DriftPrizeTypes.PrizeType.THOR):
						key = &"thor"
					int(DriftPrizeTypes.PrizeType.BRICK):
						key = &"brick"
					int(DriftPrizeTypes.PrizeType.ROCKET):
						key = &"rocket"
					int(DriftPrizeTypes.PrizeType.TELEPORT):
						key = &"teleport"
					_:
						key = &""
				if key != &"":
					var prev: int = int(_ui_inventory_counts.get(key, 0))
					_ui_inventory_counts[key] = maxi(0, prev + delta)
					if not OS.has_feature("headless"):
						var hud_inv := get_node_or_null("HUD")
						if hud_inv != null and hud_inv.has_method("set_inventory_counts"):
							hud_inv.call("set_inventory_counts", _ui_inventory_counts)
		if _prize_feedback_pipeline.take_pickup_sfx_trigger():
			if _prize_audio != null and _prize_audio.stream != null:
				_prize_audio.play()
	# Authoritative bullets (render remote bullets; local bullets are predicted).
	authoritative_bullets.clear()
	if snap_dict.has("bullets") and (snap_dict.get("bullets") is Array):
		var bs: Array = snap_dict.get("bullets")
		for b in bs:
			if b == null:
				continue
			authoritative_bullets.append(DriftTypes.DriftBulletState.new(int(b.id), int(b.owner_id), int(b.level), b.position, b.velocity, int(b.spawn_tick), int(b.die_tick), int(b.bounces_left)))
	# Authoritative prizes (render only; no client simulation).
	authoritative_prizes.clear()
	if snap_dict.has("prizes") and (snap_dict.get("prizes") is Array):
		var ps: Array = snap_dict.get("prizes")
		for p in ps:
			if p == null:
				continue
			var st := DriftTypes.DriftPrizeState.new(int(p.id), p.pos, snap_tick, int(p.despawn_tick), int(p.kind), bool(p.is_negative), bool(p.is_death_drop))
			authoritative_prizes.append(st)
		if _prize_feedback_pipeline != null and not authoritative_prizes.is_empty():
			_prize_feedback_pipeline.cache_prize_states(authoritative_prizes)
	# Also attach authoritative prize list to the rendered snapshot so the minimap/radar UI
	# (which consumes latest_snapshot) can draw prize dots.
	if latest_snapshot != null:
		latest_snapshot.prizes = authoritative_prizes
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
						int(ship_state.energy),
						int(ship_state.next_bullet_tick),
						int(ship_state.energy_current),
						int(ship_state.energy_max),
						int(ship_state.energy_recharge_rate_per_sec),
						int(ship_state.energy_recharge_delay_ticks),
						int(ship_state.energy_recharge_wait_ticks),
						int(ship_state.energy_recharge_fp_accum),
						int(ship_state.energy_drain_fp_accum)
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
				int(ship_state.energy),
				int(ship_state.next_bullet_tick),
				int(ship_state.energy_current),
				int(ship_state.energy_max),
				int(ship_state.energy_recharge_rate_per_sec),
				int(ship_state.energy_recharge_delay_ticks),
				int(ship_state.energy_recharge_wait_ticks),
				int(ship_state.energy_recharge_fp_accum),
				int(ship_state.energy_drain_fp_accum)
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
	local_state.energy = int(auth_state.energy)
	local_state.next_bullet_tick = int(auth_state.next_bullet_tick)
	local_state.energy_current = int(auth_state.energy_current)
	local_state.energy_max = int(auth_state.energy_max)
	local_state.energy_recharge_rate_per_sec = int(auth_state.energy_recharge_rate_per_sec)
	local_state.energy_recharge_delay_ticks = int(auth_state.energy_recharge_delay_ticks)
	local_state.energy_recharge_wait_ticks = int(auth_state.energy_recharge_wait_ticks)
	local_state.energy_recharge_fp_accum = int(auth_state.energy_recharge_fp_accum)
	local_state.energy_drain_fp_accum = int(auth_state.energy_drain_fp_accum)
	local_state.stealth_on = bool(auth_state.stealth_on)
	local_state.cloak_on = bool(auth_state.cloak_on)
	local_state.xradar_on = bool(auth_state.xradar_on)
	local_state.antiwarp_on = bool(auth_state.antiwarp_on)
	local_state.in_safe_zone = bool(auth_state.in_safe_zone)
	local_state.damage_protect_until_tick = int(auth_state.damage_protect_until_tick)

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
			world.bullets[int(b.id)] = DriftTypes.DriftBulletState.new(int(b.id), int(b.owner_id), int(b.level), b.position, b.velocity, int(b.spawn_tick), int(b.die_tick), int(b.bounces_left))
		# Ensure edge-triggered fire state matches the snapshot baseline.
		var base_cmd: DriftTypes.DriftInputCmd = input_history.get(snapshot_tick, DriftTypes.DriftInputCmd.new(0.0, 0.0, false, false, false))
		world._prev_fire_by_ship[local_ship_id] = bool(base_cmd.fire_primary)
		var abits: int = 0
		if bool(base_cmd.stealth_btn):
			abits |= 1
		if bool(base_cmd.cloak_btn):
			abits |= 2
		if bool(base_cmd.xradar_btn):
			abits |= 4
		if bool(base_cmd.antiwarp_btn):
			abits |= 8
		world._prev_ability_buttons_by_ship[local_ship_id] = abits

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
		on_desync_detected("replay_tick_contract_violation", {
			"expected_tick": int(current_tick),
			"actual_tick": int(world.tick),
		})

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
			local_bullets.append(DriftTypes.DriftBulletState.new(int(b.id), int(b.owner_id), int(b.level), b.position, b.velocity, int(b.spawn_tick), int(b.die_tick), int(b.bounces_left)))
	return DriftTypes.DriftWorldSnapshot.new(world.tick, ships_dict, Vector2.ZERO, Vector2.ZERO, -1, local_bullets)


func _prune_input_history(upto_tick_inclusive: int) -> void:
	if upto_tick_inclusive < 0:
		return

	var keys: Array = input_history.keys()
	for k in keys:
		if int(k) <= upto_tick_inclusive:
			input_history.erase(k)
