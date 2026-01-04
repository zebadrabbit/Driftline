extends Node2D

## Simple single-player flyable scene controller.
## - Ensures InputMap bindings exist (if not already configured in Project Settings)
## - Smooth-follow camera
## - Zoom with mouse wheel
## - Hooks PlayerShip.stats_changed -> HUD (no NodePath coupling; uses group lookup)
## - Loads default map on startup

const LevelIO = preload("res://client/scripts/maps/level_io.gd")

@export var follow_strength: float = 10.0 # higher = snappier
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.5
@export var zoom_step: float = 0.1

@onready var ship: Node2D = $PlayerShip
@onready var cam: Camera2D = $Camera2D
@onready var hud: Node = $HUD
@onready var tilemap_bg: TileMap = $TileMapBG
@onready var tilemap_solid: TileMap = $TileMapSolid
@onready var tilemap_fg: TileMap = $TileMapFG

var _ship_connected: bool = false


func _ready() -> void:
	_ensure_input_actions()
	_load_default_map()
	if cam != null:
		cam.position_smoothing_enabled = false
		cam.make_current()
	_try_connect_ship_to_hud()


func _unhandled_input(event: InputEvent) -> void:
	# Help ticker (client-only UI)
	if event.is_action_pressed(&"drift_help_next"):
		var h := get_node_or_null("HUD")
		if h != null and h.has_method("help_ticker_next_page"):
			h.call("help_ticker_next_page")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"drift_help_toggle"):
		# SubSpace-style chord: Esc+F6.
		if not Input.is_action_pressed(&"drift_toggle_pause_menu"):
			return
		var h2 := get_node_or_null("HUD")
		if h2 != null and h2.has_method("help_ticker_toggle"):
			h2.call("help_ticker_toggle")
		get_viewport().set_input_as_handled()
		return

	# Open map editor (InputMap)
	if event.is_action_pressed(&"drift_open_map_editor"):
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file("res://client/scenes/editor/MapEditor.tscn")
		return
	
	# Zoom controls (simple and stable)
	if cam == null:
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(cam.zoom.x - zoom_step)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(cam.zoom.x + zoom_step)


func _physics_process(delta: float) -> void:
	if ship == null or cam == null:
		return
	# Smooth follow using exponential-ish lerp.
	var t := 1.0 - exp(-follow_strength * delta)
	cam.global_position = cam.global_position.lerp(ship.global_position, t)

	if not _ship_connected:
		_try_connect_ship_to_hud()


func _set_zoom(z: float) -> void:
	z = clampf(z, min_zoom, max_zoom)
	cam.zoom = Vector2(z, z)


func _try_connect_ship_to_hud() -> void:
	if hud == null:
		return
	var s := get_tree().get_first_node_in_group("player_ship")
	if s == null:
		return
	if _ship_connected:
		return
	if s.has_signal("stats_changed") and not s.stats_changed.is_connected(_on_ship_stats_changed):
		s.stats_changed.connect(_on_ship_stats_changed)
		_ship_connected = true


func _on_ship_stats_changed(speed: float, heading_deg: float, energy: float) -> void:
	if hud != null and hud.has_method("set_ship_stats"):
		hud.call("set_ship_stats", speed, heading_deg, energy)


func _ensure_input_actions() -> void:
	# Ensure required Driftline actions exist.
	# Default bindings are configured in Project Settings -> Input Map.
	for action in [
		&"drift_thrust_forward",
		&"drift_thrust_reverse",
		&"drift_rotate_left",
		&"drift_rotate_right",
		&"drift_fire_primary",
		&"drift_fire_secondary",
		&"drift_modifier_ability",
	]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)





func _load_default_map() -> void:
	# Load the default map shipped with the game
	var map_path := "res://maps/default.json"
	var tilemaps := {
		"bg": tilemap_bg,
		"solid": tilemap_solid,
		"fg": tilemap_fg
	}
	
	var meta := LevelIO.load_map_from_json(map_path, tilemaps)
	if meta.is_empty():
		push_error("Failed to load default map")
	else:
		print("Default map loaded: %dx%d" % [meta.get("w", 0), meta.get("h", 0)])
