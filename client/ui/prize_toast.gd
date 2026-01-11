## PrizeToast: transient, UI-only prize feedback component.
##
## Properties:
## - Shows at most one prize at a time (replace, no queue).
## - Auto-expires based on tick inputs (replay-safe when driven by deterministic ticks).
## - Does not read or write simulation state.
## - Safe to disable (owning HUD can simply not instantiate it).
##
## Input payload conceptually: { prize_type, icon, label }

class_name PrizeToast
extends Control

const SpriteFontLabelScript := preload("res://client/SpriteFontLabel.gd")
const DriftUiIconAtlas := preload("res://client/ui/ui_icon_atlas.gd")
const ICONS_TEX: Texture2D = preload("res://client/graphics/ui/Icons.png")

var _active: bool = false
var _until_tick: int = -1
var _prize_type: int = -1
var _label: String = ""
var _icon_atlas: Vector2i = Vector2i(-1, -1)

var _bg: ColorRect = null
var _icon: TextureRect = null
var _text: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	# Small, lightweight toast with subtle translucent backdrop.
	_bg = ColorRect.new()
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.color = Color(0, 0, 0, 0.45)
	_bg.size = Vector2(220, 22)
	add_child(_bg)

	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.position = Vector2(2, 0)
	_icon.size = Vector2(DriftUiIconAtlas.TILE_W, DriftUiIconAtlas.TILE_H)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.visible = false
	add_child(_icon)

	_text = SpriteFontLabelScript.new()
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.position = Vector2(2 + DriftUiIconAtlas.TILE_W + 6, 2)
	_text.set_font_size(SpriteFontLabelScript.FontSize.SMALL)
	_text.set_color_index(0)
	_text.set_alignment(SpriteFontLabelScript.Align.LEFT)
	_text.letter_spacing_px = 0
	add_child(_text)

	_apply_state(0)


func set_toast(payload: Dictionary, now_tick: int, until_tick: int) -> void:
	# Payload: { prize_type:int, icon:Vector2i (atlas coords), label:String }
	var pt: int = int(payload.get("prize_type", -1))
	var label: String = String(payload.get("label", "")).strip_edges()
	var icon: Vector2i = payload.get("icon", Vector2i(-1, -1))
	set_toast_parts(pt, icon, label, now_tick, until_tick)


func set_toast_parts(prize_type: int, icon_atlas_coords: Vector2i, label: String, now_tick: int, until_tick: int) -> void:
	_prize_type = int(prize_type)
	_icon_atlas = icon_atlas_coords
	_label = String(label).strip_edges()
	_until_tick = int(until_tick)
	_apply_state(int(now_tick))


func clear() -> void:
	_active = false
	_until_tick = -1
	_prize_type = -1
	_label = ""
	_icon_atlas = Vector2i(-1, -1)
	_apply_state(0)


func _apply_state(now_tick: int) -> void:
	_active = _label != "" and _until_tick > 0 and int(now_tick) >= 0 and int(now_tick) < _until_tick
	visible = _active
	if not _active:
		if _icon != null:
			_icon.visible = false
			_icon.texture = null
		if _text != null:
			_text.set_text("")
		return

	# Text.
	if _text != null:
		_text.set_text(_label)

	# Icon (optional).
	if _icon != null:
		var show_icon: bool = DriftUiIconAtlas.coords_is_renderable(_icon_atlas)
		_icon.visible = show_icon
		if show_icon:
			var at := AtlasTexture.new()
			at.atlas = ICONS_TEX
			at.region = DriftUiIconAtlas.coords_to_region_rect_px(_icon_atlas)
			_icon.texture = at

	# Resize background to content width (cheap approximation).
	if _bg != null and _text != null:
		var text_w: float = float(_text.get_text_width_px())
		_bg.size.x = clampf(2 + DriftUiIconAtlas.TILE_W + 6 + text_w + 8, 120.0, 420.0)


func tick(now_tick: int) -> void:
	# Call each frame/tick from owner; does not read simulation.
	_apply_state(int(now_tick))
