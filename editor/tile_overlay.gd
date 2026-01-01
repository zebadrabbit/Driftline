## Visual overlay renderer for the map editor.
##
## Draws per-cell overlays in viewport space aligned to the editor tile grid.

class_name TileOverlay
extends Control

enum Mode { SOLID, RESTITUTION }

var mode: int = Mode.SOLID
var tile_size: Vector2i = Vector2i(16, 16)
var collision_cells: Dictionary = {} # Dictionary[Vector2i, Dictionary]
var camera: Camera2D = null
var map_canvas: Node2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 2000


func set_collision_cells(cells: Dictionary) -> void:
	collision_cells = cells
	queue_redraw()


func _draw() -> void:
	if map_canvas == null:
		return
	if collision_cells.is_empty():
		return

	# Convert world/canvas coordinates to viewport coordinates.
	# In Godot 4, Camera2D affects the viewport's canvas transform.
	var canvas_to_viewport: Transform2D = get_viewport().get_canvas_transform()

	var keys: Array = collision_cells.keys()
	keys.sort_custom(Callable(self, "_cell_less"))

	for k in keys:
		if typeof(k) != TYPE_VECTOR2I:
			continue
		var cell: Vector2i = k
		var info: Dictionary = collision_cells.get(cell, {})
		var restitution: float = clampf(float(info.get("restitution", 0.0)), 0.0, 1.2)

		var tl_world := map_canvas.to_global(Vector2(cell.x * tile_size.x, cell.y * tile_size.y))
		var br_world := map_canvas.to_global(Vector2((cell.x + 1) * tile_size.x, (cell.y + 1) * tile_size.y))
		var tl: Vector2 = canvas_to_viewport * tl_world
		var br: Vector2 = canvas_to_viewport * br_world
		var rect := Rect2(tl, br - tl).abs()

		if mode == Mode.SOLID:
			draw_rect(rect, Color(1.0, 0.2, 0.2, 0.22), true)
			draw_rect(rect, Color(1.0, 0.2, 0.2, 0.55), false, 1.0)
		else:
			var t := clampf(restitution / 1.2, 0.0, 1.0)
			var c := Color(0.2, 0.6, 1.0, 0.10 + 0.35 * t)
			draw_rect(rect, c, true)
			draw_rect(rect, Color(0.2, 0.6, 1.0, 0.55), false, 1.0)


func _cell_less(a, b) -> bool:
	# a/b are Vector2i
	if int(a.x) != int(b.x):
		return int(a.x) < int(b.x)
	return int(a.y) < int(b.y)
