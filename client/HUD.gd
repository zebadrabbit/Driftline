extends CanvasLayer

## Minimal demo HUD using SpriteFontLabel.
## Displays one SubSpace-style HUD line:
##   "PlayerName | Bounty: #### | Stars: # | Ship: X"
##
## Values can be driven by your game code (see client_main.gd snippet below),
## or will animate with simple defaults if nothing sets them.

@export var player_name: String = "Player"
@export var bounty: int = 0
@export var stars: int = 0
@export var ship_id: int = 0

@export var ship_speed: float = 0.0
@export var ship_heading_degrees: float = 0.0
@export var ship_energy_current: int = 0
@export var ship_energy_max: int = 0
@export var ship_energy_recharge_wait_ticks: int = 0

@export var ship_afterburner_on: bool = false
@export var ship_stealth_on: bool = false
@export var ship_cloak_on: bool = false
@export var ship_xradar_on: bool = false
@export var ship_antiwarp_on: bool = false

@export var ship_gun_level: int = 1
@export var ship_bomb_level: int = 1
@export var ship_multi_fire_enabled: bool = false
# Proximity bombs are not yet implemented in the sim; this is UI-forward-compatible.
@export var ship_bomb_proximity_enabled: bool = false

@export var ship_bullet_bounce_bonus: int = 0

@export var ship_tick: int = 0
@export var ship_damage_protect_until_tick: int = 0
@export var ship_dead_until_tick: int = 0

@export var ship_in_safe_zone: bool = false
@export var ship_safe_zone_time_used_ticks: int = 0
@export var ship_safe_zone_time_max_ticks: int = 0

@export var ui_low_energy_frac: float = 0.33
@export var ui_critical_energy_frac: float = 0.15

@export var help_ticker_enabled: bool = true
@export var help_ticker_period_s: float = 6.0
@export var help_ticker_path: String = "res://data/help_ticker.txt"

const SpriteFontLabelScript := preload("res://client/SpriteFontLabel.gd")
const DriftConstants := preload("res://shared/drift_constants.gd")
const MinimapScene := preload("res://client/scenes/Minimap.tscn")
const DriftUiIconAtlas := preload("res://client/ui/ui_icon_atlas.gd")
const ICONS_TEX: Texture2D = preload("res://client/graphics/ui/Icons.png")
const PrizeToastScript := preload("res://client/ui/prize_toast.gd")

@onready var name_bounty = $Root/SpriteFontLabel
@onready var rest_label = $Root/RestLabel
@onready var stats_label = $Root/StatsLabel
@onready var stats_energy_label = $Root/StatsEnergy
@onready var stats_suffix_label = $Root/StatsSuffix
@onready var help_ticker_label = $Root/HelpTicker

@onready var right_gun_label = $Root/RightGun
@onready var right_bomb_label = $Root/RightBomb
@onready var right_weapon_flags_label = $Root/RightWeaponFlags
@onready var right_status_label = $Root/RightStatus

var _last_text: String = ""
var _last_stats_text: String = ""
var _last_stats_energy_text: String = ""
var _last_stats_suffix_text: String = ""
var _ship_hooked: bool = false

var _help_pages: Array = [] # Array[Array[String]]
var _help_page_idx: int = 0
var _help_line_idx: int = 0
var _help_timer_s: float = 0.0
var _last_help_text: String = ""

# Help ticker interrupt (client-only UI).
var _help_interrupt_text: String = ""
var _help_interrupt_remaining_s: float = 0.0
var _help_interrupt_was_active: bool = false

# Prize feedback (client-only UI; tick-based, deterministic).
var _prize_feedback_text: String = ""
var _prize_feedback_until_tick: int = -1
var _prize_feedback_was_active: bool = false
var _prize_feedback_icon_atlas: Vector2i = Vector2i(-1, -1)
var _prize_feedback_icon_rect: TextureRect = null

@export var prize_toast_enabled: bool = false
var _prize_toast = null

var _minimap = null


# --- Pickup feed (screen-space, SubSpace-style) ---
const PICKUP_FEED_MAX_LINES: int = 5
# Deterministic expiry window for pickup feed lines.
const PICKUP_FEED_DURATION_MS: int = 2500
const PICKUP_FEED_DURATION_TICKS: int = int((PICKUP_FEED_DURATION_MS * DriftConstants.TICK_RATE + 999) / 1000)
# Match `res://client/fonts/shrtfont_green.png.import` (image_margin.y=16).
# Small font uses 2 rows per color @ 8px cell height => band height = 16px => 16/16 = 1.
const PICKUP_FEED_COLOR_INDEX_GREEN: int = 1

var _pickup_feed_root: VBoxContainer = null
var _pickup_feed_labels: Array = [] # Array[SpriteFontLabel]
var _pickup_feed_lines: Array = [] # Array[Dictionary] {text:String, until_tick:int}


# --- SubSpace-style edge icon stacks (client-only UI) ---
const EDGE_PEEK_PX: float = 4.0
const EDGE_SLIDE_PX_PER_FRAME: float = 8.0
const EDGE_SLOT_SPACING_PX: float = 3.0

var _edge_root: Control = null
var _left_stack: VBoxContainer = null
var _right_stack: VBoxContainer = null

var _left_counts: Dictionary = {
	&"burst": 0,
	&"repel": 0,
	&"decoy": 0,
	&"thor": 0,
	&"brick": 0,
	&"rocket": 0,
	&"teleport": 0,
}

var _left_slots: Array = [] # Array[Dictionary]
var _right_slots: Array = [] # Array[Dictionary]

