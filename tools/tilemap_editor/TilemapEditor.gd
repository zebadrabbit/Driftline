## TilemapEditor
##
## Runtime tileset editor tool:
## - Import PNG
## - Zoom + grid + selection
## - Edit per-tile metadata (layer/solid/name/tags)
## - Save/load tileset packages under res://assets/tilesets/<name>/

extends Control

const TilesetIO = preload("res://shared/tileset/tileset_io.gd")
const TilesetData = preload("res://shared/tileset/tileset_data.gd")
const TileInspectorScript = preload("res://tools/tilemap_editor/TileInspector.gd")

@onready var btn_import: Button = %ImportButton
@onready var btn_open: Button = %OpenButton
@onready var btn_save: Button = %SaveButton
@onready var btn_save_as: Button = %SaveAsButton

@onready var tile_size_opt: OptionButton = %TileSizeOption
@onready var zoom_out: Button = %ZoomOutButton
@onready var zoom_in: Button = %ZoomInButton
@onready var zoom_100: Button = %Zoom100Button
@onready var zoom_slider: HSlider = %ZoomSlider
@onready var status_label: Label = %StatusLabel

@onready var scroll: ScrollContainer = %Scroll
@onready var view: Control = %TilemapView
@onready var inspector: TileInspectorScript = %TileInspector

@onready var import_png_dialog: FileDialog = %ImportPngDialog
@onready var open_tileset_dialog: FileDialog = %OpenTilesetDialog
@onready var saveas_dir_dialog: FileDialog = %SaveAsDirDialog

var _data: TilesetData = null
var _selected := Vector2i(-1, -1)
var _selected_valid := false

var _zoom := 1.0
var _dirty := false
var _current_dir: String = "" # res://...


func _ready() -> void:
	tile_size_opt.clear()
	tile_size_opt.add_item("16x16")
	tile_size_opt.selected = 0

	zoom_slider.min_value = 0.25
	zoom_slider.max_value = 8.0
	zoom_slider.step = 0.01
	zoom_slider.value = 1.0

	btn_import.pressed.connect(_on_import_pressed)
	btn_open.pressed.connect(_on_open_pressed)
	btn_save.pressed.connect(_on_save_pressed)
	btn_save_as.pressed.connect(_on_save_as_pressed)

	zoom_out.pressed.connect(func(): _set_zoom(_zoom / 1.25))
	zoom_in.pressed.connect(func(): _set_zoom(_zoom * 1.25))
	zoom_100.pressed.connect(func(): _set_zoom(1.0))
	zoom_slider.value_changed.connect(func(v): _set_zoom(float(v)))

	(view as Node).connect("hover_changed", Callable(self, "_on_hover_changed"))
	(view as Node).connect("selection_changed", Callable(self, "_on_selection_changed"))
	(view as Node).connect("zoom_wheel", Callable(self, "_on_zoom_wheel"))

	inspector.changed.connect(_on_inspector_changed)

	import_png_dialog.file_selected.connect(_on_import_png_selected)
	open_tileset_dialog.dir_selected.connect(_on_open_tileset_dir_selected)
	saveas_dir_dialog.dir_selected.connect(_on_saveas_dir_selected)

	(view as Node).set("scroll", scroll)
	_set_status("Ready. Import a PNG or open an existing tileset.")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("drift_editor_cancel"):
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file("res://client/Main.tscn")


func _set_status(msg: String) -> void:
	status_label.text = msg


func _set_zoom(z: float) -> void:
	_zoom = clampf(z, 0.25, 8.0)
	zoom_slider.set_block_signals(true)
	zoom_slider.value = _zoom
	zoom_slider.set_block_signals(false)
	(view as Node).set("zoom", _zoom)


func _on_zoom_wheel(mult: float) -> void:
	_set_zoom(_zoom * mult)


func _on_import_pressed() -> void:
	import_png_dialog.popup_centered_ratio(0.6)


func _on_open_pressed() -> void:
	open_tileset_dialog.popup_centered_ratio(0.6)


func _on_save_pressed() -> void:
	if _data == null:
		_set_status("Nothing to save")
		return
	if _current_dir.strip_edges() == "":
		_on_save_as_pressed()
		return
	var res := TilesetIO.save_tileset(_current_dir, _data)
	if bool(res.get("ok", false)):
		_dirty = false
		_set_status("Saved: " + _current_dir)
		_refresh_reserved_frames()
	else:
		_set_status("Save failed: " + String(res.get("error", "")))


func _on_save_as_pressed() -> void:
	if _data == null:
		_set_status("Nothing to save")
		return
	saveas_dir_dialog.popup_centered_ratio(0.6)


func _on_import_png_selected(abs_path: String) -> void:
	_data = TilesetIO.new_from_png(abs_path)
	_current_dir = ""
	_dirty = true
	_apply_data_to_view()
	_set_status("Imported PNG. Use Save As to write a tileset package.")


