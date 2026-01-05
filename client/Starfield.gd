extends Node2D

## Two-layer parallax starfield (purely visual).
## - Infinite scroll via seamless tiling
## - Motion derived from camera position (not time)
## - Foreground parallax factor: 1.0x
## - Background parallax factor: 0.5x
## - Pixel-aligned offsets to avoid shimmer

@export var foreground_parallax_factor: float = 0.175
@export var background_parallax_factor: float = 0.125

const FOREGROUND_SEED: int = 1337
const BACKGROUND_SEED: int = 7331

@export var tile_size_px: int = 256

@export var foreground_texture: Texture2D
@export var background_texture: Texture2D

@export var foreground_star_count: int = 40
@export var background_star_count: int = 40

# Optional: deterministic environment decals (PNG images in res://client/graphics/environment).
# These are placed over a large parallax-space grid (not baked into the small repeating tile),
# so you get variety over a larger area without aggressive tiling.
@export var environment_decals_enabled: bool = true
@export var environment_cell_size_px: int = 2048
@export var environment_decals_foreground_per_cell: int = 1
@export var environment_decals_background_per_cell: int = 1

# Extra: small star sprites (star01..star07) sprinkled more frequently.
@export var environment_star_sprites_enabled: bool = true
@export var environment_star_cell_size_px: int = 512
@export var environment_star_foreground_per_cell: int = 2
@export var environment_star_background_per_cell: int = 2

const ENVIRONMENT_DIR := "res://client/graphics/environment"

var _fg_tex: Texture2D = null
var _bg_tex: Texture2D = null
var _last_cam_px: Vector2i = Vector2i(2147483647, 2147483647)

var _env_bg_textures: Array[Texture2D] = []
var _env_star_textures: Array[Texture2D] = []


func _ready() -> void:
	# This node is meant to live under a CanvasLayer, so it draws in screen-space.
	# Keep it behind gameplay.
	z_index = -1000
	_env_bg_textures.clear()
	_env_star_textures.clear()
	if environment_decals_enabled or environment_star_sprites_enabled:
		var pair: Dictionary = _load_environment_textures_split()
		for t in pair.get("bg", []):
			_env_bg_textures.append(t)
		for t in pair.get("stars", []):
			_env_star_textures.append(t)
	_fg_tex = foreground_texture if foreground_texture != null else _make_star_tile(FOREGROUND_SEED, tile_size_px, foreground_star_count, 0.35, 1.0)
	_bg_tex = background_texture if background_texture != null else _make_star_tile(BACKGROUND_SEED, tile_size_px, background_star_count, 0.20, 0.70)
	queue_redraw()


func _process(_delta: float) -> void:
	var cam_px := _camera_pos_px()
	if cam_px != _last_cam_px:
		_last_cam_px = cam_px
		queue_redraw()


func _draw() -> void:
	# Always draw a solid black base behind both layers.
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 1), true)

	var cam := _camera_pos_px()
	_draw_tiled_layer(_bg_tex, cam, background_parallax_factor, vp)
	_draw_tiled_layer(_fg_tex, cam, foreground_parallax_factor, vp)

	if environment_decals_enabled and not _env_bg_textures.is_empty():
		_draw_environment_decals(cam, background_parallax_factor, vp, BACKGROUND_SEED, environment_cell_size_px, environment_decals_background_per_cell, _env_bg_textures)
		_draw_environment_decals(cam, foreground_parallax_factor, vp, FOREGROUND_SEED, environment_cell_size_px, environment_decals_foreground_per_cell, _env_bg_textures)
	if environment_star_sprites_enabled and not _env_star_textures.is_empty():
		_draw_environment_decals(cam, background_parallax_factor, vp, BACKGROUND_SEED ^ 0x51a7, environment_star_cell_size_px, environment_star_background_per_cell, _env_star_textures)
		_draw_environment_decals(cam, foreground_parallax_factor, vp, FOREGROUND_SEED ^ 0x1c3d, environment_star_cell_size_px, environment_star_foreground_per_cell, _env_star_textures)


func _draw_tiled_layer(tex: Texture2D, cam_px: Vector2i, parallax_factor: float, viewport_size: Vector2) -> void:
	if tex == null:
		return

	var tw := int(tex.get_width())
	var th := int(tex.get_height())
	if tw <= 0 or th <= 0:
		return

	# Compute offset from camera position and snap to pixel grid.
	var off_x: int = int(round(float(cam_px.x) * parallax_factor))
	var off_y: int = int(round(float(cam_px.y) * parallax_factor))

	# Draw origin is negative offset, wrapped into [0..tile).
	var start_x := -_posmod_int(off_x, tw)
	var start_y := -_posmod_int(off_y, th)

	var w := int(ceil(viewport_size.x))
	var h := int(ceil(viewport_size.y))
	for y in range(start_y, h + th, th):
		for x in range(start_x, w + tw, tw):
			draw_texture(tex, Vector2(float(x), float(y)))


func _camera_pos_px() -> Vector2i:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Vector2i.ZERO
	# Pixel alignment: snap world camera position to integer pixels.
	var gp: Vector2 = cam.global_position
	return Vector2i(int(round(gp.x)), int(round(gp.y)))


static func _posmod_int(a: int, m: int) -> int:
	if m <= 0:
		return 0
	var r := a % m
	if r < 0:
		r += m
	return r


