extends CharacterBody2D

const SpriteFontLabelScript = preload("res://client/SpriteFontLabel.gd")
const DriftConstants = preload("res://shared/drift_constants.gd")

## Placeholder SubSpace-like ship movement.
## - Top-down 2D, inertial (velocity persists)
## - Rotation is independent from velocity direction (you can drift)
## - Thrust accelerates in ship-forward direction
## - Soft max speed (extra drag above cap)
## - Optional dampening toggle (extra drag) to reduce drift
##
## HUD integration:
## - Exposes vars: current_speed, heading_degrees, energy
## - Emits stats_changed(speed, heading_degrees, energy)
## - Adds itself to group "player_ship" for loose lookup

signal stats_changed(current_speed: float, heading_degrees: float, energy: float)

# --- General ---
@export var online_mode := false

# --- Tunables (feel > realism) ---
@export var turn_rate_rad_s: float = 3.5

# Base thrust acceleration (px/s^2).
@export var thrust_accel: float = 520.0

# While holding Shift: multiply thrust (also drains energy faster).
@export var afterburner_multiplier: float = 1.6

# Reverse thrust acceleration (px/s^2). Unboosted by afterburner.
@export var reverse_thrust_accel: float = 400.0

# Baseline drag (always on). Units: 1/s
@export var base_drag: float = 0.35

# Extra drag when dampening is enabled. Units: 1/s
@export var dampening_extra_drag: float = 2.3

# Soft speed cap (px/s). No hard clamp.
@export var max_speed_soft: float = 720.0

# Additional drag that ramps with overspeed.
@export var overspeed_drag: float = 2.0

# Energy system (0..100).
@export_range(0.0, 100.0, 0.1) var energy: float = 100.0
@export var energy_regen_per_s: float = 18.0
@export var energy_afterburner_drain_per_s: float = 30.0

# Wall bounce physics.
@export_range(0.0, 1.0, 0.01) var restitution: float = 0.75  # Bounce damping (1.0=no loss, 0.0=full damp)
@export var bounce_sound_min_speed: float = 150.0  # Min speed to trigger bounce sound
@export var bounce_sound_cooldown: float = 0.1  # Seconds between bounce sounds

# Toggle key for dampening.
@export var dampening_toggle_action: StringName = &"toggle_dampening"

# Input actions.
@export var thrust_action: StringName = &"thrust"
@export var reverse_thrust_action: StringName = &"brake"  # Still mapped to "brake" key
@export var turn_left_action: StringName = &"turn_left"
@export var turn_right_action: StringName = &"turn_right"
@export var afterburner_action: StringName = &"afterburner"

# --- State exposed to HUD ---
var current_speed: float = 0.0
var heading_degrees: float = 0.0

# Internal state
var _dampening_enabled: bool = false
var _last_emit_speed: float = -1.0
var _last_emit_heading: float = -9999.0
var _last_emit_energy: float = -1.0
var _last_bounce_time: float = -999.0  # Cooldown for bounce sound spam prevention


@onready var _bounce_audio: AudioStreamPlayer = $BounceAudio


func _ready() -> void:
	add_to_group("player_ship")
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(dampening_toggle_action):
		_dampening_enabled = not _dampening_enabled

func simulate_offline(delta: float) -> void:

	if online_mode:
		push_error("ONLINE MODE SHOULD NEVER CALL move_and_collide()")
		return

	var collision := move_and_collide(velocity * delta)

func _physics_process(delta: float) -> void:
	if online_mode:
		queue_redraw()
		return

	# TEMPORARY: offline disabled
	queue_redraw()

func _play_bounce_sound(impact_speed: float) -> void:
	# Play bounce sound with subtle volume/pitch scaling by impact speed.
	if not _bounce_audio or not _bounce_audio.stream:
		return
	
	# Scale volume by impact speed (subtle: map 150-800 px/s to -6..0 dB)
	var speed_norm := clampf((impact_speed - bounce_sound_min_speed) / 650.0, 0.0, 1.0)
	var volume_db := lerpf(-6.0, 0.0, speed_norm)
	_bounce_audio.volume_db = volume_db
	
	# Subtle pitch variation (0.95 - 1.05 range)
	var pitch := lerpf(0.95, 1.05, speed_norm)
	_bounce_audio.pitch_scale = pitch
	
	_bounce_audio.play()


func _emit_stats_if_changed() -> void:
	if absf(current_speed - _last_emit_speed) > 0.5 or absf(heading_degrees - _last_emit_heading) > 0.25 or absf(energy - _last_emit_energy) > 0.25:
		_last_emit_speed = current_speed
		_last_emit_heading = heading_degrees
		_last_emit_energy = energy
		emit_signal("stats_changed", current_speed, heading_degrees, energy)


func _draw() -> void:
	# Simple triangle ship pointing forward (Vector2.RIGHT).
	var tip := Vector2(14, 0)
	var left := Vector2(-10, -8)
	var right := Vector2(-10, 8)
	var pts: PackedVector2Array = PackedVector2Array([tip, right, left])
	var fill := Color(0.9, 0.9, 1.0, 0.9)
	var outline := Color(0.2, 0.6, 1.0, 1.0)
	draw_colored_polygon(pts, fill)
	draw_polyline(PackedVector2Array([tip, right, left, tip]), outline, 2.0)

	# ⚠️ ALWAYS VISIBLE: Ship-attached player name and bounty tag (blue sprite font)
	# This element must never be hidden or removed.
	# Draw at fixed world-space offset (lower-right), not rotating with ship.
	var world_offset := Vector2(24, 16)  # Fixed offset in world space
	var local_offset := world_offset.rotated(-rotation)  # Transform to local (rotated) space
	var bounty := 0  # TODO: wire to actual bounty system when available
	var player_name := "Player"  # TODO: get from username system when available
	var label := "%s(%d)" % [player_name, bounty]
	
	draw_set_transform(local_offset, -rotation, Vector2.ONE)
	SpriteFontLabelScript.draw_text(self, Vector2.ZERO, label, SpriteFontLabelScript.FontSize.SMALL, 2, 0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Velocity debug line (drift direction)
	if velocity.length() > 0.1:
		draw_line(Vector2.ZERO, velocity * 0.05, Color(1.0, 0.3, 0.3, 0.9), 2.0)

func apply_server_snapshot(pos: Vector2, vel: Vector2, rot: float) -> void:
	global_position = pos
	velocity = vel
	rotation = rot
