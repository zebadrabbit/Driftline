## Client-only ship sprite atlas mapping for res://client/graphics/ships/ships.png
##
## Spritesheet contract (STRICT):
## - 8 ships total
## - Each ship occupies 4 consecutive rows
## - Each row contains 10 frames
## - Total rows: 32
## - Total frames per ship: 40
##
## Angle handling:
## - Input heading is continuous degrees (CCW)
## - Convert to clockwise space
## - Map to a global facing frame index 0..39
##   - dir_row = frame / 10
##   - col = frame % 10
##   - sheet_row = ship_index * 4 + dir_row

class_name DriftShipAtlas

const SHIP_COUNT: int = 8
const ROWS_PER_SHIP: int = 4
const FRAMES_PER_ROW: int = 10
const TOTAL_ROWS: int = SHIP_COUNT * ROWS_PER_SHIP
const FRAMES_PER_SHIP: int = ROWS_PER_SHIP * FRAMES_PER_ROW

# ships.png uses a different 0° reference than the simulation.
# In practice, the "0°" frame in the sheet is drawn pointing up, while the
# simulation's rotation=0 points right (+X). Apply a fixed clockwise offset to
# keep visuals aligned with movement.
const CW_HEADING_OFFSET_DEG: float = 90.0

# ships.png in this repo is authored with an opaque black matte (alpha=1 everywhere).
# For in-game rendering (especially when ship opacity is reduced), we build a cutout
# texture by flood-filling the matte from each frame's corners and setting those
# pixels alpha=0. This preserves internal dark details that are not connected to
# the matte.
static var _cached_ships_cutout: Texture2D = null


static func get_ships_texture() -> Texture2D:
	if _cached_ships_cutout != null:
		return _cached_ships_cutout

	var path := "res://client/graphics/ships/ships.png"
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("Failed to read ships texture bytes: %s" % path)
		return null
	var img := Image.new()
	var err := img.load_png_from_buffer(bytes)
	if err != OK:
		push_error("Failed to decode ships texture PNG: %s (err=%d)" % [path, err])
		return null

	# Ensure we can write alpha.
	img.convert(Image.FORMAT_RGBA8)
	_cached_ships_cutout = ImageTexture.create_from_image(_cutout_black_matte(img))
	return _cached_ships_cutout


static func _cutout_black_matte(img: Image) -> Image:
	# Modify in-place.
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return img

	# Derive frame grid from the atlas contract.
	var cell_w := int(w / FRAMES_PER_ROW)
	var cell_h := int(h / TOTAL_ROWS)
	if cell_w <= 0 or cell_h <= 0:
		return img

	# Background threshold (treat very dark as matte). ships.png corners are pure black.
	var bg_thresh := 0.02

	# Reusable work buffers per cell.
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(cell_w * cell_h)
	var queue: Array[Vector2i] = []

	for row in range(TOTAL_ROWS):
		for col in range(FRAMES_PER_ROW):
			# Reset visited.
			for i in range(visited.size()):
				visited[i] = 0
			queue.clear()

			var x0 := col * cell_w
			var y0 := row * cell_h

			# Seed from corners within this cell.
			var corners: Array[Vector2i] = [
				Vector2i(0, 0),
				Vector2i(cell_w - 1, 0),
				Vector2i(0, cell_h - 1),
				Vector2i(cell_w - 1, cell_h - 1),
			]
			for c: Vector2i in corners:
				var px: int = x0 + c.x
				var py: int = y0 + c.y
				var cc := img.get_pixel(px, py)
				if cc.r <= bg_thresh and cc.g <= bg_thresh and cc.b <= bg_thresh:
					queue.append(c)

			# Flood fill (4-neighbor) of background matte.
			while not queue.is_empty():
				var p: Vector2i = queue.pop_back()
				if p.x < 0 or p.y < 0 or p.x >= cell_w or p.y >= cell_h:
					continue
				var idx := p.y * cell_w + p.x
				if visited[idx] != 0:
					continue
				visited[idx] = 1

				var sx := x0 + p.x
				var sy := y0 + p.y
				var ccol := img.get_pixel(sx, sy)
				if ccol.r > bg_thresh or ccol.g > bg_thresh or ccol.b > bg_thresh:
					continue

				# Mark this pixel transparent.
				ccol.a = 0.0
				img.set_pixel(sx, sy, ccol)

				queue.append(p + Vector2i(1, 0))
				queue.append(p + Vector2i(-1, 0))
				queue.append(p + Vector2i(0, 1))
				queue.append(p + Vector2i(0, -1))

	return img

static func _validate_texture(tex: Texture2D) -> bool:
	if tex == null:
		return false
	var w := int(tex.get_width())
	var h := int(tex.get_height())
	if w <= 0 or h <= 0:
		return false
	if (w % FRAMES_PER_ROW) != 0:
		push_error("ships.png width must be divisible by %d (got %d)" % [FRAMES_PER_ROW, w])
		return false
	if (h % TOTAL_ROWS) != 0:
		push_error("ships.png height must be divisible by %d (got %d)" % [TOTAL_ROWS, h])
		return false
	return true

static func tile_size_px(tex: Texture2D) -> Vector2i:
	if not _validate_texture(tex):
		return Vector2i.ZERO
	return Vector2i(int(tex.get_width()) / FRAMES_PER_ROW, int(tex.get_height()) / TOTAL_ROWS)

static func heading_deg_to_frame_index(heading_deg: float) -> int:
	# Convert to clockwise space.
	var cw := fposmod(360.0 - float(heading_deg), 360.0)
	# Apply fixed sheet-to-sim alignment offset.
	cw = fposmod(cw + CW_HEADING_OFFSET_DEG, 360.0)
	# 40 facings => 9 degrees per frame.
	var step := 360.0 / float(FRAMES_PER_SHIP)
	# Floor mapping keeps the index stable across small jitter.
	var idx := int(floor(cw / step))
	return clampi(idx, 0, FRAMES_PER_SHIP - 1)

static func ship_frame_to_sheet_row(ship_index: int, frame_index: int) -> int:
	var si := clampi(int(ship_index), 0, SHIP_COUNT - 1)
	var fi := clampi(int(frame_index), 0, FRAMES_PER_SHIP - 1)
	var dir_row := fi / FRAMES_PER_ROW
	return si * ROWS_PER_SHIP + dir_row

static func ship_heading_to_sheet_coords(ship_index: int, heading_deg: float) -> Vector2i:
	var si := clampi(int(ship_index), 0, SHIP_COUNT - 1)
	var frame := heading_deg_to_frame_index(heading_deg)
	var dir_row := frame / FRAMES_PER_ROW
	var col := frame % FRAMES_PER_ROW
	var sheet_row := si * ROWS_PER_SHIP + dir_row
	return Vector2i(col, sheet_row)

static func region_rect_px(tex: Texture2D, ship_index: int, heading_deg: float) -> Rect2:
	var ts := tile_size_px(tex)
	if ts == Vector2i.ZERO:
		return Rect2(0, 0, 0, 0)
	var coords := ship_heading_to_sheet_coords(ship_index, heading_deg)
	return Rect2(float(coords.x * ts.x), float(coords.y * ts.y), float(ts.x), float(ts.y))
