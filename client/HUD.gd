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
@export_range(0.0, 100.0, 0.1) var ship_energy: float = 100.0

const SpriteFontLabelScript := preload("res://client/SpriteFontLabel.gd")

@onready var name_bounty = $Root/SpriteFontLabel
@onready var rest_label = $Root/RestLabel
@onready var stats_label = $Root/StatsLabel

var _last_text: String = ""
var _last_stats_text: String = ""
var _ship_hooked: bool = false


func _ready() -> void:
	# Keep HUD in screen-space above gameplay.
	layer = 10
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

	_try_hook_player_ship()


func set_values(p_name: String, p_bounty: int, p_stars: int, p_ship_id: int) -> void:
	player_name = p_name
	bounty = p_bounty
	stars = p_stars
	ship_id = p_ship_id


func set_ship_stats(p_speed: float, p_heading_degrees: float, p_energy: float) -> void:
	ship_speed = p_speed
	ship_heading_degrees = p_heading_degrees
	ship_energy = clampf(p_energy, 0.0, 100.0)


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

	var stats_text := "SPD:%3.0f  HDG:%3.0f  ENG:%3.0f" % [ship_speed, ship_heading_degrees, ship_energy]
	if stats_text != _last_stats_text:
		_last_stats_text = stats_text
		if stats_label != null:
			stats_label.set_text(stats_text)


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
	if "energy" in s:
		ship_energy = clampf(float(s.energy), 0.0, 100.0)
