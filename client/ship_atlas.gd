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
