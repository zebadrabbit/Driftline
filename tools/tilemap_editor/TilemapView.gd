## TilemapView
##
## Draws a tileset texture with a grid overlay and selection/hover highlights.
##
## This is a pure runtime Control (not an EditorPlugin).
## Zoom is applied by scaling the drawn content; grid thickness remains 1 screen pixel.

extends Control

signal hover_changed(x: int, y: int, valid: bool)
signal selection_changed(x: int, y: int, valid: bool)
signal zoom_wheel(request_zoom_multiplier: float)

var texture: Texture2D = null:
	set(v):
		texture = v
		_update_min_size()
		queue_redraw()

var tile_size: Vector2i = Vector2i(16, 16):
	set(v):
		tile_size = Vector2i(maxi(1, v.x), maxi(1, v.y))
		_update_min_size()
		queue_redraw()

var zoom: float = 1.0:
	set(v):
		zoom = clampf(v, 0.25, 8.0)
		_update_min_size()
		queue_redraw()

var scroll: ScrollContainer = null

var hover_tile := Vector2i(-1, -1)
var hover_valid := false
var selected_tile := Vector2i(-1, -1)
var selected_valid := false

var reserved_tiles: Dictionary = {} # "x,y" -> true
var purpose_tiles: Dictionary = {} # "x,y" -> {solid:bool, layer:String, tagged:bool}


func set_reserved_frames(keys: PackedStringArray) -> void:
	reserved_tiles.clear()
	for k in keys:
		reserved_tiles[String(k)] = true
	queue_redraw()


func set_purpose_tiles(purpose: Dictionary) -> void:
	# Keys are "x,y" strings. Values are dictionaries describing purpose.
	purpose_tiles = purpose if (purpose is Dictionary) else {}
	queue_redraw()


func _update_min_size() -> void:
	if texture == null:
		custom_minimum_size = Vector2(256, 256)
		return
	custom_minimum_size = texture.get_size() * zoom


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_set_selected_from_mouse(mb.position)
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			emit_signal("zoom_wheel", 1.1)
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			emit_signal("zoom_wheel", 0.9)
			return

	if event is InputEventMouseMotion:
		_update_hover_from_mouse((event as InputEventMouseMotion).position)


func _scroll_offset() -> Vector2:
	if scroll == null:
		return Vector2.ZERO
	return Vector2(float(scroll.scroll_horizontal), float(scroll.scroll_vertical))


func _mouse_to_tile(mouse_pos: Vector2) -> Dictionary:
	if texture == null:
		return {"valid": false, "x": -1, "y": -1}
	var img_size: Vector2 = texture.get_size()
	var local: Vector2 = (mouse_pos + _scroll_offset()) / zoom
	var tx := int(floor(local.x / float(tile_size.x)))
	var ty := int(floor(local.y / float(tile_size.y)))
	var cols := maxi(1, int(floor(img_size.x / float(tile_size.x))))
	var rows := maxi(1, int(floor(img_size.y / float(tile_size.y))))
	var valid := (tx >= 0 and ty >= 0 and tx < cols and ty < rows)
	return {"valid": valid, "x": tx, "y": ty}


func _update_hover_from_mouse(mouse_pos: Vector2) -> void:
	var r := _mouse_to_tile(mouse_pos)
	var v := bool(r["valid"])
	var x := int(r["x"])
	var y := int(r["y"])
	if v == hover_valid and x == hover_tile.x and y == hover_tile.y:
		return
	hover_valid = v
	hover_tile = Vector2i(x, y)
	emit_signal("hover_changed", x, y, v)
	queue_redraw()


func _set_selected_from_mouse(mouse_pos: Vector2) -> void:
	var r := _mouse_to_tile(mouse_pos)
	selected_valid = bool(r["valid"])
	selected_tile = Vector2i(int(r["x"]), int(r["y"]))
	emit_signal("selection_changed", selected_tile.x, selected_tile.y, selected_valid)
	queue_redraw()


