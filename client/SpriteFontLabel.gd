class_name SpriteFontLabel
extends Control

## SpriteFontLabel
##
## Efficient sprite-font text renderer for SubSpace-style bitmap fonts.
##
## Key assumptions (matches your provided spec):
## - Monospace, fixed cell grid.
## - ASCII glyphs are arranged sequentially across the grid for chars 32..126.
##   There are 96 glyphs total, which fits exactly in 2 rows of 48 columns.
##
## ASCII -> glyph index mapping:
## - We map printable ASCII 32..126 to indices 0..94 using:
##     glyph_index = ascii_code - 32
## - (Optionally) ASCII 127/128 can exist depending on your sheet; unknown chars become '?'.
##
## Region calculation (atlas):
## - Base grid location for a glyph:
##     col = glyph_index % columns
##     row = glyph_index / columns   (integer division)
##     src_x = col * cell_w
##     src_y = row * cell_h
## - If using a single atlas with 8 vertically stacked color bands:
##     rows_per_color = 2
##     color_band_height_px = rows_per_color * cell_h
##     src_y += color_index * color_band_height_px
##
## Performance:
## - No per-character nodes.
## - When text changes, we cache each glyph's source Rect2i.
## - _draw() just loops cached rects and calls draw_texture_rect_region().


enum FontSize { SMALL, LARGE }
enum Align { LEFT, CENTER, RIGHT }

# --- Static helper (world-space drawing) ---
static var _static_small_atlas: Texture2D = null
static var _static_large_atlas: Texture2D = null


static func draw_text(canvas: CanvasItem, pos: Vector2, text: String, p_font_size: FontSize = FontSize.SMALL, p_color_index: int = 0, p_letter_spacing_px: int = 0) -> void:
	if canvas == null:
		return
	if text == "":
		return

	_static_ensure_default_textures()

	var color_index := clampi(p_color_index, 0, 7)
	var atlas: Texture2D = _static_small_atlas if p_font_size == FontSize.SMALL else _static_large_atlas
	if atlas == null:
		return

	var cell_w := SMALL_CELL_W if p_font_size == FontSize.SMALL else LARGE_CELL_W
	var cell_h := SMALL_CELL_H if p_font_size == FontSize.SMALL else LARGE_CELL_H
	var columns := SMALL_COLUMNS if p_font_size == FontSize.SMALL else LARGE_COLUMNS
	var rows_per_color := SMALL_ROWS_PER_COLOR if p_font_size == FontSize.SMALL else LARGE_ROWS_PER_COLOR
	var band_y_px := color_index * rows_per_color * cell_h

	var x := pos.x
	var y := pos.y
	for i in range(text.length()):
		var code := text.unicode_at(i)
		var resolved := code
		if resolved < ASCII_FIRST or resolved > ASCII_LAST:
			resolved = ASCII_FALLBACK
		var glyph_index := resolved - ASCII_FIRST
		var col := int(glyph_index % columns)
		var row := int(glyph_index / columns)
		var src := Rect2i(col * cell_w, band_y_px + row * cell_h, cell_w, cell_h)
		var dst := Rect2(Vector2(x, y), Vector2(cell_w, cell_h))
		canvas.draw_texture_rect_region(atlas, dst, src)
		x += float(cell_w + p_letter_spacing_px)


static func _static_ensure_default_textures() -> void:
	# Repo note: the *variant* PNGs are byte-identical; Godot's .import uses
	# different image_margin values to select a vertical band.
	# For sprite-font drawing, we use a single stacked atlas + band offset.
	if _static_small_atlas == null:
		_static_small_atlas = _static_load_png_texture("res://client/fonts/shrtfont_white.png")
	if _static_large_atlas == null:
		_static_large_atlas = _static_load_png_texture("res://client/fonts/largefont_white.png")


static func _static_load_png_texture(path: String) -> Texture2D:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("SpriteFontLabel: failed to read PNG bytes: %s" % path)
		return null
	var img := Image.new()
	var err := img.load_png_from_buffer(bytes)
	if err != OK:
		push_error("SpriteFontLabel: failed to decode PNG: %s (err=%d)" % [path, err])
		return null
	return ImageTexture.create_from_image(img)

# --- Small font spec ---
const SMALL_CELL_W := 8
const SMALL_CELL_H := 8
const SMALL_COLUMNS := 48
const SMALL_ROWS_PER_COLOR := 2

# --- Large font spec (your import settings) ---
const LARGE_CELL_W := 12
const LARGE_CELL_H := 18
const LARGE_COLUMNS := 48
const LARGE_ROWS_PER_COLOR := 2

const ASCII_FIRST := 32
const ASCII_LAST := 126
const ASCII_FALLBACK := 63 # '?'

# Preferred: provide a single atlas for each size (with 8 stacked color bands).
@export var small_atlas: Texture2D
@export var large_atlas: Texture2D

# Fallback mode: per-color textures (already tinted), in color-index order:
# [white, green, light blue, red, orange, purple, dark orange, pink]
@export var small_color_textures: Array[Texture2D] = []
@export var large_color_textures: Array[Texture2D] = []

@export var alignment: Align = Align.LEFT
@export var font_size: FontSize = FontSize.SMALL
@export_range(0, 7, 1) var color_index: int = 0
@export var letter_spacing_px: int = 0

var _text: String = ""

# Cached per-glyph source rects for current text
var _glyph_src_rects: Array[Rect2i] = []
var _text_pixel_width: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# If no textures were set in the Inspector, load sensible defaults from your repo.
	# These defaults match the 8-color order in the task description.
	_ensure_default_textures()
	_rebuild_cache()