var _ui_radar_on: bool = true


func _ready() -> void:
	# Keep HUD in screen-space above gameplay.
	layer = 10
	_minimap = MinimapScene.instantiate()
	add_child(_minimap)
	if name_bounty != null:
		name_bounty.set_font_size(SpriteFontLabelScript.FontSize.SMALL)
		name_bounty.set_color_index(2) # blue
		name_bounty.set_alignment(SpriteFontLabelScript.Align.LEFT)
		name_bounty.letter_spacing_px = 0
	if rest_label != null:
		rest_label.set_font_size(SpriteFontLabelScript.FontSize.SMALL)
		rest_label.set_color_index(0) # white
		rest_label.set_alignment(SpriteFontLabelScript.Align.LEFT)
		rest_label.letter_spacing_px = 0
	if stats_label != null:
		stats_label.set_font_size(SpriteFontLabelScript.FontSize.SMALL)
		stats_label.set_color_index(0) # white
		stats_label.set_alignment(SpriteFontLabelScript.Align.LEFT)
		stats_label.letter_spacing_px = 0
	if stats_energy_label != null:
		stats_energy_label.set_font_size(SpriteFontLabelScript.FontSize.SMALL)
		stats_energy_label.set_color_index(0) # white
		stats_energy_label.set_alignment(SpriteFontLabelScript.Align.LEFT)
		stats_energy_label.letter_spacing_px = 0
	if stats_suffix_label != null:
		stats_suffix_label.set_font_size(SpriteFontLabelScript.FontSize.SMALL)
		stats_suffix_label.set_color_index(0) # white
		stats_suffix_label.set_alignment(SpriteFontLabelScript.Align.LEFT)
		stats_suffix_label.letter_spacing_px = 0
	if help_ticker_label != null:
		help_ticker_label.set_font_size(SpriteFontLabelScript.FontSize.SMALL)
		help_ticker_label.set_color_index(0) # white
		help_ticker_label.set_alignment(SpriteFontLabelScript.Align.LEFT)
		help_ticker_label.letter_spacing_px = 0

	# Transient prize feedback icon (hidden by default). This must not modify
	# persistent HUD layout or left/right stacks.
	_prize_feedback_icon_rect = TextureRect.new()
	_prize_feedback_icon_rect.name = "PrizeFeedbackIcon"
	_prize_feedback_icon_rect.visible = false
	_prize_feedback_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prize_feedback_icon_rect.texture = null
	_prize_feedback_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_prize_feedback_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_prize_feedback_icon_rect.custom_minimum_size = Vector2(DriftUiIconAtlas.TILE_W, DriftUiIconAtlas.TILE_H)
	# Place above the help ticker line to avoid shifting any text.
	if help_ticker_label != null:
		_prize_feedback_icon_rect.position = Vector2(help_ticker_label.position.x, help_ticker_label.position.y - float(DriftUiIconAtlas.TILE_H))
	$Root.add_child(_prize_feedback_icon_rect)

	# PrizeToast (transient, non-stacking). Created at runtime so disabling it is a no-op.
	if prize_toast_enabled:
		_prize_toast = PrizeToastScript.new()
		_prize_toast.name = "PrizeToast"
		_prize_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Default position: center HUD area (top-center-ish), independent of left/right stacks.
		_prize_toast.anchor_left = 0.5
		_prize_toast.anchor_right = 0.5
		_prize_toast.anchor_top = 0.0
		_prize_toast.anchor_bottom = 0.0
		_prize_toast.offset_left = -110
		_prize_toast.offset_top = 52
		_prize_toast.offset_right = 110
		_prize_toast.offset_bottom = 74
		$Root.add_child(_prize_toast)
	if right_gun_label != null:
		right_gun_label.set_font_size(SpriteFontLabelScript.FontSize.SMALL)
		right_gun_label.set_color_index(0)
		right_gun_label.set_alignment(SpriteFontLabelScript.Align.LEFT)
		right_gun_label.letter_spacing_px = 0
	if right_bomb_label != null:
		right_bomb_label.set_font_size(SpriteFontLabelScript.FontSize.SMALL)
		right_bomb_label.set_color_index(0)
		right_bomb_label.set_alignment(SpriteFontLabelScript.Align.LEFT)
		right_bomb_label.letter_spacing_px = 0
	if right_weapon_flags_label != null:
		right_weapon_flags_label.set_font_size(SpriteFontLabelScript.FontSize.SMALL)
		right_weapon_flags_label.set_color_index(0)
		right_weapon_flags_label.set_alignment(SpriteFontLabelScript.Align.LEFT)
		right_weapon_flags_label.letter_spacing_px = 0
	if right_status_label != null:
		right_status_label.set_font_size(SpriteFontLabelScript.FontSize.SMALL)
		right_status_label.set_color_index(0)
		right_status_label.set_alignment(SpriteFontLabelScript.Align.LEFT)
		right_status_label.letter_spacing_px = 0

	# New UX uses icon stacks; hide the old right-side text islands.
	if right_gun_label != null:
		right_gun_label.visible = false
	if right_bomb_label != null:
		right_bomb_label.visible = false
	if right_weapon_flags_label != null:
		right_weapon_flags_label.visible = false
	if right_status_label != null:
		right_status_label.visible = false

	_build_edge_icon_stacks()
	_build_pickup_feed()

	_load_help_pages()
	_refresh_help_ticker(true)
	_apply_ui_settings_from_settings_manager()
	_hook_settings_signals()

	_try_hook_player_ship()


