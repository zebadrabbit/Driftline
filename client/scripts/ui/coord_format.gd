## Deterministic coordinate formatting for HUD/minimap.
##
## Coordinate system:
## - Letters increase LEFT -> RIGHT
## - Numbers increase TOP -> BOTTOM
##
## NOTE/TODO: This uses a fixed 20x20 sector grid (SubSpace-style).
## If Driftline adopts a different sector count, make this configurable via ruleset.

class_name DriftCoordFormat

static func sector_label(world_pos: Vector2, arena_min: Vector2, arena_max: Vector2, cols: int = 20, rows: int = 20) -> String:
	var w: float = float(arena_max.x - arena_min.x)
	var h: float = float(arena_max.y - arena_min.y)
	if w <= 0.0 or h <= 0.0:
		return "A1"

	cols = maxi(1, int(cols))
	rows = maxi(1, int(rows))

	var nx: float = (float(world_pos.x) - float(arena_min.x)) / w
	var ny: float = (float(world_pos.y) - float(arena_min.y)) / h
	nx = clampf(nx, 0.0, 0.999999)
	ny = clampf(ny, 0.0, 0.999999)

	var col: int = clampi(int(floor(nx * float(cols))), 0, cols - 1)
	var row: int = clampi(int(floor(ny * float(rows))), 0, rows - 1)

	var letter_code: int = int("A".unicode_at(0)) + col
	var letter: String = String.chr(letter_code)
	return "%s%d" % [letter, row + 1]
