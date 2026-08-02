extends Node2D

## Tile-based map editor (client-only, no server required).
## WASD moves the camera; the cursor follows the mouse.
## Tools: B rect, L line, G bucket, I eyedropper. Ctrl+Z / Ctrl+Y undo and redo.
## Space or LMB places, Backspace/RMB erases, Tab cycles layers, Q opens the palette.
## Press F1 in-editor for the full key list. Boundary tiles are generated and immutable.

const LevelIO = preload("res://client/scripts/maps/level_io.gd")
const TilesetMetaScript = preload("res://editor/tileset_meta.gd")
const TileOverlayScript = preload("res://editor/tile_overlay.gd")
const TestPuckScript = preload("res://editor/test_puck.gd")
const TilesetIO = preload("res://shared/tileset/tileset_io.gd")
const TilesetData = preload("res://shared/tileset/tileset_data.gd")

@export var map_width: int = 64
@export var map_height: int = 64
@export var cursor_move_speed: int = 1
@export var cursor_move_speed_fast: int = 8

var editor_zoom: float = 4.0

# Map size state.
# NOTE: Despite the name, these are pixel dimensions (multiples of TILE_SIZE).
# We convert them to tile dimensions internally.
var map_width_tiles: int = 1024
var map_height_tiles: int = 1024

@onready var map_canvas: Node2D = $MapCanvas
@onready var tilemap_bg: TileMap = $MapCanvas/TileMapBG
@onready var tilemap_solid: TileMap = $MapCanvas/TileMapSolid
@onready var tilemap_fg: TileMap = $MapCanvas/TileMapFG
@onready var camera: Camera2D = $Camera2D
@onready var cursor_sprite: Sprite2D = $MapCanvas/Cursor
@onready var ui_label: Label = $UI/Label
@onready var ui_root: CanvasLayer = $UI

var status_label: Label
var status_timer: float = 0.0
var entities: Array = []

var cursor_cell := Vector2i(10, 10)
# Camera navigation cell (WASD only). Mouse should not affect this.
var camera_cell := Vector2i(10, 10)
var current_layer := "solid"  # "bg", "solid", "fg"
var selected_atlas_coords := Vector2i(1, 0)  # Default: horizontal wall

# Favorites list (atlas coords) - cycle with Q/E
var favorites := [
	Vector2i(1, 0),   # Horizontal wall
	Vector2i(1, 2),   # Vertical wall
	Vector2i(9, 19),  # Safe zone
	Vector2i(0, 0),   # Empty/space
	Vector2i(2, 0),   # Some other tile (adjust as needed)
]
var favorite_index := 0
var _favorites_max_len: int = 0

# New Map dialog UI (Ctrl+N)
var new_map_visible := false
var new_map_layer: CanvasLayer
var new_map_panel: Panel
var new_map_width_spin: SpinBox
var new_map_height_spin: SpinBox

# Load Map dialog UI (Ctrl+O)
var load_map_visible := false
var load_map_layer: CanvasLayer
var load_map_panel: Panel
var load_map_list: ItemList
var _load_map_files: PackedStringArray = PackedStringArray()

# Tile palette UI (Q toggles)
var palette_visible := false
var palette_layer: CanvasLayer
var palette_panel: Panel
var palette_grid: GridContainer
var palette_source_id := -1
var palette_atlas: TileSetAtlasSource
var palette_texture: Texture2D
const PALETTE_COLUMNS := 16

# Drag tool state (LMB drag). The active tool decides what the drag commits.
enum Tool { RECT, LINE, FILL }
var current_tool: int = Tool.RECT
const TOOL_NAMES := {Tool.RECT: "RECT", Tool.LINE: "LINE", Tool.FILL: "FILL"}
var dragging: bool = false
var drag_start_cell := Vector2i.ZERO
var drag_end_cell := Vector2i.ZERO

var _tilemaps := {}
var _tileset_name := "subspace_base"

var _tileset_data: TilesetData = null
var _available_tilesets: PackedStringArray = PackedStringArray()
var _tileset_index: int = 0

var _tileset_meta
var _tileset_meta_path: String = ""

# Right-side Tile Properties panel
var _tile_props_panel: Panel
var _tile_layer_option: OptionButton
var _tile_solid_check: CheckBox
var _tile_restitution_slider: HSlider
var _tile_friction_slider: HSlider
var _tile_restitution_value: Label
var _tile_friction_value: Label
var _tile_props_syncing: bool = false

# Overlays
var _overlay_solid
var _overlay_restitution

# Collision cache: only solid cells exist here.
var collision_cells: Dictionary = {} # Dictionary[Vector2i, Dictionary]

# Test puck sandbox
var test_mode: bool = false
var _test_puck
var _test_accum: float = 0.0

# Pan state
var _panning: bool = false
var _pan_last_mouse: Vector2 = Vector2.ZERO


