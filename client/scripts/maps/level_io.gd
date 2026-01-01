extends Node

## Centralized map save/load and TileMap application utilities.
## Handles sparse JSON format and boundary stamping.

const TILE_SIZE := 16

const DriftTileDefs = preload("res://shared/drift_tile_defs.gd")
const DriftMap = preload("res://shared/drift_map.gd")


## Safe JSON parse for map import (clipboard / network / file content).
## Returns: { ok: bool, error: String, data: Dictionary }
static func parse_map_json(json_string: String) -> Dictionary:
	var result := {
		"ok": false,
		"error": "",
		"data": {}
	}
	if json_string.strip_edges() == "":
		result["error"] = "Clipboard is empty"
		return result

	var parsed = JSON.parse_string(json_string)
	if parsed == null:
		result["error"] = "Invalid JSON"
		return result
	if typeof(parsed) != TYPE_DICTIONARY:
		result["error"] = "Map JSON must be an object"
		return result

	result["ok"] = true
	result["data"] = parsed
	return result


## Apply a pre-parsed map data Dictionary to TileMaps.
## Returns normalized meta (contains w/h).
static func apply_map_data(map_data: Dictionary, tilemaps: Dictionary) -> Dictionary:
	var validated := DriftMap.validate_and_canonicalize(map_data)
	if not bool(validated.get("ok", false)):
		push_error("Map validation failed")
		for e in (validated.get("errors", []) as Array):
			push_error(" - " + String(e))
		return {}
	var canonical: Dictionary = validated.get("map", {})
	var meta: Dictionary = canonical.get("meta", {})
	var layers: Dictionary = canonical.get("layers", {})
	var w: int = int(meta.get("w", 0))
	var h: int = int(meta.get("h", 0))
	var tileset_name: String = String(meta.get("tileset", "")).strip_edges()
	if tileset_name == "":
		push_error("Map meta.tileset is required (empty)")
		return {}
	var tileset_def := DriftTileDefs.load_tileset(tileset_name)
	if not bool(tileset_def.get("ok", false)):
		push_warning("[TILES] " + String(tileset_def.get("error", "Failed to load tiles_def")))
	var routed_layers: Dictionary = DriftTileDefs.build_render_layers({"layers": layers}, tileset_def)

	# Clear all layers
	for layer_name in ["bg", "solid", "fg"]:
		if tilemaps.has(layer_name) and tilemaps[layer_name] != null:
			(tilemaps[layer_name] as TileMap).clear()

	# Apply loaded tiles
	for layer_name in ["bg", "solid", "fg"]:
		if not routed_layers.has(layer_name) or not tilemaps.has(layer_name) or tilemaps[layer_name] == null:
			continue
		var tilemap: TileMap = tilemaps[layer_name]
		var cells: Array = routed_layers[layer_name]
		for cell_data in cells:
			if cell_data is Array and cell_data.size() == 4:
				var x: int = int(cell_data[0])
				var y: int = int(cell_data[1])
				var ax: int = int(cell_data[2])
				var ay: int = int(cell_data[3])
				tilemap.set_cell(0, Vector2i(x, y), 0, Vector2i(ax, ay))

	# Apply boundary
	if tilemaps.has("solid") and tilemaps["solid"] != null:
		apply_boundary(tilemaps["solid"], w, h)

	return meta

## Sparse save format: only stores placed tiles, not empty cells.
## Boundary tiles are NOT saved; they are generated on load.
static func save_map_to_json(path: String, width: int, height: int, tileset_name: String, tilemaps: Dictionary, entities: Array = []) -> Error:
	var json_str := build_map_json_string(width, height, tileset_name, tilemaps, entities)
	if json_str.strip_edges() == "":
		push_error("Refusing to save invalid/empty map JSON: " + path)
		return ERR_INVALID_DATA
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Failed to save map: " + path)
		return FileAccess.get_open_error()
	
	file.store_string(json_str)
	file.close()
	return OK


