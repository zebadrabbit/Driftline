## Client-only bullet atlas descriptor.
##
## Pure visuals: driven only by projectile traits (level, bounce, power tier).
## No gameplay logic, no ship-name logic, no ruleset lookups.

extends Resource
class_name BulletVisuals

@export var texture: Texture2D
@export var frame_size_px: Vector2i = Vector2i(16, 16)
@export var frames_per_row: int = 10
@export var anim_period_ticks: int = 2


func get_bullet_uv(level: int, has_bounce: bool, _power_tier: int, tick: int) -> Vector2i:
	# Sheet: 4 cols x 10 rows at 5x5px.
	# Rows 0-3: level 1-4 normal. Rows 4-7: level 1-4 bounce. Rows 8-9: unused.
	var level_clamped: int = clampi(int(level), 1, 4)
	var bounce_variant: int = 1 if bool(has_bounce) else 0
	var row: int = bounce_variant * 4 + (level_clamped - 1)
	var period: int = maxi(1, int(anim_period_ticks))
	var col: int = int(floor(float(int(tick)) / float(period))) % maxi(1, int(frames_per_row))
	if col < 0:
		col += maxi(1, int(frames_per_row))
	return Vector2i(col, row)
