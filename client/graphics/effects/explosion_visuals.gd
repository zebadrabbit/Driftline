## Client-only explosion atlas descriptor.
##
## Three tiers of explosion: small (bullet hit), medium (bomb), large (death).
## Each tier has its own texture spritesheet with fixed frame layout.

extends Resource
class_name ExplosionVisuals

@export var texture: Texture2D
@export var frame_size_px: Vector2i = Vector2i(48, 48)
@export var total_frames: int = 36
@export var frames_per_row: int = 6
@export var anim_period_ticks: int = 2


func get_frame_uv(frame_index: int) -> Vector2i:
	var f: int = clampi(int(frame_index), 0, maxi(0, int(total_frames) - 1))
	var col: int = f % maxi(1, int(frames_per_row))
	var row: int = f / maxi(1, int(frames_per_row))
	return Vector2i(col, row)


func get_total_ticks() -> int:
	return int(total_frames) * maxi(1, int(anim_period_ticks))


func get_frame_for_tick(elapsed_ticks: int) -> int:
	var period: int = maxi(1, int(anim_period_ticks))
	return clampi(int(elapsed_ticks) / period, 0, int(total_frames) - 1)


func is_finished(elapsed_ticks: int) -> bool:
	return int(elapsed_ticks) >= get_total_ticks()