func _ready() -> void:
	_tilemaps = {
		"bg": tilemap_bg,
		"solid": tilemap_solid,
		"fg": tilemap_fg
	}
	_refresh_available_tilesets()
	_apply_tileset_package_if_present(_tileset_name)
	_tileset_meta = TilesetMetaScript.new()
	_tileset_meta.tileset_id = _tileset_name
	_tileset_meta_path = _resolve_tileset_meta_path(_tileset_name)
	_tileset_meta.load(_tileset_meta_path)
	_favorites_max_len = favorites.size()
	# Keep defaults aligned with inspector exports (exports are in tiles; state vars are pixels).
	map_width_tiles = map_width * LevelIO.TILE_SIZE
	map_height_tiles = map_height * LevelIO.TILE_SIZE

	_build_palette_ui()
	_build_new_map_ui()
	_build_load_map_ui()
	_build_status_ui()
	_build_help_overlay()
	_build_tile_properties_ui()
	_build_overlays()
	_apply_editor_zoom()

	# Ensure the cursor is visible even if the Sprite2D has no texture set in the scene.
	# (The scene sets a region_rect, but without a texture nothing is drawn.)
	if cursor_sprite.texture == null:
		var img := Image.create(LevelIO.TILE_SIZE, LevelIO.TILE_SIZE, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		cursor_sprite.texture = ImageTexture.create_from_image(img)
	# Make sure it renders above the tilemaps.
	cursor_sprite.z_index = 1000
	cursor_sprite.modulate = Color(1, 1, 0, 0.35)
	
	_create_new_map(map_width_tiles, map_height_tiles)
	reroute_tiles_by_meta()
	rebuild_collision_cache()
	_update_ui()
	_sync_tile_props_from_selection()


func _refresh_available_tilesets() -> void:
	_available_tilesets = TilesetIO.list_tileset_packages()
	_tileset_index = maxi(0, _available_tilesets.find(_tileset_name))


func _load_tileset_by_name(name: String) -> void:
	var n := String(name).strip_edges()
	if n == "":
		return
	_tileset_name = n
	_refresh_available_tilesets()
	_apply_tileset_package_if_present(_tileset_name)
	_tileset_meta.tileset_id = _tileset_name
	_tileset_meta_path = _resolve_tileset_meta_path(_tileset_name)
	_tileset_meta.load(_tileset_meta_path)
	_build_tileset_palette()
	_update_ui()


func _apply_tileset_package_if_present(name: String) -> void:
	_tileset_data = null
	var package_dir := "res://assets/tilesets/%s" % String(name).strip_edges()
	if not FileAccess.file_exists(package_dir + "/tileset.json"):
		return
	var res := TilesetIO.load_tileset(package_dir)
	if not bool(res.get("ok", false)):
		push_error(String(res.get("error", "Failed to load tileset")))
		return
	_tileset_data = res.get("data", null)
	if _tileset_data == null or _tileset_data.texture == null:
		return
	var ts := _build_runtime_tileset(_tileset_data.texture, _tileset_data.tile_size)
	for tm in [tilemap_bg, tilemap_solid, tilemap_fg]:
		tm.tile_set = ts


func _build_runtime_tileset(tex: Texture2D, tsz: Vector2i) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = tsz
	var atlas := TileSetAtlasSource.new()
	atlas.texture = tex
	atlas.texture_region_size = tsz
	ts.add_source(atlas)

	var img_size := tex.get_size()
	var cols := maxi(1, int(floor(img_size.x / float(tsz.x))))
	var rows := maxi(1, int(floor(img_size.y / float(tsz.y))))
	for y in range(rows):
		for x in range(cols):
			atlas.create_tile(Vector2i(x, y))
	return ts


func _map_width_cells() -> int:
	return maxi(1, int(map_width_tiles / LevelIO.TILE_SIZE))


func _map_height_cells() -> int:
	return maxi(1, int(map_height_tiles / LevelIO.TILE_SIZE))


func _process(_delta: float) -> void:
	if status_timer > 0.0:
		status_timer -= _delta
		if status_timer <= 0.0 and status_label != null:
			status_label.text = ""
	_update_ui()
	# While dragging, keep the preview responsive.
	if dragging:
		queue_redraw()

	if test_mode and _test_puck != null:
		_test_accum += _delta
		while _test_accum >= (1.0 / 60.0):
			_test_puck.step(1.0 / 60.0, collision_cells)
			_test_accum -= (1.0 / 60.0)


func _draw() -> void:
	# Editor-only rectangle preview when dragging.
	if dragging:
		var a := drag_start_cell
		var b := drag_end_cell
		var min_x: int = mini(a.x, b.x)
		var max_x: int = maxi(a.x, b.x)
		var min_y: int = mini(a.y, b.y)
		var max_y: int = maxi(a.y, b.y)

		var top_left_world := map_canvas.to_global(Vector2(min_x * LevelIO.TILE_SIZE, min_y * LevelIO.TILE_SIZE))
		var bottom_right_world := map_canvas.to_global(Vector2((max_x + 1) * LevelIO.TILE_SIZE, (max_y + 1) * LevelIO.TILE_SIZE))
		var rect := Rect2(to_local(top_left_world), bottom_right_world - top_left_world)

		var outline_only := Input.is_action_pressed("drift_modifier_ability")
		if not outline_only:
			draw_rect(rect, Color(0.2, 0.8, 1.0, 0.15), true)
		# Border
		draw_rect(rect, Color(0.2, 0.8, 1.0, 0.8), false, 2.0)

	# Entity mode removed: map entities are now derived from tiles/defs.


func _get_active_tilemap() -> TileMap:
	return _tilemaps.get(current_layer, tilemap_solid)


func _get_cell_under_mouse() -> Vector2i:
	# Mouse viewport -> world -> tilemap local -> map cell (Godot 4)
	# Using get_global_mouse_position() gives the world-space mouse position
	# taking the active Camera2D into account.
	var world_pos := get_global_mouse_position()
	var tilemap := _get_active_tilemap()
	var local_pos := tilemap.to_local(world_pos)
	var cell: Vector2i = tilemap.local_to_map(local_pos)
	cell.x = clampi(cell.x, 0, _map_width_cells() - 1)
	cell.y = clampi(cell.y, 0, _map_height_cells() - 1)
	return cell


func _set_cursor_cell(cell: Vector2i) -> void:
	if cell == cursor_cell:
		return
	cursor_cell = cell
	# Mouse hover selects a cell, but does not move the camera.
	_update_cursor_position(false)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	# Block map actions when interacting with the Tile Properties panel.
	if _tile_props_panel != null and (event is InputEventMouseButton or event is InputEventMouseMotion):
		var mp := get_viewport().get_mouse_position()
		if _tile_props_panel.get_global_rect().has_point(mp):
			return

	# Load Map dialog blocks map editing input while visible.
	if load_map_visible:
		if event.is_action_pressed("drift_editor_cancel"):
			_hide_load_map_dialog()
			get_viewport().set_input_as_handled()
			return
		# Let UI consume events; do not handle editor input.
		return

	# New Map dialog blocks map editing input while visible.
	if new_map_visible:
		if event.is_action_pressed("drift_editor_cancel"):
			_hide_new_map_dialog()
			get_viewport().set_input_as_handled()
			return
		# Let UI consume events; do not handle editor input.
		return

	# Palette blocks map editing input while visible.
	if palette_visible:
		if event.is_action_pressed("drift_editor_cancel") or event.is_action_pressed("drift_editor_toggle_palette"):
			_hide_palette()
			get_viewport().set_input_as_handled()
			return
		# Let UI consume events; do not handle editor input.
		return

	# While the help overlay is up it swallows everything except closing it.
	if help_visible:
		if event.is_action_pressed("drift_editor_help") or event.is_action_pressed("drift_editor_cancel"):
			_toggle_help_overlay()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed:
			get_viewport().set_input_as_handled()
		return

	# Undo/redo before anything else so they work regardless of tool or mode.
	if event.is_action_pressed("drift_editor_undo"):
		_undo()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("drift_editor_redo"):
		_redo()
		get_viewport().set_input_as_handled()
		return

	# F1 toggles the full hotkey overlay.
	if event.is_action_pressed("drift_editor_help"):
		_toggle_help_overlay()
		get_viewport().set_input_as_handled()
		return

	# Tool selection: B rect, L line, G bucket. I picks the tile under the cursor.
	if event.is_action_pressed("drift_editor_tool_rect"):
		_set_tool(Tool.RECT)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("drift_editor_tool_line"):
		_set_tool(Tool.LINE)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("drift_editor_tool_fill"):
		_set_tool(Tool.FILL)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("drift_editor_pick_tile"):
		_pick_tile_under_cursor()
		get_viewport().set_input_as_handled()
		return

	# F10 hands off to the tileset editor without a trip through the connect screen.
	if event.is_action_pressed("drift_editor_open_tileset_editor"):
		get_tree().change_scene_to_file("res://tools/tilemap_editor/TilemapEditor.tscn")
		get_viewport().set_input_as_handled()
		return

	# Ctrl+N opens New Map dialog.
	if event.is_action_pressed("drift_editor_new_map"):
		_show_new_map_dialog()
		get_viewport().set_input_as_handled()
		return

	# Q toggles tile palette (Shift+Q/E cycle favorites).
	if event.is_action_pressed("drift_editor_toggle_palette"):
		_show_palette()
		get_viewport().set_input_as_handled()
		return

	# Ctrl shortcuts should not trigger movement.
	if event.is_action_pressed("drift_editor_cycle_tileset"):
			_refresh_available_tilesets()
			if _available_tilesets.is_empty():
				_set_status("No tilesets found in res://assets/tilesets", true, 3.0)
				get_viewport().set_input_as_handled()
				return
			_tileset_index = wrapi(_tileset_index + 1, 0, _available_tilesets.size())
			_load_tileset_by_name(_available_tilesets[_tileset_index])
			_set_status("Tileset: %s" % _tileset_name, false, 2.0)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("drift_editor_paste"):
			_paste_map_from_clipboard()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("drift_editor_save"):
			_save_map()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("drift_editor_open_latest"):
		_load_latest_map()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("drift_editor_open"):
		_show_load_map_dialog()
		get_viewport().set_input_as_handled()
		return

	# Mode toggle removed (tile-only editor).
	if event.is_action_pressed("drift_editor_toggle_test_mode"):
			_toggle_test_mode()
			get_viewport().set_input_as_handled()
			return
		# Zoom presets.
	if event.is_action_pressed("drift_editor_zoom_2"):
			editor_zoom = 2.0
			_apply_editor_zoom()
			get_viewport().set_input_as_handled()
			return
	elif event.is_action_pressed("drift_editor_zoom_4"):
			editor_zoom = 4.0
			_apply_editor_zoom()
			get_viewport().set_input_as_handled()
			return
	elif event.is_action_pressed("drift_editor_zoom_8"):
			editor_zoom = 8.0
			_apply_editor_zoom()
			get_viewport().set_input_as_handled()
			return

	# +/- zoom
	if event.is_action_pressed("drift_editor_zoom_in"):
			editor_zoom = clampf(editor_zoom + 0.5, 1.0, 12.0)
			_apply_editor_zoom()
			get_viewport().set_input_as_handled()
			return
	elif event.is_action_pressed("drift_editor_zoom_out"):
			editor_zoom = clampf(editor_zoom - 0.5, 1.0, 12.0)
			_apply_editor_zoom()
			get_viewport().set_input_as_handled()
			return

	# Mouse hover updates the cursor cell.
	if event is InputEventMouseMotion:
		if _panning:
			var delta_screen: Vector2 = event.relative
			camera.global_position -= delta_screen / maxf(0.01, editor_zoom)
			_pan_last_mouse = get_viewport().get_mouse_position()
			return
		_set_cursor_cell(_get_cell_under_mouse())
		# If dragging, keep the drag endpoint in sync with cursor.
		if dragging:
			drag_end_cell = cursor_cell
			queue_redraw()
		return

	# Mouse buttons should act on the cell under the mouse.
	if event is InputEventMouseButton:
		# Zoom (mouse wheel)
		if event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var step := 0.5
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				editor_zoom = clampf(editor_zoom + step, 1.0, 12.0)
			else:
				editor_zoom = clampf(editor_zoom - step, 1.0, 12.0)
			_apply_editor_zoom()
			get_viewport().set_input_as_handled()
			return

		# Pan: MMB drag or Space+LMB drag
		if event.button_index == MOUSE_BUTTON_MIDDLE or (event.button_index == MOUSE_BUTTON_LEFT and Input.is_action_pressed("drift_editor_pan_modifier")):
			if event.pressed:
				_panning = true
				_pan_last_mouse = get_viewport().get_mouse_position()
				get_viewport().set_input_as_handled()
				return
			else:
				_panning = false
				_sync_camera_cell_from_camera_pos()
				get_viewport().set_input_as_handled()
				return

		_set_cursor_cell(_get_cell_under_mouse())

		# Test mode: click shoots puck; right click resets.
		if test_mode and _test_puck != null:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_test_puck.shoot_towards(map_canvas.to_local(get_global_mouse_position()))
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_reset_test_puck()
				get_viewport().set_input_as_handled()
				return

		# Entity mode removed.

	# Movement
	var move_delta := Vector2i.ZERO
	var speed := cursor_move_speed_fast if Input.is_action_pressed("drift_modifier_ability") else cursor_move_speed
	
	if event.is_action_pressed("drift_editor_camera_up"):
		move_delta.y -= speed
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drift_editor_camera_down"):
		move_delta.y += speed
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drift_editor_camera_left"):
		move_delta.x -= speed
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drift_editor_camera_right"):
		move_delta.x += speed
		get_viewport().set_input_as_handled()
	
	if move_delta != Vector2i.ZERO:
		# WASD moves the camera only. Cursor is mouse-controlled.
		camera_cell += move_delta
		camera_cell.x = clampi(camera_cell.x, 0, _map_width_cells() - 1)
		camera_cell.y = clampi(camera_cell.y, 0, _map_height_cells() - 1)
		# Apply camera move, then refresh cursor under the mouse so it stays decoupled.
		_update_cursor_position(true)
		_set_cursor_cell(_get_cell_under_mouse())
	
	# Place tile (Space) / Rectangle fill tool (LMB drag)
	if event.is_action_pressed("drift_editor_place_tile"):
		_place_tile()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not Input.is_action_pressed("drift_editor_pan_modifier"):
		if event.pressed:
			if current_tool == Tool.FILL:
				# Bucket fill is a single click, not a drag.
				_flood_fill(cursor_cell)
				get_viewport().set_input_as_handled()
			else:
				dragging = true
				drag_start_cell = cursor_cell
				drag_end_cell = cursor_cell
				queue_redraw()
				get_viewport().set_input_as_handled()
		else:
			if dragging:
				drag_end_cell = cursor_cell
				if current_tool == Tool.LINE:
					_draw_line_cells(drag_start_cell, drag_end_cell)
				else:
					_fill_rect(drag_start_cell, drag_end_cell, Input.is_action_pressed("drift_modifier_ability"))
				dragging = false
				queue_redraw()
				get_viewport().set_input_as_handled()
	
	# Erase tile (Backspace or RMB)
	if not test_mode and (event.is_action_pressed("drift_editor_erase_tile") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT)):
		_erase_tile()
		get_viewport().set_input_as_handled()
	
	# Cycle layer (Tab)
	if event.is_action_pressed("drift_editor_cycle_layer"):
		_cycle_layer()
		get_viewport().set_input_as_handled()
	
	# Cycle favorites (Q/E)
	if event.is_action_pressed("drift_editor_prev_favorite"):
		_cycle_favorite(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drift_editor_next_favorite"):
		_cycle_favorite(1)
		get_viewport().set_input_as_handled()
	
	# Save/Load handled above (Ctrl+S / Ctrl+O)
	
	# Exit (Esc)
	if event.is_action_pressed("drift_editor_cancel") and not (event is InputEventMouseButton):
		_exit_editor()
		get_viewport().set_input_as_handled()


func _is_boundary_cell(cell: Vector2i) -> bool:
	var w := _map_width_cells()
	var h := _map_height_cells()
	return cell.x == 0 or cell.y == 0 or cell.x == w - 1 or cell.y == h - 1


# --- Undo / redo -------------------------------------------------------------
#
# Every tile write in the editor goes through _write_cell(), which records the
# previous atlas coords. Edits are grouped into ops by _begin_op()/_commit_op(), so a
# rect fill or a flood fill undoes as one step. Document-level changes (new map, load,
# paste) cannot be expressed as cell diffs, so they clear both stacks instead.

const UNDO_MAX_OPS: int = 64
# Total recorded cell changes held across the whole stack. A full-map rect fill is a
# legitimate single op, so cap by changes rather than only by op count.
const UNDO_MAX_CHANGES: int = 400000
const NO_TILE := Vector2i(-1, -1)

var _undo_stack: Array = []   # Array[{label: String, changes: Array}]
var _redo_stack: Array = []
var _pending_changes: Array = []
var _op_open: bool = false
var _undo_change_count: int = 0


func _cell_atlas(layer_name: String, cell: Vector2i) -> Vector2i:
	var tm: TileMap = _tilemaps.get(layer_name, null)
	if tm == null or tm.get_cell_source_id(0, cell) < 0:
		return NO_TILE
	return tm.get_cell_atlas_coords(0, cell)


func _write_cell(layer_name: String, cell: Vector2i, atlas: Vector2i) -> void:
	## The single tile-mutation primitive. atlas == NO_TILE erases.
	var tm: TileMap = _tilemaps.get(layer_name, null)
	if tm == null:
		return
	var before := _cell_atlas(layer_name, cell)
	if before == atlas:
		return
	if _op_open:
		_pending_changes.append({"layer": layer_name, "cell": cell, "from": before, "to": atlas})
	if atlas == NO_TILE:
		tm.erase_cell(0, cell)
	else:
		tm.set_cell(0, cell, 0, atlas)


func _begin_op() -> void:
	_pending_changes = []
	_op_open = true


func _commit_op(label: String) -> void:
	_op_open = false
	if _pending_changes.is_empty():
		return
	_undo_stack.append({"label": label, "changes": _pending_changes})
	_undo_change_count += _pending_changes.size()
	_pending_changes = []
	_redo_stack.clear()
	while _undo_stack.size() > UNDO_MAX_OPS or (_undo_change_count > UNDO_MAX_CHANGES and _undo_stack.size() > 1):
		var dropped: Dictionary = _undo_stack.pop_front()
		_undo_change_count -= int((dropped["changes"] as Array).size())
	rebuild_collision_cache()
	_update_ui()


func _clear_undo_history() -> void:
	## Called after new/load/paste: those replace the document wholesale.
	_undo_stack.clear()
	_redo_stack.clear()
	_pending_changes.clear()
	_op_open = false
	_undo_change_count = 0


func _apply_changes(changes: Array, use_from: bool) -> void:
	var was_open := _op_open
	_op_open = false  # replaying history must not record new history
	# Reverse order on undo so overlapping writes to one cell unwind correctly.
	var idx_range: Array = range(changes.size() - 1, -1, -1) if use_from else range(changes.size())
	for i in idx_range:
		var c: Dictionary = changes[i]
		_write_cell(String(c["layer"]), c["cell"], c["from"] if use_from else c["to"])
	_op_open = was_open
	rebuild_collision_cache()


func _undo() -> void:
	if _undo_stack.is_empty():
		_set_status("Nothing to undo", false, 1.5)
		return
	var op: Dictionary = _undo_stack.pop_back()
	_undo_change_count -= int((op["changes"] as Array).size())
	_apply_changes(op["changes"], true)
	_redo_stack.append(op)
	_set_status("Undo: %s" % String(op["label"]), false, 1.5)
	_update_ui()


func _redo() -> void:
	if _redo_stack.is_empty():
		_set_status("Nothing to redo", false, 1.5)
		return
	var op: Dictionary = _redo_stack.pop_back()
	_apply_changes(op["changes"], false)
	_undo_stack.append(op)
	_undo_change_count += int((op["changes"] as Array).size())
	_set_status("Redo: %s" % String(op["label"]), false, 1.5)
	_update_ui()


func _selected_dest_layer() -> String:
	return _meta_layer_to_map_layer(String(_tileset_meta.get_tile_meta(selected_atlas_coords).get("layer", "mid")))


func _place_tile_at(cell: Vector2i) -> void:
	if _is_boundary_cell(cell):
		_set_status("Boundary tiles are generated and cannot be edited", true, 2.0)
		return
	_begin_op()
	_write_cell(_selected_dest_layer(), cell, selected_atlas_coords)
	_commit_op("place tile")


func _place_tile() -> void:
	_place_tile_at(cursor_cell)


func _erase_tile_at(cell: Vector2i) -> void:
	if _is_boundary_cell(cell):
		_set_status("Boundary tiles are generated and cannot be edited", true, 2.0)
		return
	_begin_op()
	for layer_name in ["bg", "solid", "fg"]:
		_write_cell(layer_name, cell, NO_TILE)
	_commit_op("erase tile")


func _erase_tile() -> void:
	_erase_tile_at(cursor_cell)


func _fill_rect(a: Vector2i, b: Vector2i, outline_only: bool) -> void:
	var min_x: int = mini(a.x, b.x)
	var max_x: int = maxi(a.x, b.x)
	var min_y: int = mini(a.y, b.y)
	var max_y: int = maxi(a.y, b.y)
	var dest_layer := _selected_dest_layer()
	_begin_op()
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var cell := Vector2i(x, y)
			if _is_boundary_cell(cell):
				continue
			if outline_only and not (x == min_x or x == max_x or y == min_y or y == max_y):
				continue
			_write_cell(dest_layer, cell, selected_atlas_coords)
	_commit_op("outline" if outline_only else "rect fill")


func _draw_line_cells(a: Vector2i, b: Vector2i) -> void:
	## Bresenham between two cells on the selected tile's destination layer.
	var dest_layer := _selected_dest_layer()
	var dx: int = absi(b.x - a.x)
	var dy: int = -absi(b.y - a.y)
	var sx: int = 1 if a.x < b.x else -1
	var sy: int = 1 if a.y < b.y else -1
	var err: int = dx + dy
	var cur := a
	_begin_op()
	while true:
		if not _is_boundary_cell(cur):
			_write_cell(dest_layer, cur, selected_atlas_coords)
		if cur == b:
			break
		var e2: int = err * 2
		if e2 >= dy:
			err += dy
			cur.x += sx
		if e2 <= dx:
			err += dx
			cur.y += sy
	_commit_op("line")


func _flood_fill(start: Vector2i) -> void:
	## Bucket fill: replaces the contiguous region of cells matching whatever is under the
	## start cell on the target layer. Bounded by the map edge and by UNDO_MAX_CHANGES.
	var dest_layer := _selected_dest_layer()
	if _is_boundary_cell(start):
		_set_status("Boundary tiles are generated and cannot be edited", true, 2.0)
		return
	var target := _cell_atlas(dest_layer, start)
	if target == selected_atlas_coords:
		_set_status("Flood fill: already that tile", false, 1.5)
		return
	var w := _map_width_cells()
	var h := _map_height_cells()
	var seen: Dictionary = {}
	var queue: Array = [start]
	seen[start] = true
	_begin_op()
	var guard: int = 0
	while not queue.is_empty():
		guard += 1
		if guard > UNDO_MAX_CHANGES:
			_set_status("Flood fill stopped at %d cells" % guard, true, 3.0)
			break
		var cell: Vector2i = queue.pop_back()
		_write_cell(dest_layer, cell, selected_atlas_coords)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cell + d
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h or seen.has(n):
				continue
			if _is_boundary_cell(n) or _cell_atlas(dest_layer, n) != target:
				continue
			seen[n] = true
			queue.append(n)
	_commit_op("flood fill")


func _pick_tile_under_cursor() -> void:
	## Eyedropper: adopt whatever tile is under the cursor, topmost layer first.
	for layer_name in ["fg", "solid", "bg"]:
		var atlas := _cell_atlas(layer_name, cursor_cell)
		if atlas != NO_TILE:
			selected_atlas_coords = atlas
			_sync_tile_props_from_selection()
			_set_status("Picked tile (%d,%d)" % [atlas.x, atlas.y], false, 1.5)
			_update_ui()
			return
	_set_status("No tile under cursor", true, 1.5)


func _cycle_layer() -> void:
	if current_layer == "bg":
		current_layer = "solid"
	elif current_layer == "solid":
		current_layer = "fg"
	else:
		current_layer = "bg"


func _cycle_favorite(direction: int) -> void:
	favorite_index = wrapi(favorite_index + direction, 0, favorites.size())
	selected_atlas_coords = favorites[favorite_index]
	_sync_tile_props_from_selection()



func _update_cursor_position(move_camera: bool = true) -> void:
	var cursor_local_pos := Vector2(cursor_cell) * LevelIO.TILE_SIZE + Vector2.ONE * (LevelIO.TILE_SIZE / 2.0)
	cursor_sprite.position = cursor_local_pos
	if move_camera:
		var camera_local_pos := Vector2(camera_cell) * LevelIO.TILE_SIZE + Vector2.ONE * (LevelIO.TILE_SIZE / 2.0)
		camera.global_position = map_canvas.to_global(camera_local_pos)
	queue_redraw()


const HELP_TEXT := """EDITOR HOTKEYS                                    [F1] close

TOOLS                          EDIT
  B    rect fill (drag)          LMB drag   apply tool
  L    line (drag)               Shift+drag rect outline
  G    bucket fill (click)       Space      place at cursor
  I    pick tile under cursor    Backspace / RMB   erase
                                 Ctrl+Z     undo
VIEW                             Ctrl+Y     redo
  WASD      move camera
  Wheel     zoom               TILES
  + / -     zoom                 Q          tile palette
  1 / 2 / 3 zoom presets         Shift+Q/E  cycle favourites
  MMB drag  pan                  Tab        cycle layer
  Space+LMB pan                  Ctrl+T     cycle tileset

FILE                           OTHER
  Ctrl+N  new map                T    physics test puck
  Ctrl+S  save                   F10  tileset editor
  Ctrl+O  open                   Esc  exit editor
  Ctrl+Shift+O  open latest
  Ctrl+V  paste map JSON"""

var help_visible: bool = false
var help_layer: CanvasLayer
var help_label: Label


func _set_tool(tool_id: int) -> void:
	current_tool = tool_id
	_set_status("Tool: %s" % String(TOOL_NAMES[tool_id]), false, 1.5)
	_update_ui()


func _build_help_overlay() -> void:
	help_layer = CanvasLayer.new()
	help_layer.name = "HelpOverlay"
	help_layer.layer = 90
	help_layer.visible = false
	add_child(help_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	help_layer.add_child(dim)
	help_label = Label.new()
	help_label.text = HELP_TEXT
	help_label.position = Vector2(32, 28)
	help_label.add_theme_font_size_override("font_size", 15)
	help_layer.add_child(help_label)


func _toggle_help_overlay() -> void:
	help_visible = not help_visible
	if help_layer != null:
		help_layer.visible = help_visible


func _update_ui() -> void:
	# One compact status line. The full key list lives behind F1 so it is not permanently
	# covering the top-left of the map.
	var undo_hint := ""
	if not _undo_stack.is_empty():
		undo_hint = "  |  Undo: %d" % _undo_stack.size()
	ui_label.text = "%d×%d  |  Cell %d,%d  |  Layer %s  |  Tool %s  |  Tile (%d,%d)  |  Zoom %.1fx%s        [F1] help" % [
		map_width_tiles, map_height_tiles,
		cursor_cell.x, cursor_cell.y,
		current_layer.to_upper(),
		String(TOOL_NAMES[current_tool]),
		selected_atlas_coords.x, selected_atlas_coords.y,
		editor_zoom, undo_hint,
	]


func _build_status_ui() -> void:
	if ui_root == null:
		return
	status_label = Label.new()
	status_label.name = "Status"
	status_label.position = Vector2(12, 72)
	status_label.modulate = Color(1, 0.6, 0.6, 1)
	ui_root.add_child(status_label)
	status_label.text = ""


func _set_status(msg: String, is_error: bool = false, seconds: float = 4.0) -> void:
	if status_label == null:
		return
	status_label.text = msg
	status_label.modulate = Color(1, 0.35, 0.35, 1) if is_error else Color(0.6, 1, 0.6, 1)
	status_timer = seconds





func _paste_map_from_clipboard() -> void:
	# History is cleared only once the paste is known to be good -- a rejected paste
	# must not cost the user their undo stack. _create_new_map() below does the clearing.
	var s = DisplayServer.clipboard_get()
	var parsed = LevelIO.parse_map_json(s)
	if not bool(parsed.get("ok", false)):
		_set_status("Paste failed: " + String(parsed.get("error", "Unknown error")), true)
		return

	var raw: Dictionary = parsed.get("data", {})
	var validated := DriftMap.validate_and_canonicalize(raw)
	if not bool(validated.get("ok", false)):
		_set_status("Paste failed: invalid map", true)
		for e in (validated.get("errors", []) as Array):
			print("[MAP] paste error: ", String(e))
		return
	var map: Dictionary = validated.get("map", {})
	var meta: Dictionary = map.get("meta", {})
	var w_tiles: int = int(meta.get("w", 0))
	var h_tiles: int = int(meta.get("h", 0))
	if w_tiles <= 0 or h_tiles <= 0:
		_set_status("Paste failed: missing map size", true)
		return

	# Resize the editor map BEFORE applying tiles.
	_create_new_map(w_tiles * LevelIO.TILE_SIZE, h_tiles * LevelIO.TILE_SIZE)
	LevelIO.apply_map_data(map, _tilemaps)
	reroute_tiles_by_meta()
	rebuild_collision_cache()
	entities = map.get("entities", [])
	queue_redraw()

	var entities_count: int = (map.get("entities", []) as Array).size()
	var tiles_count: int = 0
	for layer_name in ["bg", "solid", "fg"]:
		var layer = (map.get("layers", {}) as Dictionary).get(layer_name, [])
		if layer is Array:
			tiles_count += (layer as Array).size()
	print("Map pasted from clipboard: ", w_tiles, "x", h_tiles, ", ", tiles_count, " tiles, ", entities_count, " entities")
	_set_status("Map pasted: %dx%d" % [w_tiles, h_tiles], false)


func _build_new_map_ui() -> void:
	new_map_layer = CanvasLayer.new()
	new_map_layer.layer = 60
	new_map_layer.visible = false
	add_child(new_map_layer)

	new_map_panel = Panel.new()
	new_map_panel.name = "NewMapPanel"
	new_map_panel.custom_minimum_size = Vector2(520, 360)
	new_map_panel.set_anchors_preset(Control.PRESET_CENTER)
	new_map_panel.position = -new_map_panel.custom_minimum_size * 0.5
	new_map_layer.add_child(new_map_panel)

	var root := VBoxContainer.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	new_map_panel.add_child(root)

	var title := Label.new()
	title.text = "New Map"
	root.add_child(title)

	var presets := GridContainer.new()
	presets.columns = 3
	root.add_child(presets)

	# Preset buttons
	_add_new_map_preset_button(presets, "256×256", 256, 256)
	_add_new_map_preset_button(presets, "512×512", 512, 512)
	_add_new_map_preset_button(presets, "1024×1024", 1024, 1024)
	_add_new_map_preset_button(presets, "2048×2048", 2048, 2048)
	_add_new_map_preset_button(presets, "1024×768", 1024, 768)
	_add_new_map_preset_button(presets, "2048×1024", 2048, 1024)

	var dims_row := HBoxContainer.new()
	dims_row.add_theme_constant_override("separation", 8)
	root.add_child(dims_row)

	var w_label := Label.new()
	w_label.text = "Width"
	dims_row.add_child(w_label)

	new_map_width_spin = SpinBox.new()
	new_map_width_spin.min_value = 64
	new_map_width_spin.max_value = 4096
	new_map_width_spin.step = 16
	new_map_width_spin.value = map_width_tiles
	dims_row.add_child(new_map_width_spin)

	var h_label := Label.new()
	h_label.text = "Height"
	dims_row.add_child(h_label)

	new_map_height_spin = SpinBox.new()
	new_map_height_spin.min_value = 64
	new_map_height_spin.max_value = 4096
	new_map_height_spin.step = 16
	new_map_height_spin.value = map_height_tiles
	dims_row.add_child(new_map_height_spin)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)

	var create_btn := Button.new()
	create_btn.text = "Create"
	create_btn.pressed.connect(_on_new_map_create_pressed)
	actions.add_child(create_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_hide_new_map_dialog)
	actions.add_child(cancel_btn)


func _add_new_map_preset_button(parent: GridContainer, label: String, w: int, h: int) -> void:
	var btn := Button.new()
	btn.text = label
	btn.pressed.connect(_on_new_map_preset_pressed.bind(w, h))
	parent.add_child(btn)


func _on_new_map_preset_pressed(w: int, h: int) -> void:
	if new_map_width_spin != null:
		new_map_width_spin.value = w
	if new_map_height_spin != null:
		new_map_height_spin.value = h


func _on_new_map_create_pressed() -> void:
	var w := int(new_map_width_spin.value)
	var h := int(new_map_height_spin.value)
	_create_new_map(w, h)
	_hide_new_map_dialog()
	_update_ui()


func _show_new_map_dialog() -> void:
	# Ensure other overlays are closed.
	_hide_palette()
	_hide_load_map_dialog()
	new_map_visible = true
	new_map_layer.visible = true
	# Initialize values to current map size.
	new_map_width_spin.value = map_width_tiles
	new_map_height_spin.value = map_height_tiles
	# Stop any in-progress rectangle drag.
	dragging = false
	queue_redraw()


func _hide_new_map_dialog() -> void:
	new_map_visible = false
	if new_map_layer != null:
		new_map_layer.visible = false


func _create_new_map(width: int, height: int) -> void:
	_clear_undo_history()  # a new map replaces the document
	map_width_tiles = width
	map_height_tiles = height
	# Keep inspector exports in sync (exports store tile dimensions).
	map_width = _map_width_cells()
	map_height = _map_height_cells()

	for tilemap in _tilemaps.values():
		tilemap.clear()
	entities = []
	LevelIO.apply_boundary(tilemap_solid, _map_width_cells(), _map_height_cells())
	reroute_tiles_by_meta()
	rebuild_collision_cache()
	if test_mode and _test_puck != null:
		_reset_test_puck()

	var w_cells := _map_width_cells()
	var h_cells := _map_height_cells()
	cursor_cell = Vector2i(w_cells / 2, h_cells / 2)
	cursor_cell.x = clampi(cursor_cell.x, 0, w_cells - 1)
	cursor_cell.y = clampi(cursor_cell.y, 0, h_cells - 1)
	# Put the camera on the cursor center.
	camera_cell = cursor_cell
	_update_cursor_position(true)


func _build_palette_ui() -> void:
	palette_layer = CanvasLayer.new()
	palette_layer.layer = 50
	palette_layer.visible = false
	add_child(palette_layer)

	palette_panel = Panel.new()
	palette_panel.name = "TilePalettePanel"
	palette_panel.custom_minimum_size = Vector2(420, 320)
	palette_panel.set_anchors_preset(Control.PRESET_CENTER)
	palette_panel.position = -palette_panel.custom_minimum_size * 0.5
	palette_layer.add_child(palette_panel)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	palette_panel.add_child(scroll)

	palette_grid = GridContainer.new()
	palette_grid.name = "Grid"
	palette_grid.columns = PALETTE_COLUMNS
	scroll.add_child(palette_grid)

	_build_tileset_palette()


func _build_tileset_palette() -> void:
	# Use the TileSet from any of the tilemaps (they all share the same tileset).
	var ts: TileSet = tilemap_bg.tile_set
	if ts == null:
		return

	palette_source_id = -1
	palette_atlas = null
	palette_texture = null

	for i in range(ts.get_source_count()):
		var sid := ts.get_source_id(i)
		var src := ts.get_source(sid)
		if src is TileSetAtlasSource:
			palette_source_id = int(sid)
			palette_atlas = src
			break

	if palette_atlas == null:
		return

	palette_texture = palette_atlas.texture
	if palette_texture == null:
		return

	# Clear any existing buttons.
	for child in palette_grid.get_children():
		child.queue_free()

	var tile_size: Vector2i = palette_atlas.texture_region_size
	if tile_size.x <= 0 or tile_size.y <= 0:
		# Fallback to editor tile size.
		tile_size = Vector2i(LevelIO.TILE_SIZE, LevelIO.TILE_SIZE)

	var tex_size: Vector2i = palette_texture.get_size()
	var cols: int = maxi(1, tex_size.x / tile_size.x)
	var rows: int = maxi(1, tex_size.y / tile_size.y)

	for y in range(rows):
		for x in range(cols):
			var at := AtlasTexture.new()
			at.atlas = palette_texture
			at.region = Rect2(float(x * tile_size.x), float(y * tile_size.y), float(tile_size.x), float(tile_size.y))

			var btn := TextureButton.new()
			btn.texture_normal = at
			btn.custom_minimum_size = Vector2(tile_size.x, tile_size.y)
			btn.set_meta("atlas_coords", Vector2i(x, y))
			btn.pressed.connect(_on_palette_tile_pressed.bind(btn))
			palette_grid.add_child(btn)


func _on_palette_tile_pressed(button: TextureButton) -> void:
	var coords := button.get_meta("atlas_coords") as Vector2i
	selected_atlas_coords = coords
	_sync_tile_props_from_selection()
	# Update favorites: most-recent-first, dedupe, preserve max length.
	var existing := favorites.find(coords)
	if existing != -1:
		favorites.remove_at(existing)
	favorites.insert(0, coords)
	while favorites.size() > _favorites_max_len and _favorites_max_len > 0:
		favorites.pop_back()
	favorite_index = 0
	_hide_palette()
	_update_ui()


func _resolve_tileset_meta_path(tileset_name: String) -> String:
	var ts := String(tileset_name).strip_edges()
	if ts == "":
		ts = "subspace_base"
	var packaged := "res://assets/tilesets/%s/tiles_def.json" % ts
	if FileAccess.file_exists(packaged):
		return packaged
	return "res://client/graphics/tilesets/%s/tiles_meta.json" % ts


func _meta_layer_to_map_layer(layer: String) -> String:
	var l := layer.strip_edges().to_lower()
	if l == "bg":
		return "bg"
	if l == "fg":
		return "fg"
	return "solid" # mid


func _apply_editor_zoom() -> void:
	editor_zoom = clampf(editor_zoom, 1.0, 12.0)
	if map_canvas != null:
		map_canvas.scale = Vector2(editor_zoom, editor_zoom)
	# Keep camera anchored to its logical cell.
	_update_cursor_position(true)
	if _overlay_solid != null:
		_overlay_solid.queue_redraw()
	if _overlay_restitution != null:
		_overlay_restitution.queue_redraw()


func _sync_camera_cell_from_camera_pos() -> void:
	if camera == null or map_canvas == null:
		return
	var local := map_canvas.to_local(camera.global_position)
	camera_cell = Vector2i(int(floor(local.x / float(LevelIO.TILE_SIZE))), int(floor(local.y / float(LevelIO.TILE_SIZE))))
	camera_cell.x = clampi(camera_cell.x, 0, _map_width_cells() - 1)
	camera_cell.y = clampi(camera_cell.y, 0, _map_height_cells() - 1)


func rebuild_collision_cache() -> void:
	collision_cells.clear()
	if _tileset_meta == null:
		return

	var used_by_layer: Dictionary = {}
	for layer_name in ["bg", "solid", "fg"]:
		var tm: TileMap = _tilemaps.get(layer_name, null)
		if tm == null:
			continue
		var used: Array = tm.get_used_cells(0)
		used.sort_custom(Callable(self, "_cell_less"))
		used_by_layer[layer_name] = used

	for layer_name in ["bg", "solid", "fg"]:
		var tm: TileMap = _tilemaps.get(layer_name, null)
		if tm == null:
			continue
		var used: Array = used_by_layer.get(layer_name, [])
		for cell in used:
			if typeof(cell) != TYPE_VECTOR2I:
				continue
			var atlas: Vector2i = tm.get_cell_atlas_coords(0, cell)
			if atlas.x < 0 or atlas.y < 0:
				continue
			var meta: Dictionary = _tileset_meta.get_tile_meta(atlas)
			if not bool(meta.get("solid", false)):
				continue
			collision_cells[cell] = {
				"restitution": clampf(float(meta.get("restitution", 0.0)), 0.0, 1.2),
				"friction": clampf(float(meta.get("friction", 0.0)), 0.0, 1.0),
			}

	if _overlay_solid != null:
		_overlay_solid.set_collision_cells(collision_cells)
	if _overlay_restitution != null:
		_overlay_restitution.set_collision_cells(collision_cells)


func reroute_tiles_by_meta() -> void:
	if _tileset_meta == null:
		return
	var placed: Dictionary = {} # Vector2i -> Vector2i(atlas)
	for layer_name in ["bg", "solid", "fg"]:
		var tm: TileMap = _tilemaps.get(layer_name, null)
		if tm == null:
			continue
		var used: Array = tm.get_used_cells(0)
		used.sort_custom(Callable(self, "_cell_less"))
		for cell in used:
			if typeof(cell) != TYPE_VECTOR2I:
				continue
			var atlas: Vector2i = tm.get_cell_atlas_coords(0, cell)
			if atlas.x < 0 or atlas.y < 0:
				continue
			placed[cell] = atlas

	# Clear all tilemaps
	for layer_name in ["bg", "solid", "fg"]:
		var tm: TileMap = _tilemaps.get(layer_name, null)
		if tm != null:
			tm.clear()

	var cells: Array = placed.keys()
	cells.sort_custom(Callable(self, "_cell_less"))
	for cell in cells:
		var atlas: Vector2i = placed[cell]
		var meta: Dictionary = _tileset_meta.get_tile_meta(atlas)
		var dest := _meta_layer_to_map_layer(String(meta.get("layer", "mid")))
		var tm: TileMap = _tilemaps.get(dest, null)
		if tm != null:
			tm.set_cell(0, cell, 0, atlas)


func _cell_less(a, b) -> bool:
	if int(a.x) != int(b.x):
		return int(a.x) < int(b.x)
	return int(a.y) < int(b.y)


func _build_tile_properties_ui() -> void:
	if ui_root == null:
		return

	_tile_props_panel = Panel.new()
	_tile_props_panel.name = "TilePropertiesPanel"
	_tile_props_panel.custom_minimum_size = Vector2(280, 260)
	_tile_props_panel.anchor_left = 1.0
	_tile_props_panel.anchor_right = 1.0
	_tile_props_panel.anchor_top = 0.0
	_tile_props_panel.anchor_bottom = 0.0
	_tile_props_panel.offset_left = -300.0
	_tile_props_panel.offset_right = -12.0
	_tile_props_panel.offset_top = 12.0
	_tile_props_panel.offset_bottom = 12.0 + 260.0
	ui_root.add_child(_tile_props_panel)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	_tile_props_panel.add_child(root)

	var title := Label.new()
	title.text = "Tile Properties"
	root.add_child(title)

	# Layer
	var layer_row := HBoxContainer.new()
	layer_row.add_theme_constant_override("separation", 8)
	root.add_child(layer_row)
	var layer_lbl := Label.new()
	layer_lbl.text = "Layer"
	layer_row.add_child(layer_lbl)
	_tile_layer_option = OptionButton.new()
	_tile_layer_option.add_item("bg")
	_tile_layer_option.add_item("mid")
	_tile_layer_option.add_item("fg")
	_tile_layer_option.item_selected.connect(_on_tile_layer_selected)
	layer_row.add_child(_tile_layer_option)

	# Solid
	_tile_solid_check = CheckBox.new()
	_tile_solid_check.text = "Solid"
	_tile_solid_check.toggled.connect(_on_tile_solid_toggled)
	root.add_child(_tile_solid_check)

	# Restitution
	var rest_lbl := Label.new()
	rest_lbl.text = "Restitution"
	root.add_child(rest_lbl)
	var rest_row := HBoxContainer.new()
	rest_row.add_theme_constant_override("separation", 8)
	root.add_child(rest_row)
	_tile_restitution_slider = HSlider.new()
	_tile_restitution_slider.min_value = 0.0
	_tile_restitution_slider.max_value = 1.2
	_tile_restitution_slider.step = 0.01
	_tile_restitution_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tile_restitution_slider.value_changed.connect(_on_tile_restitution_changed)
	rest_row.add_child(_tile_restitution_slider)
	_tile_restitution_value = Label.new()
	_tile_restitution_value.text = "0.00"
	rest_row.add_child(_tile_restitution_value)

	# Friction
	var fr_lbl := Label.new()
	fr_lbl.text = "Friction"
	root.add_child(fr_lbl)
	var fr_row := HBoxContainer.new()
	fr_row.add_theme_constant_override("separation", 8)
	root.add_child(fr_row)
	_tile_friction_slider = HSlider.new()
	_tile_friction_slider.min_value = 0.0
	_tile_friction_slider.max_value = 1.0
	_tile_friction_slider.step = 0.01
	_tile_friction_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tile_friction_slider.value_changed.connect(_on_tile_friction_changed)
	fr_row.add_child(_tile_friction_slider)
	_tile_friction_value = Label.new()
	_tile_friction_value.text = "0.00"
	fr_row.add_child(_tile_friction_value)


func _build_overlays() -> void:
	if ui_root == null:
		return
	_overlay_solid = TileOverlayScript.new()
	_overlay_solid.mode = TileOverlayScript.Mode.SOLID
	_overlay_solid.camera = camera
	_overlay_solid.map_canvas = map_canvas
	ui_root.add_child(_overlay_solid)

	_overlay_restitution = TileOverlayScript.new()
	_overlay_restitution.mode = TileOverlayScript.Mode.RESTITUTION
	_overlay_restitution.camera = camera
	_overlay_restitution.map_canvas = map_canvas
	ui_root.add_child(_overlay_restitution)

	_overlay_solid.set_collision_cells(collision_cells)
	_overlay_restitution.set_collision_cells(collision_cells)


func _sync_tile_props_from_selection() -> void:
	if _tileset_meta == null:
		return
	if _tile_layer_option == null:
		return
	_tile_props_syncing = true
	var meta: Dictionary = _tileset_meta.get_tile_meta(selected_atlas_coords)
	var layer := String(meta.get("layer", "mid"))
	var idx := 1
	if layer == "bg":
		idx = 0
	elif layer == "fg":
		idx = 2
	_tile_layer_option.select(idx)
	_tile_solid_check.button_pressed = bool(meta.get("solid", false))
	_tile_restitution_slider.value = float(meta.get("restitution", 0.0))
	_tile_friction_slider.value = float(meta.get("friction", 0.0))
	_tile_restitution_value.text = "%.2f" % float(_tile_restitution_slider.value)
	_tile_friction_value.text = "%.2f" % float(_tile_friction_slider.value)
	_tile_props_syncing = false


func _apply_tile_meta_patch(patch: Dictionary) -> void:
	if _tile_props_syncing:
		return
	if _tileset_meta == null:
		return
	_tileset_meta.set_tile_meta(selected_atlas_coords, patch)
	_tileset_meta.save(_tileset_meta_path)
	reroute_tiles_by_meta()
	rebuild_collision_cache()


func _on_tile_layer_selected(index: int) -> void:
	var layer := "mid"
	if index == 0:
		layer = "bg"
	elif index == 2:
		layer = "fg"
	_apply_tile_meta_patch({"layer": layer})


func _on_tile_solid_toggled(pressed: bool) -> void:
	_apply_tile_meta_patch({"solid": pressed})


func _on_tile_restitution_changed(v: float) -> void:
	if _tile_restitution_value != null:
		_tile_restitution_value.text = "%.2f" % clampf(v, 0.0, 1.2)
	_apply_tile_meta_patch({"restitution": v})


func _on_tile_friction_changed(v: float) -> void:
	if _tile_friction_value != null:
		_tile_friction_value.text = "%.2f" % clampf(v, 0.0, 1.0)
	_apply_tile_meta_patch({"friction": v})


func _toggle_test_mode() -> void:
	test_mode = not test_mode
	if test_mode:
		_spawn_test_puck()
		_set_status("Test mode ON", false, 1.5)
	else:
		_destroy_test_puck()
		_set_status("Test mode OFF", false, 1.5)


func _spawn_test_puck() -> void:
	if _test_puck != null:
		return
	_test_puck = TestPuckScript.new()
	_test_puck.tile_size = Vector2i(LevelIO.TILE_SIZE, LevelIO.TILE_SIZE)
	map_canvas.add_child(_test_puck)
	_reset_test_puck()


func _destroy_test_puck() -> void:
	if _test_puck != null:
		_test_puck.queue_free()
		_test_puck = null
	_test_accum = 0.0


func _reset_test_puck() -> void:
	if _test_puck == null:
		return
	var center_cell := Vector2i(_map_width_cells() / 2, _map_height_cells() / 2)
	var p := Vector2(center_cell) * LevelIO.TILE_SIZE + Vector2.ONE * (LevelIO.TILE_SIZE / 2.0)
	_test_puck.reset(p)


func _show_palette() -> void:
	palette_visible = true
	palette_layer.visible = true
	# Stop any in-progress rectangle drag.
	dragging = false
	queue_redraw()

	# Position near mouse (viewport space), clamped to screen.
	var vp := get_viewport_rect().size
	var pos := get_viewport().get_mouse_position() + Vector2(12, 12)
	var size := palette_panel.size
	if size.x <= 0 or size.y <= 0:
		size = palette_panel.custom_minimum_size
	pos.x = clampf(pos.x, 8.0, vp.x - size.x - 8.0)
	pos.y = clampf(pos.y, 8.0, vp.y - size.y - 8.0)
	palette_panel.position = pos


func _hide_palette() -> void:
	palette_visible = false
	if palette_layer != null:
		palette_layer.visible = false


func _build_load_map_ui() -> void:
	load_map_layer = CanvasLayer.new()
	load_map_layer.layer = 70
	load_map_layer.visible = false
	add_child(load_map_layer)

	load_map_panel = Panel.new()
	load_map_panel.name = "LoadMapPanel"
	load_map_panel.custom_minimum_size = Vector2(560, 420)
	load_map_panel.set_anchors_preset(Control.PRESET_CENTER)
	load_map_panel.position = -load_map_panel.custom_minimum_size * 0.5
	load_map_layer.add_child(load_map_panel)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	load_map_panel.add_child(root)

	var title := Label.new()
	title.text = "Load Map"
	root.add_child(title)

	load_map_list = ItemList.new()
	load_map_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	load_map_list.select_mode = ItemList.SELECT_SINGLE
	load_map_list.item_activated.connect(_on_load_map_item_activated)
	root.add_child(load_map_list)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)

	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.pressed.connect(_on_load_map_load_pressed)
	actions.add_child(load_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_hide_load_map_dialog)
	actions.add_child(cancel_btn)


