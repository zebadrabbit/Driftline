## Deterministic UI icon atlas contract.
##
## Contract summary (fixed):
## - Texture:  res://client/graphics/ui/Icons.png
## - TileSet:  res://client/graphics/ui/Icons.tres
## - Tile size: 26x24
## - Grid: 9 columns, 0-based (row,col)
##
## IMPORTANT:
## - Treat mappings as a fixed data contract.
## - Do not reinterpret meanings or sides.
## - Reserved blank tiles must not be rendered.

class_name DriftUiIconAtlas
extends RefCounted

const ICONS_TEXTURE_PATH: String = "res://client/graphics/ui/Icons.png"
const ICONS_TILESET_PATH: String = "res://client/graphics/ui/Icons.tres"

const TILE_W: int = 26
const TILE_H: int = 24
const GRID_COLS: int = 9
const GRID_ROWS: int = 6

enum Side { LEFT, RIGHT }


static func rc(row: int, col: int) -> Vector2i:
	# The written contract uses (row,col). Godot atlas coords are Vector2i(col,row).
	return Vector2i(int(col), int(row))


static func coords_is_valid(atlas: Vector2i) -> bool:
	return atlas.x >= 0 and atlas.x < GRID_COLS and atlas.y >= 0 and atlas.y < GRID_ROWS


static func coords_is_blank(atlas: Vector2i) -> bool:
	# Row 5 blanks are reserved and must not be rendered.
	# (5,2) blank (unused)
	# (5,4) blank (unused)
	# (5,6..8) blank
	# NOTE: placeholders (5,3) and (5,5) are *not* blanks.
	if atlas.y != 5:
		return false
	return atlas.x == 2 or atlas.x == 4 or atlas.x >= 6


static func coords_is_renderable(atlas: Vector2i) -> bool:
	return coords_is_valid(atlas) and not coords_is_blank(atlas)


static func coords_to_region_rect_px(atlas: Vector2i) -> Rect2i:
	# Converts atlas coords to a pixel region in Icons.png.
	return Rect2i(atlas.x * TILE_W, atlas.y * TILE_H, TILE_W, TILE_H)


static func gun_icon_coords(
		gun_level: int,
		bounce: bool,
		multishot_owned: bool,
		multishot_enabled: bool
	) -> Vector2i:
	# Rows:
	# - Row 0: Guns (no bounce)
	# - Row 1: Guns (bounce)
	# Col groups:
	# - 0..2: single
	# - 3..5: multishot enabled
	# - 6..8: multishot owned, single-fire mode
	var lvl := clampi(int(gun_level), 1, 3)
	var row := 1 if bool(bounce) else 0

	var variant_base_col: int = 0
	if bool(multishot_enabled):
		variant_base_col = 3
	elif bool(multishot_owned):
		variant_base_col = 6

	return rc(row, variant_base_col + (lvl - 1))


static func bomb_icon_coords(
		bomb_level: int,
		proximity_enabled: bool,
		shrapnel_enabled: bool
	) -> Vector2i:
	# Rows:
	# - Row 2: base variants
	# - Row 3: proximity + shrapnel
	# Col groups in Row 2:
	# - 0..2: no proximity, no shrapnel
	# - 3..5: proximity, no shrapnel
	# - 6..8: no proximity, shrapnel
	var lvl := clampi(int(bomb_level), 1, 3)
	var prox := bool(proximity_enabled)
	var shrap := bool(shrapnel_enabled)
	if prox and shrap:
		return rc(3, (lvl - 1))
	if prox and not shrap:
		return rc(2, 3 + (lvl - 1))
	if (not prox) and shrap:
		return rc(2, 6 + (lvl - 1))
	return rc(2, (lvl - 1))


static func toggle_icon_coords(toggle: StringName, enabled: bool) -> Vector2i:
	# Contracted toggles:
	# - Radar:   row3 col5/6 (right)
	# - Stealth: row3 col7/8 (right)
	# - XRadar:  row4 col0/1 (right)
	# - Antiwarp:row4 col2/3 (right)
	var on := bool(enabled)
	match String(toggle):
		"radar":
			return rc(3, 5 if on else 6)
		"stealth":
			return rc(3, 7 if on else 8)
		"xradar":
			return rc(4, 0 if on else 1)
		"antiwarp":
			return rc(4, 2 if on else 3)
		_:
			push_error("Unknown UI icon toggle: %s" % String(toggle))
			return Vector2i(-1, -1)


static func key_icon_coords() -> Vector2i:
	# (5,0) right key
	return rc(5, 0)


static func teleport_icon_coords() -> Vector2i:
	# (5,1) left teleport
	return rc(5, 1)


static func inventory_icon_coords(item: StringName) -> Vector2i:
	# Left-side consumables inventory icons.
	match String(item):
		"burst":
			return rc(3, 3)
		"repel":
			return rc(3, 4)
		"decoy":
			return rc(4, 4)
		"thor":
			return rc(4, 5)
		"brick":
			return rc(4, 6)
		"thruster":
			return rc(4, 7)
		"rocket":
			return rc(4, 8)
		"teleport":
			return teleport_icon_coords()
		_:
			push_error("Unknown UI inventory icon: %s" % String(item))
			return Vector2i(-1, -1)


static func empty_placeholder_coords(side: int) -> Vector2i:
	# Row 5 placeholders (renderable).
	# - (5,3) right empty placeholder
	# - (5,5) left  empty placeholder
	var s := int(side)
	if s == int(Side.RIGHT):
		return rc(5, 3)
	if s == int(Side.LEFT):
		return rc(5, 5)
	push_error("Unknown placeholder side: %s" % str(side))
	return Vector2i(-1, -1)