## Build the map JSON string (useful for clipboard/copy-paste).
static func build_map_json_string(width: int, height: int, tileset_name: String, tilemaps: Dictionary, entities: Array = []) -> String:
	var data := build_map_data(width, height, tileset_name, tilemaps, entities)
	var validated := DriftMap.validate_and_canonicalize(data)
	if not bool(validated.get("ok", false)):
		push_error("Map build produced invalid data")
		for e in (validated.get("errors", []) as Array):
			push_error(" - " + String(e))
		return ""
	return DriftMap.canonical_json_string(validated.get("map", {}))


## Build the full map data dictionary (meta + layers).
static func build_map_data(width: int, height: int, tileset_name: String, tilemaps: Dictionary, entities: Array = []) -> Dictionary:
	var layers := {}

	for layer_name in ["bg", "solid", "fg"]:
		if not tilemaps.has(layer_name):
			continue
		var tilemap: TileMap = tilemaps[layer_name]
		var cells := []

		# Iterate used cells, skip boundary cells (not saved)
		for cell in tilemap.get_used_cells(0):
			var x: int = cell.x
			var y: int = cell.y
			# Skip boundary (will be regenerated)
			if x == 0 or y == 0 or x == width - 1 or y == height - 1:
				continue
			var atlas_coords := tilemap.get_cell_atlas_coords(0, cell)
			if atlas_coords != Vector2i(-1, -1):
				cells.append([x, y, atlas_coords.x, atlas_coords.y])

		layers[layer_name] = cells

	return {
		"format": "driftline.map",
		"schema_version": 1,
		"meta": {
			"w": width,
			"h": height,
			"tile_size": TILE_SIZE,
			"tileset": tileset_name,
		},
		"layers": layers,
		"entities": entities
	}


static func count_tiles(map_data: Dictionary) -> int:
	var validated := DriftMap.validate_and_canonicalize(map_data)
	if not bool(validated.get("ok", false)):
		return 0
	var canonical: Dictionary = validated.get("map", {})
	var layers: Dictionary = canonical.get("layers", {})
	var count: int = 0
	for layer_name in ["bg", "solid", "fg"]:
		var arr = layers.get(layer_name, [])
		if arr is Array:
			count += (arr as Array).size()
	return count


static func validate_entities(entities: Array, width: int, height: int) -> Array[String]:
	var issues: Array[String] = []
	for i in range(entities.size()):
		var e = entities[i]
		if typeof(e) != TYPE_DICTIONARY:
			issues.append("entities[%d] is not an object" % i)
			continue
		var d: Dictionary = e
		var t: String = String(d.get("type", ""))
		if t not in ["spawn", "flag", "base"]:
			issues.append("entities[%d] has invalid type '%s'" % [i, t])
		var x: int = int(d.get("x", -1))
		var y: int = int(d.get("y", -1))
		if x < 0 or y < 0 or x >= width or y >= height:
			issues.append("entities[%d] out of bounds (%d,%d)" % [i, x, y])
	return issues


