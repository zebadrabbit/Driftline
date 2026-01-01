## Simple deterministic test puck for the map editor.
##
## - Custom fixed-step integration (no Godot physics bodies).
## - Collides against a collision cache keyed by tile cell.

class_name TestPuck
extends Node2D

var tile_size: Vector2i = Vector2i(16, 16)
var radius: float = 6.0
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO


func reset(p: Vector2) -> void:
	pos = p
	vel = Vector2.ZERO
	position = pos
	queue_redraw()


func shoot_towards(world_target: Vector2, speed: float = 520.0) -> void:
	var d := world_target - pos
	if d.length_squared() <= 0.00001:
		return
	vel = d.normalized() * speed


func step(dt: float, collision_cells: Dictionary) -> void:
	# Integrate
	pos += vel * dt

	# Collide (a few iterations for stability)
	for _i in range(4):
		var hit := _resolve_collisions(collision_cells)
		if not hit:
			break

	position = pos
	queue_redraw()


func _resolve_collisions(collision_cells: Dictionary) -> bool:
	var min_x := int(floor((pos.x - radius) / float(tile_size.x)))
	var max_x := int(floor((pos.x + radius) / float(tile_size.x)))
	var min_y := int(floor((pos.y - radius) / float(tile_size.y)))
	var max_y := int(floor((pos.y + radius) / float(tile_size.y)))

	var candidates: Array[Vector2i] = []
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var cell := Vector2i(x, y)
			if collision_cells.has(cell):
				candidates.append(cell)

	if candidates.is_empty():
		return false

	# Deterministic order
	candidates.sort_custom(Callable(self, "_cell_less"))

	for cell in candidates:
		var info: Dictionary = collision_cells.get(cell, {})
		var restitution: float = clampf(float(info.get("restitution", 0.0)), 0.0, 1.2)
		var friction: float = clampf(float(info.get("friction", 0.0)), 0.0, 1.0)

		var aabb_pos := Vector2(cell.x * tile_size.x, cell.y * tile_size.y)
		var aabb_size := Vector2(tile_size.x, tile_size.y)
		var result := _circle_vs_aabb(pos, radius, aabb_pos, aabb_size)
		if not bool(result.get("hit", false)):
			continue

		var normal: Vector2 = result.get("normal", Vector2.ZERO)
		var penetration: float = float(result.get("penetration", 0.0))
		if normal == Vector2.ZERO or penetration <= 0.0:
			continue

		# Positional correction
		pos += normal * penetration

		# Velocity response: reflect normal component by restitution; damp tangential by (1-friction)
		var v_n := normal * vel.dot(normal)
		var v_t := vel - v_n
		vel = (-v_n * restitution) + (v_t * (1.0 - friction))
		return true

	return false


func _circle_vs_aabb(c: Vector2, r: float, p: Vector2, s: Vector2) -> Dictionary:
	var closest := Vector2(
		clampf(c.x, p.x, p.x + s.x),
		clampf(c.y, p.y, p.y + s.y)
	)
	var delta := c - closest
	var dist2 := delta.length_squared()
	if dist2 > r * r:
		return {"hit": false}

	# If center is inside AABB, pick smallest axis as normal.
	if dist2 <= 0.0000001:
		var left: float = absf(c.x - p.x)
		var right: float = absf((p.x + s.x) - c.x)
		var top: float = absf(c.y - p.y)
		var bottom: float = absf((p.y + s.y) - c.y)
		var m: float = minf(minf(left, right), minf(top, bottom))
		var n: Vector2 = Vector2.ZERO
		if m == left:
			n = Vector2(-1, 0)
			return {"hit": true, "normal": n, "penetration": r + left}
		elif m == right:
			n = Vector2(1, 0)
			return {"hit": true, "normal": n, "penetration": r + right}
		elif m == top:
			n = Vector2(0, -1)
			return {"hit": true, "normal": n, "penetration": r + top}
		else:
			n = Vector2(0, 1)
			return {"hit": true, "normal": n, "penetration": r + bottom}

	var dist := sqrt(dist2)
	var normal := delta / dist
	var penetration := r - dist
	return {"hit": true, "normal": normal, "penetration": penetration}


func _cell_less(a: Vector2i, b: Vector2i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(1, 1, 1, 0.95))
	draw_circle(Vector2.ZERO, radius, Color(0, 0, 0, 1.0), false, 1.5)
