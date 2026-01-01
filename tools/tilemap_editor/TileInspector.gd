## TileInspector
##
## Right-side inspector UI for a single tile.
## Keeps UI state separate from storage (TilesetData).

extends VBoxContainer

const TilesetData = preload("res://shared/tileset/tileset_data.gd")

signal changed

@onready var preview: TextureRect = %Preview
@onready var label_atlas: Label = %AtlasLabel
@onready var label_key: Label = %KeyLabel
@onready var label_rect: Label = %RectLabel
@onready var label_effective: Label = %EffectiveLabel

@onready var layer_opt: OptionButton = %LayerOption
@onready var solid_chk: CheckBox = %SolidCheck
@onready var name_edit: LineEdit = %NameEdit
@onready var tags_edit: LineEdit = %TagsEdit

@onready var apply_btn: Button = %ApplyButton
@onready var revert_btn: Button = %RevertButton
@onready var copy_btn: Button = %CopyButton
@onready var paste_btn: Button = %PasteButton
@onready var reserved_label: Label = %ReservedLabel

var _data: TilesetData = null
var _x := -1
var _y := -1
var _valid := false
var _reserved := false


func set_tileset_data(d: TilesetData) -> void:
	_data = d
	_refresh_reserved()
	_update_ui_from_data()


func set_selected_tile(x: int, y: int, valid: bool) -> void:
	_x = x
	_y = y
	_valid = valid
	_refresh_reserved()
	_update_ui_from_data()


func _ready() -> void:
	layer_opt.clear()
	for l in ["bg", "mid", "fg"]:
		layer_opt.add_item(l)

	apply_btn.pressed.connect(_on_apply)
	revert_btn.pressed.connect(_on_revert)
	copy_btn.pressed.connect(_on_copy)
	paste_btn.pressed.connect(_on_paste)


func _refresh_reserved() -> void:
	_reserved = false
	if _data == null or not _valid:
		reserved_label.visible = false
		return
	var key := _data.get_tile_key(_x, _y)
	_reserved = _data.get_reserved_door_frames().has(key)
	reserved_label.visible = _reserved
	reserved_label.text = "Reserved (doors): " + key if _reserved else ""


func _update_ui_from_data() -> void:
	var enabled := (_data != null and _valid)
	apply_btn.disabled = not enabled or _reserved
	revert_btn.disabled = not enabled or _reserved
	copy_btn.disabled = not enabled
	paste_btn.disabled = not enabled or _reserved
	layer_opt.disabled = not enabled or _reserved
	solid_chk.disabled = not enabled or _reserved
	name_edit.editable = enabled and not _reserved
	tags_edit.editable = enabled and not _reserved

	if _data == null or not _valid:
		preview.texture = null
		label_atlas.text = "atlas: -"
		label_key.text = "key: -"
		label_rect.text = "rect: -"
		label_effective.text = "effective: -"
		layer_opt.select(1)
		solid_chk.button_pressed = false
		name_edit.text = ""
		tags_edit.text = ""
		return

	label_atlas.text = "atlas: %d,%d" % [_x, _y]
	label_key.text = "key: \"%s\"" % _data.get_tile_key(_x, _y)
	var px := _x * _data.tile_size.x
	var py := _y * _data.tile_size.y
	label_rect.text = "rect: (%d,%d) %dx%d" % [px, py, _data.tile_size.x, _data.tile_size.y]

	# Preview
	if _data.texture != null:
		var at := AtlasTexture.new()
		at.atlas = _data.texture
		at.region = Rect2(px, py, _data.tile_size.x, _data.tile_size.y)
		preview.texture = at
	else:
		preview.texture = null

	var eff := _data.get_tile_effective(_x, _y)
	label_effective.text = "effective: " + JSON.stringify(eff)

	# Populate editable fields from effective (so Apply is explicit).
	var layer := String(eff.get("layer", "mid"))
	var idx := _find_option_text(layer_opt, layer)
	if idx < 0:
		idx = _find_option_text(layer_opt, "mid")
	if idx < 0:
		idx = 0
	layer_opt.select(idx)
	solid_chk.button_pressed = bool(eff.get("solid", false))
	name_edit.text = String(eff.get("name", ""))
	if eff.has("tags") and eff["tags"] is Array:
		tags_edit.text = ",".join((eff["tags"] as Array).map(func(t): return String(t)))
	else:
		tags_edit.text = String(eff.get("tags", ""))


func _on_apply() -> void:
	if _data == null or not _valid or _reserved:
		return
	var patch: Dictionary = {}
	patch["layer"] = layer_opt.get_item_text(layer_opt.selected)
	patch["solid"] = solid_chk.button_pressed
	if name_edit.text.strip_edges() != "":
		patch["name"] = name_edit.text.strip_edges()
	if tags_edit.text.strip_edges() != "":
		patch["tags"] = tags_edit.text.strip_edges()
	_data.set_tile_override(_x, _y, patch)
	emit_signal("changed")
	_update_ui_from_data()


func _on_revert() -> void:
	if _data == null or not _valid or _reserved:
		return
	_data.clear_tile_override(_x, _y)
	emit_signal("changed")
	_update_ui_from_data()


func _on_copy() -> void:
	if _data == null or not _valid:
		return
	var eff := _data.get_tile_effective(_x, _y)
	DisplayServer.clipboard_set(JSON.stringify(eff))


func _on_paste() -> void:
	if _data == null or not _valid or _reserved:
		return
	var s := DisplayServer.clipboard_get()
	var parsed = JSON.parse_string(s)
	if parsed == null or not (parsed is Dictionary):
		return
	var d: Dictionary = parsed
	if d.has("layer"):
		var layer := String(d["layer"])
		var idx := _find_option_text(layer_opt, layer)
		if idx >= 0:
			layer_opt.select(idx)
	if d.has("solid"):
		solid_chk.button_pressed = bool(d["solid"])
	name_edit.text = String(d.get("name", name_edit.text))
	if d.has("tags"):
		if d["tags"] is Array:
			tags_edit.text = ",".join((d["tags"] as Array).map(func(t): return String(t)))
		else:
			tags_edit.text = String(d["tags"])


func _find_option_text(opt: OptionButton, text: String) -> int:
	for i in range(opt.item_count):
		if opt.get_item_text(i) == text:
			return i
	return -1