func _on_open_tileset_dir_selected(abs_dir: String) -> void:
	var res_dir := TilesetIO.to_res_path(abs_dir)
	if res_dir == abs_dir:
		_set_status("Open Tileset requires a folder under the project (res://assets/tilesets)")
		return
	var res := TilesetIO.load_tileset(res_dir)
	if not bool(res.get("ok", false)):
		_set_status("Open failed: " + String(res.get("error", "")))
		return
	_data = res.get("data", null)
	_current_dir = res_dir
	_dirty = false
	_apply_data_to_view()
	var warnings: Array = res.get("warnings", [])
	if warnings.size() > 0:
		_set_status("Opened with warnings: " + String(warnings[0]))
	else:
		_set_status("Opened: " + res_dir)


func _on_saveas_dir_selected(abs_dir: String) -> void:
	var base := TilesetIO.to_res_path(abs_dir)
	if base == abs_dir:
		_set_status("Save As requires a folder under the project (res://)")
		return

	# If they picked res://assets/tilesets, create/target a child folder by name.
	var target := base
	if base.replace("\\", "/").trim_suffix("/") == TilesetIO.ASSETS_TILESETS_DIR:
		target = base + "/" + _data.name

	_current_dir = target
	_on_save_pressed()


func _apply_data_to_view() -> void:
	if _data == null:
		(view as Node).set("texture", null)
		(view as Node).call("set_purpose_tiles", {})
		return

	(view as Node).set("texture", _data.texture)
	(view as Node).set("tile_size", _data.tile_size)
	_set_zoom(_zoom) # forces view update

	# Inspector
	inspector.set_tileset_data(_data)
	inspector.set_selected_tile(_selected.x, _selected.y, _selected_valid)

	_refresh_reserved_frames()
	_refresh_purpose_overlays()
	_validate_image()
	_validate_defs_bounds()
	if _data.warnings.size() > 0:
		_set_status("Warning: " + String(_data.warnings[0]))


func _refresh_reserved_frames() -> void:
	if _data == null:
		(view as Node).call("set_reserved_frames", PackedStringArray())
		return
	(view as Node).call("set_reserved_frames", _data.get_reserved_door_frames())


func _refresh_purpose_overlays() -> void:
	if _data == null or _data.texture == null:
		(view as Node).call("set_purpose_tiles", {})
		return

	var defaults: Dictionary = _data.get_defaults()
	var default_layer := String(defaults.get("layer", "mid"))
	var default_solid := bool(defaults.get("solid", false))

	var img_size: Vector2 = _data.texture.get_size()
	var cols := maxi(1, int(floor(img_size.x / float(_data.tile_size.x))))
	var rows := maxi(1, int(floor(img_size.y / float(_data.tile_size.y))))
	var purpose: Dictionary = {}

	for y in range(rows):
		for x in range(cols):
			# Keep the atlas readable: only outline tiles with explicit metadata entries.
			# (If defaults say solid=true, outlining all tiles would be overwhelming.)
			if not _data.has_override(x, y):
				continue

			var eff: Dictionary = _data.get_tile_effective(x, y)
			var is_solid := bool(eff.get("solid", false))
			var layer := String(eff.get("layer", "mid"))
			var has_name := String(eff.get("name", "")).strip_edges() != ""
			var has_tags := false
			if eff.has("tags"):
				if eff["tags"] is Array:
					has_tags = (eff["tags"] as Array).size() > 0
				else:
					has_tags = String(eff["tags"]).strip_edges() != ""

			# Only outline if it differs from defaults or carries extra semantics.
			# (But still show *something* for explicit entries like {"door": true}.)
			var differs := (is_solid != default_solid) or (layer != default_layer) or has_name or has_tags
			if differs or eff.size() > 0:
				purpose[_data.get_tile_key(x, y)] = {
					"solid": is_solid,
					"layer": layer,
					"tagged": (has_name or has_tags),
				}

	(view as Node).call("set_purpose_tiles", purpose)


func _validate_image() -> void:
	if _data == null or _data.texture == null:
		return
	var sz := _data.texture.get_size()
	if int(sz.x) % _data.tile_size.x != 0 or int(sz.y) % _data.tile_size.y != 0:
		_set_status("Warning: image size not divisible by tile_size; bounds will be clamped")


func _validate_defs_bounds() -> void:
	if _data == null or _data.texture == null:
		return
	var sz := _data.texture.get_size()
	var cols := maxi(1, int(floor(sz.x / float(_data.tile_size.x))))
	var rows := maxi(1, int(floor(sz.y / float(_data.tile_size.y))))
	var tiles: Dictionary = _data.defs_raw.get("tiles", {})
	var bad := 0
	for k in tiles.keys():
		var parts := String(k).split(",")
		if parts.size() != 2:
			continue
		var x := int(parts[0])
		var y := int(parts[1])
		if x < 0 or y < 0 or x >= cols or y >= rows:
			bad += 1
	if bad > 0:
		_set_status("Warning: defs contain %d out-of-bounds entries" % bad)


func _on_hover_changed(_x: int, _y: int, _valid: bool) -> void:
	# Hover is non-committing; view draws the hover overlay.
	pass


func _on_selection_changed(x: int, y: int, valid: bool) -> void:
	_selected = Vector2i(x, y)
	_selected_valid = valid
	inspector.set_selected_tile(x, y, valid)


func _on_inspector_changed() -> void:
	_dirty = true
	_set_status("Modified (not saved)")
	_refresh_reserved_frames()
	_refresh_purpose_overlays()