func _show_load_map_dialog() -> void:
	_hide_palette()
	_hide_new_map_dialog()
	_refresh_load_map_list()
	load_map_visible = true
	load_map_layer.visible = true
	# Stop any in-progress rectangle drag.
	dragging = false
	queue_redraw()


func _hide_load_map_dialog() -> void:
	load_map_visible = false
	if load_map_layer != null:
		load_map_layer.visible = false


func _refresh_load_map_list() -> void:
	_load_map_files = PackedStringArray()
	load_map_list.clear()

	var dir_path := "user://maps"
	if not DirAccess.dir_exists_absolute(dir_path):
		load_map_list.add_item("(no saved maps)")
		load_map_list.set_item_disabled(0, true)
		return

	var dir := DirAccess.open(dir_path)
	if dir == null:
		load_map_list.add_item("(failed to open user://maps)")
		load_map_list.set_item_disabled(0, true)
		return

	var files := dir.get_files()
	var json_files: PackedStringArray = PackedStringArray()
	for f in files:
		if String(f).ends_with(".json"):
			json_files.append(f)
	json_files.sort()
	if json_files.is_empty():
		load_map_list.add_item("(no saved maps)")
		load_map_list.set_item_disabled(0, true)
		return

	for f in json_files:
		_load_map_files.append(dir_path.path_join(f))
		load_map_list.add_item(f)

	# Default select newest.
	load_map_list.select(load_map_list.item_count - 1)
	load_map_list.ensure_current_is_visible()