func _hook_settings_signals() -> void:
	if typeof(Settings) == TYPE_NIL or Settings == null:
		return
	if not Settings.setting_changed.is_connected(_on_setting_changed):
		Settings.setting_changed.connect(_on_setting_changed)
	if Settings.has_signal("settings_loaded") and not Settings.settings_loaded.is_connected(_on_settings_loaded):
		Settings.settings_loaded.connect(_on_settings_loaded)


func _on_settings_loaded() -> void:
	_apply_ui_settings_from_settings_manager()


func _on_setting_changed(path: String, value: Variant) -> void:
	if path == "ui.show_minimap":
		_set_minimap_enabled(bool(value))
		return
	if path == "ui.help_ticker_enabled":
		help_ticker_set_enabled(bool(value))
		return


func _apply_ui_settings_from_settings_manager() -> void:
	if typeof(Settings) == TYPE_NIL or Settings == null:
		return
	_set_minimap_enabled(bool(Settings.get_value("ui.show_minimap", true)))
	help_ticker_set_enabled(bool(Settings.get_value("ui.help_ticker_enabled", true)))


func _set_minimap_enabled(enabled: bool) -> void:
	if _minimap == null:
		return
	_ui_radar_on = bool(enabled)
	_minimap.visible = bool(enabled)
	_update_right_stack_visuals()


func set_values(p_name: String, p_bounty: int, p_stars: int, p_ship_id: int) -> void:
	player_name = p_name
	bounty = p_bounty
	stars = p_stars
	ship_id = p_ship_id


func set_ui_thresholds(p_low_energy_frac: float, p_critical_energy_frac: float) -> void:
	ui_low_energy_frac = clampf(float(p_low_energy_frac), 0.0, 1.0)
	ui_critical_energy_frac = clampf(float(p_critical_energy_frac), 0.0, 1.0)
	if ui_critical_energy_frac > ui_low_energy_frac:
		ui_critical_energy_frac = ui_low_energy_frac


func set_ship_stats(
	p_speed: float,
	p_heading_degrees: float,
	p_energy_current: float,
	p_energy_max: float = 0.0,
	p_recharge_wait_ticks: int = 0,
	p_afterburner_on: bool = false,
	p_stealth_on: bool = false,
	p_cloak_on: bool = false,
	p_xradar_on: bool = false,
	p_antiwarp_on: bool = false,
	p_in_safe_zone: bool = false,
	p_safe_zone_used_ticks: int = 0,
	p_safe_zone_max_ticks: int = 0,
	p_tick: int = 0,
	p_damage_protect_until_tick: int = 0,
	p_dead_until_tick: int = 0,
	p_gun_level: int = 1,
	p_bomb_level: int = 1,
	p_multi_fire_enabled: bool = false,
	p_bomb_proximity_enabled: bool = false,
	p_bullet_bounce_bonus: int = 0
) -> void:
	ship_speed = p_speed
	ship_heading_degrees = p_heading_degrees
	ship_energy_current = maxi(0, int(round(p_energy_current)))
	ship_energy_max = maxi(0, int(round(p_energy_max)))
	ship_energy_recharge_wait_ticks = maxi(0, int(p_recharge_wait_ticks))
	ship_afterburner_on = bool(p_afterburner_on)
	ship_stealth_on = bool(p_stealth_on)
	ship_cloak_on = bool(p_cloak_on)
	ship_xradar_on = bool(p_xradar_on)
	ship_antiwarp_on = bool(p_antiwarp_on)
	ship_in_safe_zone = bool(p_in_safe_zone)
	ship_safe_zone_time_used_ticks = maxi(0, int(p_safe_zone_used_ticks))
	ship_safe_zone_time_max_ticks = maxi(0, int(p_safe_zone_max_ticks))
	ship_tick = maxi(0, int(p_tick))
	ship_damage_protect_until_tick = maxi(0, int(p_damage_protect_until_tick))
	ship_dead_until_tick = maxi(0, int(p_dead_until_tick))
	ship_gun_level = clampi(int(p_gun_level), 1, 3)
	ship_bomb_level = clampi(int(p_bomb_level), 1, 3)
	ship_multi_fire_enabled = bool(p_multi_fire_enabled)
	ship_bomb_proximity_enabled = bool(p_bomb_proximity_enabled)
	ship_bullet_bounce_bonus = clampi(int(p_bullet_bounce_bonus), 0, 16)

	_update_right_islands()


func set_prize_feedback(text: String, until_tick: int, icon_atlas_coords: Vector2i = Vector2i(-1, -1)) -> void:
	# Tick-based transient message shown in the help ticker channel.
	# Client-only: callers must derive this from authoritative state/events.
	var t := String(text).strip_edges()
	var ut := int(until_tick)
	var icon := icon_atlas_coords
	if t == "" or ut <= 0:
		_prize_feedback_text = ""
		_prize_feedback_until_tick = -1
		_prize_feedback_icon_atlas = Vector2i(-1, -1)
		return
	_prize_feedback_text = t
	_prize_feedback_until_tick = ut
	_prize_feedback_icon_atlas = icon


func set_prize_toast(prize_type: int, icon_atlas_coords: Vector2i, label: String, until_tick: int) -> void:
	# UI-only; does not mutate sim. Safe to disable by not instantiating PrizeToast.
	if _prize_toast == null:
		return
	var payload := {
		"prize_type": int(prize_type),
		"icon": icon_atlas_coords,
		"label": String(label),
	}
	_prize_toast.call("set_toast", payload, int(ship_tick), int(until_tick))


