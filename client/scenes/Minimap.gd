extends Control

## SubSpace-style minimap (client-only UI).
## Owns sizing, labels, and state plumbing; rendering is delegated to MinimapView.

const DriftConstants := preload("res://shared/drift_constants.gd")
const DriftCoordFormat := preload("res://client/scripts/ui/coord_format.gd")

const SMALL_SIDE_PX: int = 160
const LARGE_MULT: int = 2
const MARGIN_PX: int = 24

@onready var _time_label: Label = $VBox/TimeLabel
@onready var _coord_label: Label = $VBox/CoordLabel
@onready var _view: Control = $VBox/MinimapView

var _is_large: bool = false
var _radar_enabled: bool = true

var _last_time_s: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_apply_size()


func set_large(v: bool) -> void:
	_is_large = bool(v)
	_apply_size()


func toggle_size() -> void:
	set_large(not _is_large)


func set_radar_enabled(v: bool) -> void:
	_radar_enabled = bool(v)


func set_static_geometry(meta: Dictionary, solid_cells: Array, safe_cells: Array) -> void:
	if _view != null and _view.has_method("set_static_geometry"):
		_view.call("set_static_geometry", meta, solid_cells, safe_cells)


func set_dynamic_state(snapshot, local_ship_id: int, my_freq: int, player_world_pos: Vector2, xradar_active: bool) -> void:
	# Coordinates label is intentionally separate from minimap rendering.
	if _coord_label != null:
		var sector := DriftCoordFormat.sector_label(player_world_pos, DriftConstants.ARENA_MIN, DriftConstants.ARENA_MAX)
		_coord_label.text = "Pos: %s" % sector

	if _view != null and _view.has_method("set_dynamic_state"):
		_view.call("set_dynamic_state", snapshot, local_ship_id, my_freq, player_world_pos, _radar_enabled, bool(xradar_active))


func _process(_delta: float) -> void:
	if _time_label != null:
		var now_s: int = int(Time.get_ticks_msec() / 1000)
		if now_s != _last_time_s:
			_last_time_s = now_s
			var t := Time.get_time_dict_from_system()
			var hh: int = int(t.get("hour", 0))
			var mm: int = int(t.get("minute", 0))
			_time_label.text = "Time: %02d:%02d" % [hh, mm]


func _apply_size() -> void:
	var side: int = SMALL_SIDE_PX * (LARGE_MULT if _is_large else 1)
	if _view != null:
		_view.custom_minimum_size = Vector2(side, side)

	# Root size accounts for 2 text lines above the map.
	# Use actual label minimum sizes to avoid VBox overflow off-screen.
	var header_h: float = 0.0
	if _time_label != null:
		header_h += _time_label.get_combined_minimum_size().y
	if _coord_label != null:
		header_h += _coord_label.get_combined_minimum_size().y
	header_h += 8.0
	custom_minimum_size = Vector2(side, side + header_h)
	offset_right = -float(MARGIN_PX)
	offset_bottom = -float(MARGIN_PX)
	offset_left = -float(MARGIN_PX + side)
	offset_top = -float(MARGIN_PX + side + header_h)