static func _make_star_tile(seed: int, size_px: int, star_count: int, min_a: float, max_a: float) -> Texture2D:
	var s := maxi(32, int(size_px))
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed)

	var count := maxi(0, int(star_count))
	for i in range(count):
		var x := rng.randi_range(0, s - 1)
		var y := rng.randi_range(0, s - 1)
		var a := rng.randf_range(min_a, max_a)
		var c := Color(1, 1, 1, a)
		# Single pixel star.
		img.set_pixel(x, y, c)
		# If we're on an edge, mirror to the opposite edge to guarantee seamless tiling.
		if x == 0:
			img.set_pixel(s - 1, y, c)
		elif x == s - 1:
			img.set_pixel(0, y, c)
		if y == 0:
			img.set_pixel(x, s - 1, c)
		elif y == s - 1:
			img.set_pixel(x, 0, c)
		# Corner wrap if needed.
		if (x == 0 or x == s - 1) and (y == 0 or y == s - 1):
			img.set_pixel((x + s / 2) % s, (y + s / 2) % s, c)

	return ImageTexture.create_from_image(img)

func _draw_environment_decals(cam_px: Vector2i, parallax_factor: float, viewport_size: Vector2, seed_base: int, cell_size_px: int, decals_per_cell: int, textures: Array[Texture2D]) -> void:
	var cell := maxi(128, int(cell_size_px))
	var count := maxi(0, int(decals_per_cell))
	if count <= 0:
		return
	if textures.is_empty():
		return

	# Parallax-space camera offset (pixel-aligned).
	var cam_off := Vector2i(
		int(round(float(cam_px.x) * parallax_factor)),
		int(round(float(cam_px.y) * parallax_factor))
	)

	# Visible parallax-space region: [cam_off .. cam_off + viewport].
	var w := int(ceil(viewport_size.x))
	var h := int(ceil(viewport_size.y))
	var min_x := cam_off.x
	var min_y := cam_off.y
	var max_x := cam_off.x + w
	var max_y := cam_off.y + h

	var cx0 := floori(float(min_x) / float(cell))
	var cy0 := floori(float(min_y) / float(cell))
	var cx1 := floori(float(max_x) / float(cell))
	var cy1 := floori(float(max_y) / float(cell))

	# Small overdraw so large decals near edges still appear.
	cx0 -= 1
	cy0 -= 1
	cx1 += 1
	cy1 += 1

	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var rng := RandomNumberGenerator.new()
			rng.seed = _hash_cell_seed(seed_base, cx, cy)
			for i in range(count):
				var tex: Texture2D = textures[rng.randi_range(0, textures.size() - 1)]
				if tex == null:
					continue
				var tw := int(tex.get_width())
				var th := int(tex.get_height())
				if tw <= 0 or th <= 0:
					continue
				var px := cx * cell + rng.randi_range(0, cell - 1)
				var py := cy * cell + rng.randi_range(0, cell - 1)
				var screen := Vector2i(px - cam_off.x, py - cam_off.y)
				# Pixel aligned draw.
				draw_texture(tex, Vector2(float(screen.x), float(screen.y)))


static func _hash_cell_seed(seed_base: int, cx: int, cy: int) -> int:
	# Stable integer hash (no floats) to seed RNG per cell.
	var x := int(cx)
	var y := int(cy)
	var h := int(seed_base)
	h = int(h ^ (x * 73856093))
	h = int(h ^ (y * 19349663))
	# Mix.
	h = int(h ^ (h << 13))
	h = int(h ^ (h >> 17))
	h = int(h ^ (h << 5))
	# RNG seed must be non-negative.
	return int(h) & 0x7fffffff


static func _load_environment_textures_split() -> Dictionary:
	var bg_out: Array[Texture2D] = []
	var star_out: Array[Texture2D] = []
	var dir := DirAccess.open(ENVIRONMENT_DIR)
	if dir == null:
		return {"bg": bg_out, "stars": star_out}

	var bg_names: Array[String] = []
	var star_names: Array[String] = []

	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if dir.current_is_dir():
			continue
		if not name.to_lower().ends_with(".png"):
			continue
		if name.to_lower().ends_with(".import"):
			continue
		if name.to_lower().begins_with("star"):
			star_names.append(name)
		else:
			bg_names.append(name)
	dir.list_dir_end()

	bg_names.sort()
	star_names.sort()

	for name in bg_names:
		var t := _load_environment_texture_by_name(name)
		if t != null:
			bg_out.append(t)
	for name in star_names:
		var t2 := _load_environment_texture_by_name(name)
		if t2 != null:
			star_out.append(t2)

	return {"bg": bg_out, "stars": star_out}


static func _load_environment_texture_by_name(name: String) -> Texture2D:
	var path := ENVIRONMENT_DIR + "/" + name
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	var err := img.load_png_from_buffer(bytes)
	if err != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	_cutout_black_matte_edges(img)
	return ImageTexture.create_from_image(img)


static func _cutout_black_matte_edges(img: Image) -> void:
	# Flood-fill near-black pixels connected to the image edges and set alpha=0.
	if img == null:
		return
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return

	var bg_thresh := 0.02
	var visited := PackedByteArray()
	visited.resize(w * h)
	for i in range(visited.size()):
		visited[i] = 0

	var queue: Array[Vector2i] = []
	# Seed from all edge pixels.
	for x in range(w):
		queue.append(Vector2i(x, 0))
		queue.append(Vector2i(x, h - 1))
	for y in range(h):
		queue.append(Vector2i(0, y))
		queue.append(Vector2i(w - 1, y))

	while not queue.is_empty():
		var p: Vector2i = queue.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var idx := p.y * w + p.x
		if visited[idx] != 0:
			continue
		visited[idx] = 1
		var c := img.get_pixel(p.x, p.y)
		if c.r > bg_thresh or c.g > bg_thresh or c.b > bg_thresh:
			continue
		c.a = 0.0
		img.set_pixel(p.x, p.y, c)
		queue.append(p + Vector2i(1, 0))
		queue.append(p + Vector2i(-1, 0))
		queue.append(p + Vector2i(0, 1))
		queue.append(p + Vector2i(0, -1))
