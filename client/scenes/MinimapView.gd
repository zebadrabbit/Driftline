extends Control

## Renders the minimap contents. Purely client-side UI.
##
## Player is always centered; the map scrolls underneath.
## North-up (no rotation).

const DriftConstants := preload("res://shared/drift_constants.gd")

# Colors (explicit per spec)
const COLOR_WALL := Color(0.6, 0.6, 0.6, 1.0)
const COLOR_SAFE := Color(0.0, 1.0, 0.0, 0.35)
const COLOR_PRIZE := Color(0.55, 1.0, 0.55, 1.0)
const COLOR_SELF := Color(1.0, 1.0, 0.0, 1.0)
const COLOR_TEAM := Color(1.0, 1.0, 0.0, 1.0)
const COLOR_ENEMY := Color(0.2, 0.55, 1.0, 1.0)

@export var view_span_tiles: int = 48
@export var blink_period_s: float = 0.50

var tile_size_px: int = 16
var map_w_tiles: int = 0
var map_h_tiles: int = 0

var _terrain_tex: Texture2D = null
var _goal_zones: Array = []  # Array of {pos:Vector2, team:int}

var _snapshot = null
var _local_ship_id: int = -1
var _my_freq: int = 0
var _player_world_pos: Vector2 = Vector2.ZERO
var _radar_enabled: bool = true
var _xradar_active: bool = false


func set_goal_zones(zones: Array) -> void:
	if _goal_zones.size() == zones.size():
		return
	_goal_zones = zones
	queue_redraw()


var _static_built: bool = false

func set_static_geometry(meta: Dictionary, solid_cells: Array, safe_cells: Array) -> void:
	if _static_built:
		return
	_static_built = true
	tile_size_px = maxi(1, int(meta.get("tile_size", tile_size_px)))
	map_w_tiles = maxi(0, int(meta.get("w", 0)))
	map_h_tiles = maxi(0, int(meta.get("h", 0)))
	_terrain_tex = _build_terrain_texture(map_w_tiles, map_h_tiles, solid_cells, safe_cells)
	queue_redraw()


func set_dynamic_state(snapshot, local_ship_id: int, my_freq: int, player_world_pos: Vector2, radar_enabled: bool, xradar_active: bool) -> void:
	_snapshot = snapshot
	_local_ship_id = int(local_ship_id)
	_my_freq = int(my_freq)
	_player_world_pos = player_world_pos
	_radar_enabled = bool(radar_enabled)
	_xradar_active = bool(xradar_active)
	queue_redraw()