## Read the raw map JSON as a Dictionary (meta + layers) without applying to TileMaps.
static func read_map_data(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to load map: " + path)
		return {}

	var json_str := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(json_str)
	if parse_result != OK:
		push_error("Failed to parse map JSON: " + path)
		return {}

	var data: Dictionary = json.data
	return data


## Load map from JSON and apply to TileMaps, then stamp boundary.
static func load_map_from_json(path: String, tilemaps: Dictionary) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to load map: " + path)
		return {}
	
	var json_str := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var parse_result := json.parse(json_str)
	if parse_result != OK:
		push_error("Failed to parse map JSON: " + path)
		return {}
	
	var data: Dictionary = json.data
	var validated := DriftMap.validate_and_canonicalize(data)
	if not bool(validated.get("ok", false)):
		push_error("Map validation failed: " + path)
		for e in (validated.get("errors", []) as Array):
			push_error(" - " + String(e))
		return {}
	var canonical: Dictionary = validated.get("map", {})
	var meta: Dictionary = canonical.get("meta", {})
	var layers: Dictionary = canonical.get("layers", {})
	var w: int = int(meta.get("w", 0))
	var h: int = int(meta.get("h", 0))
	var tileset_name: String = String(meta.get("tileset", "")).strip_edges()
	if tileset_name == "":
		push_error("Map meta.tileset is required (empty): " + path)
		return {}
	var tileset_def := DriftTileDefs.load_tileset(tileset_name)
	if not bool(tileset_def.get("ok", false)):
		push_warning("[TILES] " + String(tileset_def.get("error", "Failed to load tiles_def")))
	var routed_layers: Dictionary = DriftTileDefs.build_render_layers({"layers": layers}, tileset_def)
	
	# Clear all layers
	for layer_name in ["bg", "solid", "fg"]:
		if tilemaps.has(layer_name):
			tilemaps[layer_name].clear()
	
	# Apply loaded tiles
	for layer_name in ["bg", "solid", "fg"]:
		if not routed_layers.has(layer_name) or not tilemaps.has(layer_name):
			continue
		var tilemap: TileMap = tilemaps[layer_name]
		var cells: Array = routed_layers[layer_name]
		
		for cell_data in cells:
			if cell_data.size() != 4:
				continue
			var x: int = cell_data[0]
			var y: int = cell_data[1]
			var ax: int = cell_data[2]
			var ay: int = cell_data[3]
			tilemap.set_cell(0, Vector2i(x, y), 0, Vector2i(ax, ay))
	
	# Apply boundary
	if tilemaps.has("solid"):
		apply_boundary(tilemaps["solid"], w, h)
	
	return meta


## Load only map metadata (width/height/tileset/etc) without applying tiles.
static func load_map_meta(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to load map: " + path)
		return {}

	var json_str := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(json_str)
	if parse_result != OK:
		push_error("Failed to parse map JSON: " + path)
		return {}

	var data: Dictionary = json.data
	var validated := DriftMap.validate_and_canonicalize(data)
	if not bool(validated.get("ok", false)):
		push_error("Map validation failed: " + path)
		for e in (validated.get("errors", []) as Array):
			push_error(" - " + String(e))
		return {}
	var canonical: Dictionary = validated.get("map", {})
	var meta: Dictionary = canonical.get("meta", {}).duplicate(true)
	meta["width"] = int(meta.get("w", 0)) * TILE_SIZE
	meta["height"] = int(meta.get("h", 0)) * TILE_SIZE
	return meta


## Stamp immutable boundary tiles on TileMapSolid.
## Corners: TL(17,0), TR(18,0), BL(18,2), BR(17,2)
## Edges: horizontal(1,0), vertical(1,2)
static func apply_boundary(tilemap_solid: TileMap, width: int, height: int) -> void:
	# Corners
	tilemap_solid.set_cell(0, Vector2i(0, 0), 0, Vector2i(17, 0))           # TL
	tilemap_solid.set_cell(0, Vector2i(width - 1, 0), 0, Vector2i(18, 0))   # TR
	tilemap_solid.set_cell(0, Vector2i(0, height - 1), 0, Vector2i(18, 2))  # BL
	tilemap_solid.set_cell(0, Vector2i(width - 1, height - 1), 0, Vector2i(17, 2))  # BR
	
	# Top/bottom edges (horizontal wall 1,0)
	for x in range(1, width - 1):
		tilemap_solid.set_cell(0, Vector2i(x, 0), 0, Vector2i(1, 0))
		tilemap_solid.set_cell(0, Vector2i(x, height - 1), 0, Vector2i(1, 0))
	
	# Left/right edges (vertical wall 1,2)
	for y in range(1, height - 1):
		tilemap_solid.set_cell(0, Vector2i(0, y), 0, Vector2i(1, 2))
		tilemap_solid.set_cell(0, Vector2i(width - 1, y), 0, Vector2i(1, 2))
