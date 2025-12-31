extends Control

## EnergyBarWidget
##
## Renders a SubSpace-style energy bar:
## - Frame (static texture)
## - Fill (cropped horizontally left->right)
## - Optional low-energy pulse
## - Numeric readout 0..100
##
## Clipping approach:
## We avoid stretching/cropping quirks by doing BOTH:
## - Shrink the Fill TextureRect's width in UI pixels
## - Enable region_enabled and shrink region_rect.size.x in texture pixels
## This preserves aspect/pixels when the fill texture matches the bar size.

@export var frame_texture: Texture2D
@export var fill_texture: Texture2D

@export var min_energy: float = 0.0
@export var max_energy: float = 100.0

@export var smoothing_speed: float = 12.0 # higher = snappier
@export var low_energy_threshold: float = 20.0
@export var low_energy_pulse_hz: float = 2.0
@export var low_energy_min_alpha: float = 0.55

# If true, will try to connect to player ship stats_changed; otherwise it only uses set_energy().
@export var auto_bind_to_ship: bool = true

var target_energy: float = 100.0
var display_energy: float = 100.0

@onready var bar_area: Control = $BarArea
@onready var frame_rect: TextureRect = $BarArea/Frame
@onready var fill_rect: TextureRect = $BarArea/Fill
@onready var value_label: Label = $ValueLabel

var _ship_hooked: bool = false
var _pulse_t: float = 0.0


func _ready() -> void:
	# For demo/testing, start at 75% energy.
	# NOTE: If `auto_bind_to_ship` is true and a ship exists, the ship will override this.
	set_energy(75.0)

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if frame_rect != null:
		frame_rect.texture = frame_texture
	if fill_rect != null:
		fill_rect.texture = fill_texture
		fill_rect.region_enabled = true
		fill_rect.region_rect = Rect2(0, 0, 0, 0)

	# Initialize visuals immediately at the current target.
	display_energy = target_energy
	_update_visuals(0.0)
	if auto_bind_to_ship:
		_try_hook_player_ship()


func set_energy(value: float) -> void:
	target_energy = clampf(value, min_energy, max_energy)


func _process(delta: float) -> void:
	if auto_bind_to_ship and not _ship_hooked:
		_try_hook_player_ship()

	# Smooth display value toward target (frame-rate stable lerp)
	var t := 1.0 - exp(-smoothing_speed * delta)
	display_energy = lerpf(display_energy, target_energy, t)

	_update_visuals(delta)


func _update_visuals(delta: float) -> void:
	var denom := maxf(1e-6, max_energy - min_energy)
	var pct := clampf((display_energy - min_energy) / denom, 0.0, 1.0)

	# Pixel-snapped width for better "pixel perfect" feel.
	var full_w := int(floor(bar_area.size.x))
	var full_h := int(floor(bar_area.size.y))
	var fill_w := int(floor(full_w * pct))
	fill_w = clampi(fill_w, 0, full_w)

	if fill_rect != null:
		# UI-space crop
		fill_rect.position = Vector2(0, 0)
		fill_rect.size = Vector2(fill_w, full_h)

		# Texture-space crop (region) to avoid stretching the first pixels across the whole rect.
		if fill_rect.texture != null:
			var tw := fill_rect.texture.get_width()
			var th := fill_rect.texture.get_height()
			var region_w := int(floor(float(tw) * pct))
			region_w = clampi(region_w, 0, tw)
			fill_rect.region_rect = Rect2(0, 0, region_w, th)

		# Low-energy feedback: subtle pulse in alpha.
		if display_energy <= low_energy_threshold:
			_pulse_t += delta
			var s := 0.5 + 0.5 * sin(_pulse_t * TAU * low_energy_pulse_hz)
			fill_rect.modulate.a = lerpf(low_energy_min_alpha, 1.0, s)
		else:
			_pulse_t = 0.0
			fill_rect.modulate.a = 1.0

	if value_label != null:
		value_label.text = "%d" % int(round(display_energy))


func _try_hook_player_ship() -> void:
	if _ship_hooked:
		return
	var ship := get_tree().get_first_node_in_group("player_ship")
	if ship == null:
		return

	# Initialize immediately via polling.
	if "energy" in ship:
		set_energy(float(ship.energy))
		display_energy = target_energy

	# Preferred: connect signal if available.
	if ship.has_signal("stats_changed") and not ship.stats_changed.is_connected(_on_ship_stats_changed):
		ship.stats_changed.connect(_on_ship_stats_changed)
		_ship_hooked = true


func _on_ship_stats_changed(_speed: float, _heading_deg: float, energy: float) -> void:
	set_energy(energy)
