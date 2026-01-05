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

var _minimap = null


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

	_load_help_pages()
	_refresh_help_ticker(true)

	_try_hook_player_ship()


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
	p_bomb_proximity_enabled: bool = false
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

	_update_right_islands()


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

	_update_right_islands()

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
	set_ship_stats(speed, heading_deg, energy_value)


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