func set_minimap_static(meta: Dictionary, solid_cells: Array, safe_cells: Array) -> void:
	if _minimap != null and _minimap.has_method("set_static_geometry"):
		_minimap.call("set_static_geometry", meta, solid_cells, safe_cells)


func set_minimap_dynamic(snapshot, local_ship_id: int, my_freq: int, player_world_pos: Vector2, xradar_active: bool) -> void:
	if _minimap != null and _minimap.has_method("set_dynamic_state"):
		_minimap.call("set_dynamic_state", snapshot, local_ship_id, my_freq, player_world_pos, xradar_active)


func _process(delta: float) -> void:
	# Demo animation if nothing external updates bounty.
	# (If your game sets bounty each frame, this is effectively overridden.)
	bounty = max(0, bounty)

	# Preferred: get ship stats via signal; fallback: poll group.
	if not _ship_hooked:
		_try_hook_player_ship()
	else:
		# still allow polling in case something else owns stats
		_poll_player_ship_stats()

	var left := "%s(%d)" % [player_name, bounty]
	var right := " | Stars: %d | Ship: %d" % [stars, ship_id]
	var text := left + right
	if text != _last_text:
		_last_text = text
		if name_bounty != null:
			name_bounty.set_text(left)
		if rest_label != null:
			rest_label.set_text(right)
			# Place the rest directly after the blue segment.
			var spacing_px := 8
			rest_label.position.x = float(name_bounty.get_text_width_px() + spacing_px)

	var energy_frac := 0.0
	if ship_energy_max > 0:
		energy_frac = clampf(float(ship_energy_current) / float(ship_energy_max), 0.0, 1.0)

	var eng_text := "%d" % ship_energy_current
	if ship_energy_max > 0:
		eng_text = "%d/%d" % [ship_energy_current, ship_energy_max]
	var abil: String = ""
	if ship_afterburner_on:
		abil += " AB"
	if ship_stealth_on:
		abil += " ST"
	if ship_cloak_on:
		abil += " CL"
	if ship_xradar_on:
		abil += " XR"
	if ship_antiwarp_on:
		abil += " AW"
	var stats_prefix := "SPD:%3.0f  HDG:%3.0f  ENG:" % [ship_speed, ship_heading_degrees]
	var stats_suffix := "  R:%d%s" % [ship_energy_recharge_wait_ticks, abil]
	# Safe-zone countdown (only when configured).
	if ship_in_safe_zone and ship_safe_zone_time_max_ticks > 0:
		var remaining_ticks: int = maxi(0, ship_safe_zone_time_max_ticks - ship_safe_zone_time_used_ticks)
		var remaining_s: float = float(remaining_ticks) * float(DriftConstants.TICK_DT)
		stats_suffix += "  SZ:%0.1fs" % remaining_s

	# Prefix (always white).
	if stats_prefix != _last_stats_text:
		_last_stats_text = stats_prefix
		if stats_label != null:
			stats_label.set_text(stats_prefix)

	# Energy segment (color changes by thresholds).
	if eng_text != _last_stats_energy_text:
		_last_stats_energy_text = eng_text
		if stats_energy_label != null:
			stats_energy_label.set_text(eng_text)
	if stats_energy_label != null:
		var color_idx := 0
		if ship_energy_max > 0 and energy_frac <= ui_critical_energy_frac:
			color_idx = 3 # red
		elif ship_energy_max > 0 and energy_frac <= ui_low_energy_frac:
			color_idx = 4 # orange
		stats_energy_label.set_color_index(color_idx)

	# Suffix (always white).
	if stats_suffix != _last_stats_suffix_text:
		_last_stats_suffix_text = stats_suffix
		if stats_suffix_label != null:
			stats_suffix_label.set_text(stats_suffix)

	# Position segments.
	if stats_label != null and stats_energy_label != null and stats_suffix_label != null:
		var spacing_px := 0
		stats_energy_label.position.x = float(stats_label.get_text_width_px() + spacing_px)
		stats_suffix_label.position.x = float(stats_label.get_text_width_px() + stats_energy_label.get_text_width_px() + spacing_px)

	# Keep legacy right islands updated (even though hidden) for now.
	_update_right_islands()
	_update_edge_icon_stacks()
	_update_pickup_feed()

	# PrizeToast tick: UI-only; driven by ship_tick provided by owner.
	if _prize_toast != null:
		_prize_toast.call("tick", int(ship_tick))

	# NOTE: Prize pickup UI is no longer routed through the help ticker/messages.
	# (New UX uses near-ship text toast + edge stacks.)
	_prize_feedback_was_active = false

	# Help ticker (client-only UI) with priority interrupt channel.
	var interrupt_active: bool = _help_interrupt_remaining_s > 0.0 and _help_interrupt_text != ""
	if interrupt_active:
		_help_interrupt_remaining_s = maxf(0.0, _help_interrupt_remaining_s - float(delta))
		if help_ticker_label != null:
			# Force-update so the interrupt shows immediately.
			if _last_help_text != _help_interrupt_text:
				_last_help_text = _help_interrupt_text
				help_ticker_label.set_text(_help_interrupt_text)
		# Pause normal rotation while interrupt is active.
		_help_timer_s = 0.0
		_help_interrupt_was_active = true
		return

	# Interrupt ended this frame: resume at the NEXT line.
	if _help_interrupt_was_active:
		_help_interrupt_was_active = false
		_help_interrupt_text = ""
		_help_interrupt_remaining_s = 0.0
		if help_ticker_enabled and _help_pages.size() > 0:
			_advance_help_line()
		_help_timer_s = 0.0
		_refresh_help_ticker(true)
		return

	# Normal help ticker rotation.
	if help_ticker_enabled and _help_pages.size() > 0:
		_help_timer_s += float(delta)
		if _help_timer_s >= help_ticker_period_s:
			_help_timer_s = 0.0
			_advance_help_line()
		_refresh_help_ticker(false)
	else:
		if _last_help_text != "":
			_last_help_text = ""
			if help_ticker_label != null:
				help_ticker_label.set_text("")


