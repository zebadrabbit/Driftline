## Tile definition loader + helpers (shared).
##
## Source of truth for per-tile behavior (solidity, render layer, safe zones, etc).
## Reads tiles_def.json for a given tileset.

class_name DriftTileDefs

const DriftMap = preload("res://shared/drift_map.gd")

# tileset_name -> { ok, path, defaults, tiles, error }
static var _cache: Dictionary = {}


static func _resolve_tiles_def_path(tileset_name: String) -> String:
	var ts := String(tileset_name).strip_edges()
	if ts == "":
		ts = "subspace_base"
	return "res://client/graphics/tilesets/%s/tiles_def.json" % ts


static func load_tileset(tileset_name: String) -> Dictionary:
	var key := String(tileset_name).strip_edges()
	if _cache.has(key):
		return _cache[key]

	var defaults: Dictionary = {
		"solid": true,
		"safe_zone": false,
		"render_layer": "solid",
		"restitution": 0.90,
		"door": false,
	}

	var path := _resolve_tiles_def_path(key)
	if not FileAccess.file_exists(path):
		var res_missing := {
			"ok": false,
			"path": path,
			"defaults": defaults,
			"tiles": {},
			"error": "tiles_def.json not found: " + path,
		}
		_cache[key] = res_missing
		return res_missing

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var res_open := {
			"ok": false,
			"path": path,
			"defaults": defaults,
			"tiles": {},
			"error": "Failed to open tiles_def.json: " + path,
		}
		_cache[key] = res_open
		return res_open

	var json_str := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_str)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		var res_parse := {
			"ok": false,
			"path": path,
			"defaults": defaults,
			"tiles": {},
			"error": "Invalid tiles_def.json (must be an object): " + path,
		}
		_cache[key] = res_parse
		return res_parse

	var root: Dictionary = parsed
	if root.has("defaults") and root["defaults"] is Dictionary:
		for k in (root["defaults"] as Dictionary).keys():
			defaults[k] = (root["defaults"] as Dictionary)[k]

	var tiles: Dictionary = {}
	if root.has("tiles") and root["tiles"] is Dictionary:
		tiles = root["tiles"]

	var res_ok := {
		"ok": true,
		"path": path,
		"defaults": defaults,
		"tiles": tiles,
		"error": "",
	}
	_cache[key] = res_ok
	return res_ok


static func tile_props(tileset_def: Dictionary, atlas_x: int, atlas_y: int) -> Dictionary:
	var defaults: Dictionary = tileset_def.get("defaults", {})
	var tiles: Dictionary = tileset_def.get("tiles", {})
	var key := "%d,%d" % [atlas_x, atlas_y]
	var out: Dictionary = {}
	for k in defaults.keys():
		out[k] = defaults[k]
	if tiles.has(key) and tiles[key] is Dictionary:
		var t: Dictionary = tiles[key]
		for k2 in t.keys():
			out[k2] = t[k2]
	return out


static func tile_is_solid(tileset_def: Dictionary, atlas_x: int, atlas_y: int) -> bool:
	var p := tile_props(tileset_def, atlas_x, atlas_y)
	return bool(p.get("solid", true))


static func tile_render_layer(tileset_def: Dictionary, atlas_x: int, atlas_y: int) -> String:
	var p := tile_props(tileset_def, atlas_x, atlas_y)
	var layer := String(p.get("render_layer", "solid"))
	if layer not in ["bg", "solid", "fg"]:
		layer = "solid"
	return layer


static func build_render_layers(map_canonical: Dictionary, tileset_def: Dictionary) -> Dictionary:
	var layers: Dictionary = map_canonical.get("layers", {})
	var seen := {
		"bg": {},
		"solid": {},
		"fg": {},
	}

	for src_layer in ["bg", "solid", "fg"]:
		var cells: Array = layers.get(src_layer, [])
		for cell in cells:
			if not (cell is Array) or (cell as Array).size() != 4:
				continue
			var arr: Array = cell
			var x: int = int(arr[0])
			var y: int = int(arr[1])
			var ax: int = int(arr[2])
			var ay: int = int(arr[3])
			var dest := tile_render_layer(tileset_def, ax, ay)
			(seen[dest] as Dictionary)["%d,%d" % [x, y]] = [x, y, ax, ay]

	return {
		"bg": _sorted_cells((seen["bg"] as Dictionary).values()),
		"solid": _sorted_cells((seen["solid"] as Dictionary).values()),
		"fg": _sorted_cells((seen["fg"] as Dictionary).values()),
	}


static func build_solid_cells(map_canonical: Dictionary, tileset_def: Dictionary) -> Array:
	var layers: Dictionary = map_canonical.get("layers", {})
	return build_solid_cells_from_layer_cells(layers.get("solid", []), tileset_def)


static func build_solid_cells_from_layer_cells(cells: Array, tileset_def: Dictionary) -> Array:
	var seen: Dictionary = {} # "x,y" -> [x,y,ax,ay]
	for cell in cells:
		if not (cell is Array) or (cell as Array).size() != 4:
			continue
		var arr: Array = cell
		var x: int = int(arr[0])
		var y: int = int(arr[1])
		var ax: int = int(arr[2])
		var ay: int = int(arr[3])
		if not tile_is_solid(tileset_def, ax, ay):
			continue
		seen["%d,%d" % [x, y]] = [x, y, ax, ay]
	return _sorted_cells(seen.values())


static func _sorted_cells(cells_in: Array) -> Array:
	var cells := cells_in.duplicate(true)
	cells.sort_custom(Callable(DriftTileDefs, "_cell_less"))
	return cells


static func _cell_less(a, b) -> bool:
	# a/b are [x,y,ax,ay]
	if int(a[0]) != int(b[0]):
		return int(a[0]) < int(b[0])
	if int(a[1]) != int(b[1]):
		return int(a[1]) < int(b[1])
	if int(a[2]) != int(b[2]):
		return int(a[2]) < int(b[2])
	return int(a[3]) < int(b[3])