func _on_load_map_item_activated(index: int) -> void:
	_load_selected_map(index)


func _on_load_map_load_pressed() -> void:
	var sel := load_map_list.get_selected_items()
	if sel.is_empty():
		return
	_load_selected_map(sel[0])


func _load_selected_map(index: int) -> void:
	if index < 0 or index >= _load_map_files.size():
		return
	var full_path := _load_map_files[index]
	_load_map_from_path(full_path)
	_hide_load_map_dialog()
	_update_ui()


func _save_map() -> void:
	var dir_path := "user://maps"
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_absolute(dir_path)
	
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var filename := "map_%s.json" % timestamp
	var full_path := dir_path.path_join(filename)

	var json_str := LevelIO.build_map_json_string(_map_width_cells(), _map_height_cells(), _tileset_name, _tilemaps, entities)
	var err := LevelIO.save_map_to_json(full_path, _map_width_cells(), _map_height_cells(), _tileset_name, _tilemaps, entities)
	if err == OK:
		DisplayServer.clipboard_set(json_str)
		print("Map saved: " + full_path)
		print("Map JSON copied to clipboard (", json_str.length(), " chars)")
		if Input.is_action_pressed("drift_modifier_ability"):
			print("----- BEGIN MAP JSON -----")
			print(json_str)
			print("----- END MAP JSON -----")
	else:
		push_error("Failed to save map")