func show_help_interrupt(text: String, duration_s: float) -> void:
	# Temporarily replaces the rotating help ticker line.
	# Client-only: callers must be driven by client-observed authoritative state changes.
	var t := String(text).strip_edges()
	var d := float(duration_s)
	if d <= 0.0 or t == "":
		_help_interrupt_text = ""
		_help_interrupt_remaining_s = 0.0
		_help_interrupt_was_active = false
		_refresh_help_ticker(true)
		return
	_help_interrupt_text = t
	_help_interrupt_remaining_s = d
	_help_interrupt_was_active = true
	# Show immediately.
	if help_ticker_label != null:
		_last_help_text = _help_interrupt_text
		help_ticker_label.set_text(_help_interrupt_text)


func set_inventory_counts(counts: Dictionary) -> void:
	# Client-only. Expected keys: burst, repel, decoy, thor, brick, rocket, teleport.
	if typeof(counts) != TYPE_DICTIONARY:
		return
	for k in counts.keys():
		if typeof(k) == TYPE_STRING_NAME:
			_left_counts[k] = maxi(0, int(counts.get(k, 0)))
		elif typeof(k) == TYPE_STRING:
			_left_counts[StringName(String(k))] = maxi(0, int(counts.get(k, 0)))
	_update_left_stack_visuals()


func add_pickup_feed_line(text: String) -> void:
	# Backwards-compatible: add with default duration.
	add_pickup_feed_line_until_tick(text, int(ship_tick) + int(PICKUP_FEED_DURATION_TICKS))


func add_pickup_feed_line_until_tick(text: String, until_tick: int) -> void:
	# Client-only. Screen-space pickup feed (not chat).
	# Tick-based expiry so it is deterministic and replay-safe.
	var t := String(text).strip_edges()
	var ut := int(until_tick)
	if t == "" or ut <= 0:
		return
	_pickup_feed_lines.append({
		"text": t,
		"until_tick": ut,
	})
	# Keep only the most recent N entries.
	while _pickup_feed_lines.size() > PICKUP_FEED_MAX_LINES:
		_pickup_feed_lines.pop_front()
	_update_pickup_feed_labels()


func set_ball_possession(has_ball: bool) -> void:
	# Ball possession icon is not part of the contracted right stack.
	# Keep API for future use without changing the HUD contract.
	pass


func _build_edge_icon_stacks() -> void:
	# Screen-space root that spans the viewport.
	_edge_root = Control.new()
	_edge_root.name = "EdgeStacks"
	_edge_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_root.anchor_left = 0.0
	_edge_root.anchor_top = 0.0
	_edge_root.anchor_right = 1.0
	_edge_root.anchor_bottom = 1.0
	_edge_root.offset_left = 0.0
	_edge_root.offset_top = 0.0
	_edge_root.offset_right = 0.0
	_edge_root.offset_bottom = 0.0
	add_child(_edge_root)

	_left_stack = VBoxContainer.new()
	_left_stack.name = "LeftStack"
	_left_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	_left_stack.add_theme_constant_override("separation", int(EDGE_SLOT_SPACING_PX))
	_edge_root.add_child(_left_stack)

	_right_stack = VBoxContainer.new()
	_right_stack.name = "RightStack"
	_right_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	_right_stack.add_theme_constant_override("separation", int(EDGE_SLOT_SPACING_PX))
	_edge_root.add_child(_right_stack)

	_left_slots.clear()
	_right_slots.clear()

	# Left inventory stack (fixed order; always visible; per-slot slide when inactive).
	var left_order: Array = [&"burst", &"repel", &"decoy", &"thor", &"brick", &"rocket", &"teleport"]
	for item in left_order:
		var slot := _make_icon_slot(true)
		slot["item"] = item
		slot["side"] = int(DriftUiIconAtlas.Side.LEFT)
		_left_stack.add_child(slot["root"])
		_left_slots.append(slot)

	# Right stack order (fixed) per contract.
	var right_order: Array = [&"gun", &"bomb", &"radar", &"stealth", &"xradar", &"antiwarp"]
	for rid in right_order:
		var rslot := _make_icon_slot(false)
		rslot["id"] = rid
		rslot["side"] = int(DriftUiIconAtlas.Side.RIGHT)
		_right_stack.add_child(rslot["root"])
		_right_slots.append(rslot)

	_update_edge_stack_layout()
	_update_left_stack_visuals()
	_update_right_stack_visuals()


func _build_pickup_feed() -> void:
	if _edge_root == null:
		return
	_pickup_feed_root = VBoxContainer.new()
	_pickup_feed_root.name = "PickupFeed"
	_pickup_feed_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pickup_feed_root.add_theme_constant_override("separation", 1)
	_edge_root.add_child(_pickup_feed_root)

	_pickup_feed_labels.clear()
	for i in range(PICKUP_FEED_MAX_LINES):
		var lbl := SpriteFontLabelScript.new()
		lbl.name = "Line%d" % i
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.set_font_size(SpriteFontLabelScript.FontSize.SMALL)
		lbl.set_color_index(PICKUP_FEED_COLOR_INDEX_GREEN)
		lbl.set_alignment(SpriteFontLabelScript.Align.LEFT)
		lbl.letter_spacing_px = 0
		_pickup_feed_root.add_child(lbl)
		_pickup_feed_labels.append(lbl)

	_update_pickup_feed_layout()
	_update_pickup_feed_labels()