# --- Public API (requested) ---
func set_text(value: String) -> void:
	if value == _text:
		return
	_text = value
	_rebuild_cache()
	queue_redraw()


func set_color_index(value: int) -> void:
	value = clampi(value, 0, 7)
	if value == color_index:
		return
	color_index = value
	# If using a stacked atlas, src rects depend on color. Rebuild.
	if _using_stacked_atlas():
		_rebuild_cache()
	queue_redraw()


func set_font_size(value: FontSize) -> void:
	if value == font_size:
		return
	font_size = value
	_rebuild_cache()
	queue_redraw()


func set_alignment(value: Align) -> void:
	if value == alignment:
		return
	alignment = value
	queue_redraw()


func get_text() -> String:
	return _text


func get_text_width_px() -> int:
	# Cached width for the current text/font settings.
	return _text_pixel_width


func get_cell_size_px() -> Vector2i:
	return Vector2i(_cell_w(), _cell_h())


func _draw() -> void:
	var atlas: Texture2D = _get_active_texture()
	if atlas == null:
		return
	if _glyph_src_rects.is_empty():
		return

	var cell_w := _cell_w()
	var cell_h := _cell_h()

	var start_x := 0.0
	match alignment:
		Align.LEFT:
			start_x = 0.0
		Align.CENTER:
			start_x = (size.x - float(_text_pixel_width)) * 0.5
		Align.RIGHT:
			start_x = size.x - float(_text_pixel_width)
	start_x = maxf(0.0, start_x)

	var x := start_x
	var y := 0.0
	for src in _glyph_src_rects:
		# Destination rect on this Control.
		var dst := Rect2(Vector2(x, y), Vector2(cell_w, cell_h))
		draw_texture_rect_region(atlas, dst, src)
		x += float(cell_w + letter_spacing_px)


# --- Internals ---
func _using_stacked_atlas() -> bool:
	return (font_size == FontSize.SMALL and small_atlas != null) or (font_size == FontSize.LARGE and large_atlas != null)


func _get_active_texture() -> Texture2D:
	if font_size == FontSize.SMALL:
		if small_atlas != null:
			return small_atlas
		if color_index >= 0 and color_index < small_color_textures.size():
			return small_color_textures[color_index]
		return null

	# LARGE
	if large_atlas != null:
		return large_atlas
	if color_index >= 0 and color_index < large_color_textures.size():
		return large_color_textures[color_index]
	return null


func _cell_w() -> int:
	return SMALL_CELL_W if font_size == FontSize.SMALL else LARGE_CELL_W


func _cell_h() -> int:
	return SMALL_CELL_H if font_size == FontSize.SMALL else LARGE_CELL_H


func _columns() -> int:
	return SMALL_COLUMNS if font_size == FontSize.SMALL else LARGE_COLUMNS


func _rows_per_color() -> int:
	return SMALL_ROWS_PER_COLOR if font_size == FontSize.SMALL else LARGE_ROWS_PER_COLOR


func _rebuild_cache() -> void:
	_glyph_src_rects.clear()
	_text_pixel_width = 0

	if _text == "":
		return

	var atlas := _get_active_texture()
	if atlas == null:
		return

	var cell_w := _cell_w()
	var cell_h := _cell_h()
	var columns := _columns()

	# Color-band offset only applies when using a stacked atlas.
	var band_y_px := 0
	if _using_stacked_atlas():
		var rows_per_color := _rows_per_color()
		var color_band_height_px := rows_per_color * cell_h
		band_y_px = color_index * color_band_height_px

	for i in range(_text.length()):
		var code := _text.unicode_at(i)
		var resolved := code

		# Only map printable ASCII; unknown becomes '?'.
		if resolved < ASCII_FIRST or resolved > ASCII_LAST:
			resolved = ASCII_FALLBACK

		var glyph_index := resolved - ASCII_FIRST
		# With 48 columns, 96 glyphs fit in 2 rows.
		var col := int(glyph_index % columns)
		var row := int(glyph_index / columns)

		var src := Rect2i(col * cell_w, band_y_px + row * cell_h, cell_w, cell_h)
		_glyph_src_rects.append(src)

	_text_pixel_width = (_glyph_src_rects.size() * cell_w) + max(0, _glyph_src_rects.size() - 1) * letter_spacing_px


func _ensure_default_textures() -> void:
	# Only fill defaults if the Inspector didn't set anything.
	# Repo note: the *variant* PNGs are byte-identical; Godot's .import uses
	# different image_margin values to select a vertical band.
	# For sprite-font drawing, we use a single stacked atlas + band offset.
	if small_atlas == null:
		small_atlas = _load_png_texture("res://client/fonts/shrtfont_white.png")
	if large_atlas == null:
		large_atlas = _load_png_texture("res://client/fonts/largefont_white.png")


func _load_png_texture(path: String) -> Texture2D:
	# In this repo the font PNGs are imported as FontFile (font_data_image),
	# so `load()/preload()` returns a FontFile, not a Texture2D.
	# We load the PNG bytes from the PCK/resources and create an ImageTexture.
	# This avoids the export warning about loading image files directly.
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("SpriteFontLabel: failed to read PNG bytes: %s" % path)
		return null

	var img := Image.new()
	var err := img.load_png_from_buffer(bytes)
	if err != OK:
		push_error("SpriteFontLabel: failed to decode PNG: %s (err=%d)" % [path, err])
		return null

	return ImageTexture.create_from_image(img)
