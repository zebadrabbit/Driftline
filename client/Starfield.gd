extends Node2D

func _init():
	z_index = -1000

# Parallax starfield with deterministic layers
const LAYER_CONFIG = [
	{ "count": 300, "parallax": 0.15 },
	{ "count": 200, "parallax": 0.35 },
	{ "count": 120, "parallax": 0.60 },
]
const STARFIELD_AREA_SCALE = 2.0 # Multiplier for arena size
const STAR_SEED = 13371337

var layers = [] # Array of Array[star]
var arena_min := Vector2.ZERO
var arena_max := Vector2(2048, 1152)

func _ready():
	arena_min = get_arena_min()
	arena_max = get_arena_max()
	var arena_size = arena_max - arena_min
	var field_min = arena_min - arena_size * 0.5
	var field_max = arena_max + arena_size * 0.5
	var field_size = field_max - field_min

	var rng = RandomNumberGenerator.new()
	rng.seed = STAR_SEED
	layers.clear()
	for config in LAYER_CONFIG:
		var stars = []
		for i in config.count:
			var pos = Vector2(
				rng.randf_range(field_min.x, field_max.x),
				rng.randf_range(field_min.y, field_max.y)
			)
			var size = rng.randf_range(0.7, 2.2)
			var brightness = rng.randf_range(0.25, 0.85)
			stars.append({"position": pos, "size": size, "brightness": brightness})
		layers.append({"stars": stars, "parallax": config.parallax})

func _draw():
	var cam_pos = get_camera_position()
	# Draw black background covering the entire arena (with margin)
	var margin = 200.0
	var arena_size = arena_max - arena_min
	var bg_rect = Rect2(arena_min - Vector2(margin, margin), arena_size + Vector2(margin, margin) * 2.0)
	draw_rect(bg_rect, Color(0,0,0,1), true)
	var viewport_rect = get_viewport_rect()
	var viewport_size = viewport_rect.size
	# Use arena size for wrapping so stars fill the whole playfield
	var wrap_size = arena_size + Vector2(margin, margin) * 2.0
	for layer in layers:
		var parallax = layer.parallax
		for star in layer.stars:
			var draw_pos = star.position - cam_pos * parallax
			draw_pos.x = fposmod(draw_pos.x, wrap_size.x)
			draw_pos.y = fposmod(draw_pos.y, wrap_size.y)
			# Draw if within the visible arena (with margin)
			if draw_pos.x >= -margin and draw_pos.x < arena_size.x + margin and draw_pos.y >= -margin and draw_pos.y < arena_size.y + margin:
				draw_circle(draw_pos, star.size, Color(1,1,1, star.brightness))

func get_camera_position():
	# Try to find Camera2D in parent tree
	var cam = get_viewport().get_camera_2d()
	if cam:
		return cam.global_position
	# Fallback: center of arena
	return (arena_min + arena_max) * 0.5

func get_arena_min():
	# Optionally fetch from shared constants
	return Vector2(0,0)

func get_arena_max():
	return Vector2(2048, 1152)