func _update_pickup_feed_layout() -> void:
	if _pickup_feed_root == null:
		return
	var vp: Rect2 = get_viewport().get_visible_rect()
	# Anchor left-third, below mid-screen.
	_pickup_feed_root.position = Vector2(vp.size.x * 0.33, vp.size.y * 0.60)


func _update_pickup_feed() -> void:
	if _pickup_feed_root == null:
		return
	_update_pickup_feed_layout()
	# Prune expired entries deterministically by tick.
	var now_tick: int = int(ship_tick)
	var did_prune: bool = false
	for i in range(_pickup_feed_lines.size() - 1, -1, -1):
		var e = _pickup_feed_lines[i]
		if typeof(e) != TYPE_DICTIONARY:
			_pickup_feed_lines.remove_at(i)
			did_prune = true
			continue
		var ut: int = int((e as Dictionary).get("until_tick", -1))
		if ut > 0 and now_tick >= ut:
			_pickup_feed_lines.remove_at(i)
			did_prune = true
	if did_prune:
		_update_pickup_feed_labels()


func _update_pickup_feed_labels() -> void:
	# Oldest at top, newest at bottom.
	for i in range(PICKUP_FEED_MAX_LINES):
		var lbl = _pickup_feed_labels[i] if i < _pickup_feed_labels.size() else null
		if lbl == null:
			continue
		if i < _pickup_feed_lines.size():
			var e = _pickup_feed_lines[i]
			if typeof(e) == TYPE_DICTIONARY:
				lbl.set_text(String((e as Dictionary).get("text", "")))
			else:
				lbl.set_text(String(e))
		else:
			lbl.set_text("")


func _make_icon_slot(with_count: bool) -> Dictionary:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.custom_minimum_size = Vector2(DriftUiIconAtlas.TILE_W, DriftUiIconAtlas.TILE_H)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(DriftUiIconAtlas.TILE_W, DriftUiIconAtlas.TILE_H)
	var at := AtlasTexture.new()
	at.atlas = ICONS_TEX
	at.region = Rect2i(0, 0, DriftUiIconAtlas.TILE_W, DriftUiIconAtlas.TILE_H)
	icon.texture = at
	root.add_child(icon)

	var count_lbl = null
	if with_count:
		count_lbl = SpriteFontLabelScript.new()
		count_lbl.name = "Count"
		count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count_lbl.set_font_size(SpriteFontLabelScript.FontSize.SMALL)
		count_lbl.set_color_index(0) # white
		count_lbl.set_alignment(SpriteFontLabelScript.Align.LEFT)
		count_lbl.letter_spacing_px = 0
		# Overlay near top-left of the icon.
		count_lbl.position = Vector2(2.0, 1.0)
		root.add_child(count_lbl)

	return {
		"root": root,
		"icon": icon,
		"count": count_lbl,
		"slide_x": 0.0,
		"side": int(DriftUiIconAtlas.Side.LEFT),
	}


func _set_slot_icon(icon_rect: TextureRect, atlas_coords: Vector2i) -> void:
	if icon_rect == null:
		return
	var at: AtlasTexture = icon_rect.texture as AtlasTexture
	if at == null:
		at = AtlasTexture.new()
		at.atlas = ICONS_TEX
		icon_rect.texture = at
	if DriftUiIconAtlas.coords_is_renderable(atlas_coords):
		at.region = DriftUiIconAtlas.coords_to_region_rect_px(atlas_coords)
		icon_rect.visible = true
	else:
		icon_rect.visible = false


func _update_edge_stacks_anchor_y(stack: Control, total_h: float) -> void:
	# Center vertically on screen.
	if stack == null:
		return
	var vp: Rect2 = get_viewport().get_visible_rect()
	stack.position.y = (vp.size.y * 0.5) - (total_h * 0.5)


func _update_edge_stack_layout() -> void:
	if _edge_root == null:
		return
	var vp: Rect2 = get_viewport().get_visible_rect()

	# Compute stack heights.
	var left_h: float = float(_left_slots.size()) * float(DriftUiIconAtlas.TILE_H) + maxf(0.0, float(_left_slots.size() - 1)) * float(EDGE_SLOT_SPACING_PX)
	var right_h: float = float(_right_slots.size()) * float(DriftUiIconAtlas.TILE_H) + maxf(0.0, float(_right_slots.size() - 1)) * float(EDGE_SLOT_SPACING_PX)

	_update_edge_stacks_anchor_y(_left_stack, left_h)
	_update_edge_stacks_anchor_y(_right_stack, right_h)

	# Set baseline x positions: anchored to exact edges.
	if _left_stack != null:
		_left_stack.position.x = 0.0
	if _right_stack != null:
		# Right-aligned.
		_right_stack.position.x = vp.size.x - float(DriftUiIconAtlas.TILE_W)


func _update_edge_icon_stacks() -> void:
	if _edge_root == null:
		return
	_update_edge_stack_layout()
	_update_left_stack_visuals()
	_update_right_stack_visuals()


func _step_towards(cur: float, target: float, step: float) -> float:
	if cur < target:
		return minf(target, cur + step)
	if cur > target:
		return maxf(target, cur - step)
	return cur