func _build_terrain_texture(w_tiles: int, h_tiles: int, solid_cells: Array, safe_cells: Array) -> Texture2D:
	if w_tiles <= 0 or h_tiles <= 0:
		return null

	var img := Image.create(w_tiles, h_tiles, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Safe zones first (green fill)
	for cell in safe_cells:
		if not (cell is Array) or (cell as Array).size() < 2:
			continue
		var x: int = int(cell[0])
		var y: int = int(cell[1])
		if x < 0 or y < 0 or x >= w_tiles or y >= h_tiles:
			continue
		img.set_pixel(x, y, COLOR_SAFE)

	# Walls over safe zones
	for cell2 in solid_cells:
		if not (cell2 is Array) or (cell2 as Array).size() < 2:
			continue
		var x2: int = int(cell2[0])
		var y2: int = int(cell2[1])
		if x2 < 0 or y2 < 0 or x2 >= w_tiles or y2 >= h_tiles:
			continue
		img.set_pixel(x2, y2, COLOR_WALL)

	var tex := ImageTexture.create_from_image(img)
	return tex


func _draw() -> void:
	# Background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.75), true)
	# Border (light grey)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.75, 0.75, 0.75, 1.0), false, 1.0)

	if _terrain_tex == null or map_w_tiles <= 0 or map_h_tiles <= 0:
		_draw_player_dot()
		return

	var span: int = maxi(4, int(view_span_tiles))
	var px_per_tile: float = minf(size.x, size.y) / float(span)
	var dest_size := Vector2(float(span) * px_per_tile, float(span) * px_per_tile)
	var dest_origin := (size - dest_size) * 0.5

	# Player in tile-space (arena origin assumed aligned to map origin).
	# TODO: If maps can have non-zero origin, plumb that through meta and offset here.
	var player_tile := Vector2(
		(float(_player_world_pos.x) - float(DriftConstants.ARENA_MIN.x)) / float(tile_size_px),
		(float(_player_world_pos.y) - float(DriftConstants.ARENA_MIN.y)) / float(tile_size_px)
	)

	var half: float = float(span) * 0.5
	var desired_tl := player_tile - Vector2(half, half)

	var skip_left: float = maxf(0.0, -desired_tl.x)
	var skip_top: float = maxf(0.0, -desired_tl.y)
	var skip_right: float = maxf(0.0, (desired_tl.x + float(span)) - float(map_w_tiles))
	var skip_bottom: float = maxf(0.0, (desired_tl.y + float(span)) - float(map_h_tiles))

	var src_w: float = float(span) - skip_left - skip_right
	var src_h: float = float(span) - skip_top - skip_bottom
	if src_w > 0.0 and src_h > 0.0:
		var src_rect := Rect2(desired_tl + Vector2(skip_left, skip_top), Vector2(src_w, src_h))
		var dst_rect := Rect2(
			dest_origin + Vector2(skip_left * px_per_tile, skip_top * px_per_tile),
			Vector2(src_w * px_per_tile, src_h * px_per_tile)
		)
		draw_texture_rect_region(_terrain_tex, dst_rect, src_rect, Color.WHITE)

	_draw_dynamic(dest_origin, px_per_tile, span, player_tile)
	_draw_player_dot()


func _draw_dynamic(dest_origin: Vector2, px_per_tile: float, span: int, player_tile: Vector2) -> void:
	if _snapshot == null:
		return

	var center := dest_origin + Vector2(float(span) * px_per_tile, float(span) * px_per_tile) * 0.5
	var max_delta := float(span) * 0.5 + 2.0

	# Prizes
	if "prizes" in _snapshot:
		for p in _snapshot.prizes:
			if p == null or not ("pos" in p):
				continue
			var pos: Vector2 = p.pos
			var pt := Vector2(
				(float(pos.x) - float(DriftConstants.ARENA_MIN.x)) / float(tile_size_px),
				(float(pos.y) - float(DriftConstants.ARENA_MIN.y)) / float(tile_size_px)
			)
			var d := pt - player_tile
			if absf(d.x) > max_delta or absf(d.y) > max_delta:
				continue
			draw_circle(center + d * px_per_tile, 2.0, COLOR_PRIZE)

	# Flags
	var _snap_flags: Array = _snapshot.flags if (_snapshot is Object and "flags" in _snapshot) else (_snapshot.get("flags", []) if _snapshot is Dictionary else [])
	if not _snap_flags.is_empty():
		var t_now: float = float(Time.get_ticks_msec()) / 1000.0
		for fl in _snap_flags:
			if fl == null:
				continue
			var fpos: Vector2 = fl.position if (fl is Object) else fl.get("position", Vector2.ZERO)
			var fteam: int = int(fl.team) if (fl is Object) else int(fl.get("team", 0))
			var fat_home: bool = bool(fl.at_home) if (fl is Object) else bool(fl.get("at_home", true))
			var fpt := Vector2(
				(float(fpos.x) - float(DriftConstants.ARENA_MIN.x)) / float(tile_size_px),
				(float(fpos.y) - float(DriftConstants.ARENA_MIN.y)) / float(tile_size_px)
			)
			var fd := fpt - player_tile
			if absf(fd.x) > max_delta or absf(fd.y) > max_delta:
				continue
			# Away flags blink; home flags are steady.
			if not fat_home and fmod(t_now, 0.5) > 0.25:
				continue
			var fc := Color(1.0, 0.3, 0.3) if fteam == 1 else Color(0.3, 0.6, 1.0)
			var fp := center + fd * px_per_tile
			# Diamond shape (4 points)
			var fs: float = 3.5
			draw_colored_polygon(PackedVector2Array([fp + Vector2(0, -fs), fp + Vector2(fs, 0), fp + Vector2(0, fs), fp + Vector2(-fs, 0)]), fc)

	# Goal zones (Powerball scoring areas)
	for gz in _goal_zones:
		var gpos: Vector2 = gz.get("pos", Vector2.ZERO)
		var gteam: int = int(gz.get("team", 0))
		var gpt := Vector2(
			(float(gpos.x) - float(DriftConstants.ARENA_MIN.x)) / float(tile_size_px),
			(float(gpos.y) - float(DriftConstants.ARENA_MIN.y)) / float(tile_size_px)
		)
		var gd := gpt - player_tile
		if absf(gd.x) > max_delta or absf(gd.y) > max_delta:
			continue
		var gc := Color(1.0, 0.3, 0.3) if gteam == 1 else Color(0.3, 0.6, 1.0)
		draw_arc(center + gd * px_per_tile, 5.0, 0.0, TAU, 12, gc, 1.5)

	# Ball (Powerball)
	var ball_pos: Vector2 = _snapshot.ball_position if (_snapshot is Object and "ball_position" in _snapshot) else _snapshot.get("ball_position", Vector2(-1e9, -1e9)) if _snapshot is Dictionary else Vector2(-1e9, -1e9)
	if ball_pos.x > -1e8:
		var bpt := Vector2(
			(float(ball_pos.x) - float(DriftConstants.ARENA_MIN.x)) / float(tile_size_px),
			(float(ball_pos.y) - float(DriftConstants.ARENA_MIN.y)) / float(tile_size_px)
		)
		var bd := bpt - player_tile
		if absf(bd.x) <= max_delta and absf(bd.y) <= max_delta:
			draw_circle(center + bd * px_per_tile, 3.0, Color(1.0, 1.0, 1.0, 1.0))

	# Ships
	if not _radar_enabled:
		return
	if "ships" not in _snapshot:
		return

	var ids: Array = _snapshot.ships.keys()
	ids.sort()
	for ship_id in ids:
		var ss = _snapshot.ships.get(ship_id)
		if ss == null:
			continue
		if int(ship_id) == _local_ship_id:
			continue
		var dut: int = int(ss.dead_until_tick) if ("dead_until_tick" in ss) else 0
		if dut > 0 and int(_snapshot.get("tick", 0)) < dut:
			continue
		var st_on: bool = bool(ss.stealth_on) if ("stealth_on" in ss) else false
		var ck_on: bool = bool(ss.cloak_on) if ("cloak_on" in ss) else false
		if (st_on or ck_on) and (not _xradar_active):
			continue

		var pos2: Vector2 = ss.position
		var pt2 := Vector2(
			(float(pos2.x) - float(DriftConstants.ARENA_MIN.x)) / float(tile_size_px),
			(float(pos2.y) - float(DriftConstants.ARENA_MIN.y)) / float(tile_size_px)
		)
		var d2 := pt2 - player_tile
		if absf(d2.x) > max_delta or absf(d2.y) > max_delta:
			continue

		var other_freq: int = int(ss.freq) if ("freq" in ss) else 0
		var is_team: bool = (_my_freq != 0 and other_freq == _my_freq)
		var c := COLOR_TEAM if is_team else COLOR_ENEMY
		draw_circle(center + d2 * px_per_tile, 2.0, c)

	# Radar ships: ships outside AOI sent as lightweight positional blips.
	if "radar_ships" in _snapshot:
		for rs in _snapshot.radar_ships:
			if rs == null or rs.get("dead", false):
				continue
			var rpos: Vector2 = rs.get("position", Vector2.ZERO)
			var rpt := Vector2(
				(float(rpos.x) - float(DriftConstants.ARENA_MIN.x)) / float(tile_size_px),
				(float(rpos.y) - float(DriftConstants.ARENA_MIN.y)) / float(tile_size_px)
			)
			var rd := rpt - player_tile
			if absf(rd.x) > max_delta or absf(rd.y) > max_delta:
				continue
			var rfreq: int = int(rs.get("freq", 0))
			var ris_team: bool = (_my_freq != 0 and rfreq == _my_freq)
			draw_circle(center + rd * px_per_tile, 2.0, COLOR_TEAM if ris_team else COLOR_ENEMY)

	# Decoys: show as dim enemy/team blips (same as ships, slightly smaller).
	if "decoys" in _snapshot:
		for dc in _snapshot.decoys:
			if dc == null:
				continue
			var dpos: Vector2 = dc.position if dc is Object else dc.get("position", Vector2.ZERO)
			var dfreq: int = int(dc.freq) if dc is Object else int(dc.get("freq", 0))
			var dpt := Vector2(
				(float(dpos.x) - float(DriftConstants.ARENA_MIN.x)) / float(tile_size_px),
				(float(dpos.y) - float(DriftConstants.ARENA_MIN.y)) / float(tile_size_px)
			)
			var dd := dpt - player_tile
			if absf(dd.x) > max_delta or absf(dd.y) > max_delta:
				continue
			var dis_team: bool = (_my_freq != 0 and dfreq == _my_freq)
			draw_circle(center + dd * px_per_tile, 1.5, (COLOR_TEAM if dis_team else COLOR_ENEMY) * Color(1, 1, 1, 0.5))


func _draw_player_dot() -> void:
	var span: int = maxi(4, int(view_span_tiles))
	var px_per_tile: float = minf(size.x, size.y) / float(span)
	var dest_size := Vector2(float(span) * px_per_tile, float(span) * px_per_tile)
	var dest_origin := (size - dest_size) * 0.5
	var center := dest_origin + dest_size * 0.5

	var t: float = float(Time.get_ticks_msec()) / 1000.0
	var phase: float = fmod(t, blink_period_s)
	var on: bool = phase < (blink_period_s * 0.5)
	if on:
		draw_circle(center, 2.5, COLOR_SELF)
