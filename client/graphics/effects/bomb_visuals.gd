## Client-only bomb atlas descriptor.
##
## Pure visuals: no ruleset logic, no ship-name logic, no gameplay state mutation.

extends Resource
class_name BombVisuals

@export var texture: Texture2D
@export var frame_size_px: Vector2i = Vector2i(16, 16)
@export var frames_per_row: int = 10
@export var anim_period_ticks: int = 3


func get_bomb_uv(level: int, has_shrapnel: bool, has_bounce: bool, tick: int) -> Vector2i:
	var level_clamped: int = clampi(int(level), 1, 4)
	var variant: int = 0
	if bool(has_shrapnel) and bool(has_bounce):
		variant = 2
	elif bool(has_shrapnel):
		variant = 1
	elif bool(has_bounce):
		# If has_bounce and no shrapnel, treat as variant 2.
		variant = 2
	var row: int = variant * 4 + (level_clamped - 1)
	var period: int = maxi(1, int(anim_period_ticks))
	var col: int = int(floor(float(int(tick)) / float(period))) % maxi(1, int(frames_per_row))
	if col < 0:
		col += maxi(1, int(frames_per_row))
	return Vector2i(col, row)