func _update_left_stack_visuals() -> void:
	if _left_stack == null:
		return
	var off_px: float = -(float(DriftUiIconAtlas.TILE_W) - EDGE_PEEK_PX)
	for s_any in _left_slots:
		if typeof(s_any) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = s_any
		var item: StringName = s.get("item", &"")
		var n: int = int(_left_counts.get(item, 0))
		var atlas: Vector2i = DriftUiIconAtlas.inventory_icon_coords(item)
		_set_slot_icon(s.get("icon"), atlas)
		# Per-slot slide: inactive when count==0.
		var icon_rect: TextureRect = s.get("icon")
		var cur_x: float = float(s.get("slide_x", 0.0))
		var target_x: float = 0.0 if n > 0 else off_px
		cur_x = _step_towards(cur_x, target_x, EDGE_SLIDE_PX_PER_FRAME)
		s["slide_x"] = cur_x
		if icon_rect != null:
			icon_rect.position.x = cur_x
		var c = s.get("count")
		if c != null:
			if n > 0:
				# Single digit display per spec; clamp 0..9.
				var d := clampi(n, 0, 9)
				c.set_text("%d" % d)
			else:
				c.set_text("")


func _update_right_stack_visuals() -> void:
	if _right_stack == null:
		return
	var off_px: float = float(DriftUiIconAtlas.TILE_W) - EDGE_PEEK_PX
	for s_any in _right_slots:
		if typeof(s_any) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = s_any
		var rid: StringName = s.get("id", &"")
		var icon_rect: TextureRect = s.get("icon")
		var show: bool = false
		var atlas: Vector2i = Vector2i(-1, -1)
		match String(rid):
			"gun":
				show = true
				atlas = DriftUiIconAtlas.gun_icon_coords(ship_gun_level, ship_bullet_bounce_bonus > 0, ship_multi_fire_enabled, ship_multi_fire_enabled)
			"bomb":
				show = true
				atlas = DriftUiIconAtlas.bomb_icon_coords(ship_bomb_level, ship_bomb_proximity_enabled, false)
			"radar":
				show = bool(_ui_radar_on)
				atlas = DriftUiIconAtlas.toggle_icon_coords(&"radar", bool(_ui_radar_on))
			"stealth":
				show = bool(ship_stealth_on)
				atlas = DriftUiIconAtlas.toggle_icon_coords(&"stealth", bool(ship_stealth_on))
			"xradar":
				show = bool(ship_xradar_on)
				atlas = DriftUiIconAtlas.toggle_icon_coords(&"xradar", bool(ship_xradar_on))
			"antiwarp":
				show = bool(ship_antiwarp_on)
				atlas = DriftUiIconAtlas.toggle_icon_coords(&"antiwarp", bool(ship_antiwarp_on))
			_:
				show = false
		# Right stack slots are always present; off-state slides mostly off-screen.
		_set_slot_icon(icon_rect, atlas)
		var cur_x: float = float(s.get("slide_x", 0.0))
		var target_x: float = 0.0 if show else off_px
		cur_x = _step_towards(cur_x, target_x, EDGE_SLIDE_PX_PER_FRAME)
		s["slide_x"] = cur_x
		if icon_rect != null:
			icon_rect.position.x = cur_x


func help_ticker_toggle() -> void:
	help_ticker_set_enabled(not help_ticker_enabled)


func help_ticker_set_enabled(enabled: bool) -> void:
	help_ticker_enabled = bool(enabled)
	_help_timer_s = 0.0
	_refresh_help_ticker(true)


func help_ticker_next_page() -> void:
	if _help_pages.size() <= 0:
		return
	_help_page_idx = (_help_page_idx + 1) % _help_pages.size()
	_help_line_idx = 0
	_help_timer_s = 0.0
	_refresh_help_ticker(true)


func _advance_help_line() -> void:
	if _help_pages.size() <= 0:
		return
	var page: Array = _help_pages[_help_page_idx]
	if page.size() <= 0:
		return
	_help_line_idx = (_help_line_idx + 1) % page.size()


func _refresh_help_ticker(force: bool) -> void:
	if help_ticker_label == null:
		return
	var next_text := ""
	if help_ticker_enabled and _help_pages.size() > 0:
		var page: Array = _help_pages[_help_page_idx]
		if page.size() > 0:
			_help_line_idx = clampi(_help_line_idx, 0, page.size() - 1)
			next_text = String(page[_help_line_idx])
	if force or next_text != _last_help_text:
		_last_help_text = next_text
		help_ticker_label.set_text(next_text)


func _load_help_pages() -> void:
	_help_pages.clear()
	_help_page_idx = 0
	_help_line_idx = 0
	_help_timer_s = 0.0

	var raw := ""
	if help_ticker_path != "" and FileAccess.file_exists(help_ticker_path):
		raw = FileAccess.get_file_as_string(help_ticker_path)

	if raw.strip_edges() == "":
		_help_pages = _default_help_pages()
		return

	var cur: Array = []
	for line_raw in raw.split("\n", false):
		var line := String(line_raw).strip_edges()
		if line == "" :
			# Blank line = page break only if we already collected something.
			if cur.size() > 0:
				_help_pages.append(cur)
				cur = []
			continue
		if line.begins_with("#"):
			continue
		if line == "---":
			if cur.size() > 0:
				_help_pages.append(cur)
				cur = []
			continue
		cur.append(line)
	if cur.size() > 0:
		_help_pages.append(cur)

	if _help_pages.size() <= 0:
		_help_pages = _default_help_pages()