func _draw() -> void:
	if texture == null:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.2), true)
		return

	var img_size: Vector2 = texture.get_size()
	var scaled_size := img_size * zoom
	var rect := Rect2(Vector2.ZERO, scaled_size)
	draw_texture_rect(texture, rect, false)

	# Grid (1px thickness in screen space).
	var cols := maxi(1, int(floor(img_size.x / float(tile_size.x))))
	var rows := maxi(1, int(floor(img_size.y / float(tile_size.y))))
	var step_x := float(tile_size.x) * zoom
	var step_y := float(tile_size.y) * zoom
	# Keep the base grid subtle so purpose outlines read clearly.
	var grid_color := Color(1, 1, 1, 0.06)

	for x in range(cols + 1):
		var px := float(x) * step_x
		draw_line(Vector2(px, 0), Vector2(px, step_y * rows), grid_color, 1.0)
	for y in range(rows + 1):
		var py := float(y) * step_y
		draw_line(Vector2(0, py), Vector2(step_x * cols, py), grid_color, 1.0)

	# Reserved tile marking.
	for k in reserved_tiles.keys():
		var parts := String(k).split(",")
		if parts.size() != 2:
			continue
		var rx := int(parts[0])
		var ry := int(parts[1])
		var rrect := Rect2(Vector2(rx * step_x, ry * step_y), Vector2(step_x, step_y))
		# Reserved doors: strong red fill + thick outline.
		draw_rect(rrect, Color(1.0, 0.0, 0.0, 0.16), true)
		draw_rect(rrect, Color(1.0, 0.0, 0.0, 0.95), false, 2.0)

	# Purpose outlines (solid/layer/tags/name). Keep this light: only tiles with
	# explicit purpose are passed in by the editor.
	for k in purpose_tiles.keys():
		var parts := String(k).split(",")
		if parts.size() != 2:
			continue
		var rx := int(parts[0])
		var ry := int(parts[1])
		var rrect := Rect2(Vector2(rx * step_x, ry * step_y), Vector2(step_x, step_y))

		# Don't fight with reserved highlight.
		if reserved_tiles.has(String(k)):
			continue

		var info: Dictionary = purpose_tiles.get(k, {})
		var is_solid := bool(info.get("solid", false))
		var layer := String(info.get("layer", "mid"))
		var tagged := bool(info.get("tagged", false))

		var outline := Color(1, 1, 1, 0.25)
		if is_solid:
			# Solid/walls: bright yellow-orange (distinct from reserved red).
			outline = Color(1.0, 0.80, 0.10, 0.95)
		elif tagged:
			outline = Color(0.90, 0.60, 1.0, 0.85)
		elif layer == "bg":
			outline = Color(0.35, 0.70, 1.0, 0.85)
		elif layer == "fg":
			outline = Color(0.35, 1.0, 0.65, 0.85)
		else:
			outline = Color(1, 1, 1, 0.25)

		draw_rect(rrect, outline, false, 1.5)

	# Hover highlight.
	if hover_valid:
		var hrect := Rect2(Vector2(hover_tile.x * step_x, hover_tile.y * step_y), Vector2(step_x, step_y))
		draw_rect(hrect, Color(1, 1, 0.2, 0.14), true)
		draw_rect(hrect, Color(1, 1, 0.2, 0.9), false, 1.0)

	# Selection highlight.
	if selected_valid:
		var srect := Rect2(Vector2(selected_tile.x * step_x, selected_tile.y * step_y), Vector2(step_x, step_y))
		draw_rect(srect, Color(0.2, 0.8, 1.0, 0.12), true)
		draw_rect(srect, Color(0.2, 0.8, 1.0, 0.95), false, 2.0)

	# Coordinate readout.
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var text := ""
	if hover_valid:
		var px := hover_tile.x * tile_size.x
		var py := hover_tile.y * tile_size.y
		text = "atlas %d,%d  |  px %d,%d" % [hover_tile.x, hover_tile.y, px, py]
	else:
		text = "(hover a tile)"
	draw_string(font, Vector2(8, 8 + font_size), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.95))