func _load_latest_map() -> void:
	var dir_path := "user://maps"
	if not DirAccess.dir_exists_absolute(dir_path):
		print("No maps to load")
		return

	var dir := DirAccess.open(dir_path)
	if not dir:
		print("Failed to open maps directory")
		return

	var files := dir.get_files()
	var json_files: PackedStringArray = PackedStringArray()
	for f in files:
		if String(f).ends_with(".json"):
			json_files.append(f)
	if json_files.is_empty():
		print("No maps found")
		return

	json_files.sort()
	var latest := json_files[-1]
	_load_map_from_path(dir_path.path_join(latest))


func _load_map_from_path(full_path: String) -> void:
	# _create_new_map() below clears the undo history, and only once the metadata has
	# been accepted -- a failed load leaves the current map and its history intact.
	var meta0 := LevelIO.load_map_meta(full_path)
	if meta0.is_empty():
		push_error("Failed to load map meta: " + full_path)
		return
	var tileset_name: String = String(meta0.get("tileset", "")).strip_edges()
	if tileset_name == "":
		push_error("Map meta.tileset is required (empty): " + full_path)
		return
	_load_tileset_by_name(tileset_name)
	var w_px := int(meta0.get("width", 1024))
	var h_px := int(meta0.get("height", 1024))
	_create_new_map(w_px, h_px)

	var raw := LevelIO.read_map_data(full_path)
	var validated := DriftMap.validate_and_canonicalize(raw)
	if not bool(validated.get("ok", false)):
		push_error("Map validation failed: " + full_path)
		for e in (validated.get("errors", []) as Array):
			push_error(" - " + String(e))
		return
	var canonical: Dictionary = validated.get("map", {})
	entities = canonical.get("entities", [])
	var meta: Dictionary = LevelIO.load_map_from_json(full_path, _tilemaps)
	reroute_tiles_by_meta()
	rebuild_collision_cache()
	if test_mode and _test_puck != null:
		_reset_test_puck()
	if meta.has("w") and meta.has("h"):
		print("Map loaded: " + full_path)
	else:
		push_error("Failed to load map")


func _exit_editor() -> void:
	# Return to FlyableMain or main menu
	get_tree().change_scene_to_file("res://client/FlyableMain.tscn")