func _default_help_pages() -> Array:
	return [
		[
			"Controls: W/S thrust, A/D rotate.",
			"Weapons: Space = primary fire.",
			"Abilities: Shift+Z Stealth, Shift+X Cloak, Shift+C XRadar, Shift+V Antiwarp.",
			"Help: F1 cycles pages. Hold Esc + press F6 toggles the ticker.",
		],
		[
			"Energy: HP and resource share the same bar.",
			"Damage reduces energy; weapons/abilities also consume energy.",
			"Energy recharges after a delay (see R: timer).",
		],
		[
			"Safe Zone: immune to damage while inside.",
			"Safe Zone time can be limited; HUD shows SZ countdown.",
			"Map/Radar: learn the arena lanes, doors, and safe-zone geometry.",
		],
	]


func _try_hook_player_ship() -> void:
	if _ship_hooked:
		return
	var s := get_tree().get_first_node_in_group("player_ship")
	if s == null:
		# Fallback will still poll once it exists.
		_poll_player_ship_stats()
		return
	_poll_player_ship_stats()
	if s.has_signal("stats_changed") and not s.stats_changed.is_connected(_on_ship_stats_changed):
		s.stats_changed.connect(_on_ship_stats_changed)
		_ship_hooked = true


func _on_ship_stats_changed(speed: float, heading_deg: float, energy_value: float) -> void:
	# This signal only provides a subset of ship stats and does not include
	# authoritative tick-based fields (e.g. ship_tick) used for deterministic UI.
	# ClientMain is responsible for calling set_ship_stats(...) with the full
	# snapshot-derived payload each frame.
	ship_speed = float(speed)
	ship_heading_degrees = float(heading_deg)
	ship_energy_current = maxi(0, int(round(float(energy_value))))
	_update_right_islands()


func _poll_player_ship_stats() -> void:
	var s := get_tree().get_first_node_in_group("player_ship")
	if s == null:
		return
	if "current_speed" in s:
		ship_speed = float(s.current_speed)
	if "heading_degrees" in s:
		ship_heading_degrees = float(s.heading_degrees)
	if "energy_current" in s:
		ship_energy_current = maxi(0, int(s.energy_current))
	if "energy_max" in s:
		ship_energy_max = maxi(0, int(s.energy_max))
	if "energy_recharge_wait_ticks" in s:
		ship_energy_recharge_wait_ticks = maxi(0, int(s.energy_recharge_wait_ticks))
	elif "energy" in s:
		# Fallback for older ship nodes.
		ship_energy_current = maxi(0, int(round(float(s.energy))))
	# Note: weapon/status fields are expected to come from snapshots in client_main.gd.
	_update_right_islands()


func _update_right_islands() -> void:
	var root := get_node_or_null("Root") as Control
	if root == null:
		return
	var right_x := float(root.size.x)
	if right_x <= 0.0:
		return

	# --- Weapon levels (colored) + toggles ---
	var gun_level := clampi(int(ship_gun_level), 1, 3)
	var bomb_level := clampi(int(ship_bomb_level), 1, 3)
	var gun_text := "G:L%d" % gun_level
	var bomb_text := "B:L%d" % bomb_level
	var flags: Array[String] = []
	if bool(ship_multi_fire_enabled):
		flags.append("MF")
	if bool(ship_bomb_proximity_enabled):
		flags.append("PROX")
	var flags_text := " ".join(flags)

	var spacing_px := 10.0
	var x := right_x

	if right_weapon_flags_label != null:
		right_weapon_flags_label.set_text(flags_text)
		right_weapon_flags_label.position.y = 0.0
		x -= float(right_weapon_flags_label.get_text_width_px())
		right_weapon_flags_label.position.x = maxf(0.0, x)
		x -= spacing_px

	if right_bomb_label != null:
		right_bomb_label.set_text(bomb_text)
		right_bomb_label.set_color_index(_weapon_level_color_index(bomb_level))
		right_bomb_label.position.y = 0.0
		x -= float(right_bomb_label.get_text_width_px())
		right_bomb_label.position.x = maxf(0.0, x)
		x -= spacing_px

	if right_gun_label != null:
		right_gun_label.set_text(gun_text)
		right_gun_label.set_color_index(_weapon_level_color_index(gun_level))
		right_gun_label.position.y = 0.0
		x -= float(right_gun_label.get_text_width_px())
		right_gun_label.position.x = maxf(0.0, x)

	# --- Status/abilities island ---
	var tokens: Array[String] = []
	# Abilities (toggles)
	if bool(ship_stealth_on):
		tokens.append("ST")
	if bool(ship_cloak_on):
		tokens.append("CL")
	if bool(ship_xradar_on):
		tokens.append("XR")
	if bool(ship_antiwarp_on):
		tokens.append("AW")

	# Status flags
	var dead := int(ship_tick) < int(ship_dead_until_tick)
	var spawn_protect := (not dead) and (int(ship_tick) < int(ship_damage_protect_until_tick))
	var safe := (not dead) and bool(ship_in_safe_zone)
	if safe:
		tokens.append("SAFE")
	if spawn_protect:
		tokens.append("SPAWN")
	if dead:
		tokens.append("DEAD")

	var status_text := " ".join(tokens)
	if right_status_label != null:
		right_status_label.set_text(status_text)
		right_status_label.position.y = 12.0
		right_status_label.position.x = maxf(0.0, right_x - float(right_status_label.get_text_width_px()))


func _weapon_level_color_index(level: int) -> int:
	# Match spec intent using existing sprite-font color indices.
	# L1 = red, L2 = yellow-ish (orange), L3 = blue.
	match int(level):
		1:
			return 3 # red
		2:
			return 4 # orange (closest to yellow)
		3:
			return 2 # light blue
		_:
			return 0
