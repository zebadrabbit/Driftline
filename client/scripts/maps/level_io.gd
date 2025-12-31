extends Node

## Centralized map save/load and TileMap application utilities.
## Handles sparse JSON format and boundary stamping.

const TILE_SIZE := 16

const DEFAULT_WIDTH_TILES: int = 64
const DEFAULT_HEIGHT_TILES: int = 64


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


## Normalize raw map data for backward/forward compatibility.
## Ensures:
## - meta exists and has w/h (tile counts)
## - layers exists with bg/solid/fg arrays
## - entities exists as an array
## Returns a normalized Dictionary (map object).
static func normalize_map_data(data: Dictionary) -> Dictionary:
	var out: Dictionary = {}

	# Preserve top-level fields.
	for k in data.keys():
		out[k] = data[k]

	var meta: Dictionary = {}
	if out.has("meta") and out["meta"] is Dictionary:
		meta = out["meta"]
	else:
		meta = {}
		out["meta"] = meta

	# Determine width/height (tile counts). Accept legacy root width/height that may be pixels.
	var w_tiles: int = int(meta.get("w", 0))
	var h_tiles: int = int(meta.get("h", 0))
	if w_tiles <= 0:
		var w_raw: int = int(out.get("width", 0))
		if w_raw > 0:
			# Heuristic: if it looks like pixels (large and divisible), convert.
			w_tiles = int(w_raw / TILE_SIZE) if (w_raw >= 256 and w_raw % TILE_SIZE == 0) else w_raw
		else:
			w_tiles = DEFAULT_WIDTH_TILES
	if h_tiles <= 0:
		var h_raw: int = int(out.get("height", 0))
		if h_raw > 0:
			h_tiles = int(h_raw / TILE_SIZE) if (h_raw >= 256 and h_raw % TILE_SIZE == 0) else h_raw
		else:
			h_tiles = DEFAULT_HEIGHT_TILES

	meta["w"] = w_tiles
	meta["h"] = h_tiles
	meta["tile_size"] = int(meta.get("tile_size", TILE_SIZE))
	# Keep root width/height present for tools that expect them (store pixels).
	out["width"] = int(out.get("width", w_tiles * TILE_SIZE))
	out["height"] = int(out.get("height", h_tiles * TILE_SIZE))

	# Layers
	var layers: Dictionary = {}
	if out.has("layers") and out["layers"] is Dictionary:
		layers = out["layers"]
	else:
		layers = {}
		out["layers"] = layers

	for layer_name in ["bg", "solid", "fg"]:
		if not layers.has(layer_name) or not (layers[layer_name] is Array):
			layers[layer_name] = []

	# Entities (Part 2)
	if not out.has("entities") or not (out["entities"] is Array):
		out["entities"] = []

	return out


## Apply a pre-parsed map data Dictionary to TileMaps.
## Returns normalized meta (contains w/h).
static func apply_map_data(map_data: Dictionary, tilemaps: Dictionary) -> Dictionary:
	var norm := normalize_map_data(map_data)
	var meta: Dictionary = norm.get("meta", {})
	var layers: Dictionary = norm.get("layers", {})
	var w: int = int(meta.get("w", DEFAULT_WIDTH_TILES))
	var h: int = int(meta.get("h", DEFAULT_HEIGHT_TILES))

	# Clear all layers
	for layer_name in ["bg", "solid", "fg"]:
		if tilemaps.has(layer_name) and tilemaps[layer_name] != null:
			(tilemaps[layer_name] as TileMap).clear()

	# Apply loaded tiles
	for layer_name in ["bg", "solid", "fg"]:
		if not layers.has(layer_name) or not tilemaps.has(layer_name) or tilemaps[layer_name] == null:
			continue
		var tilemap: TileMap = tilemaps[layer_name]
		var cells: Array = layers[layer_name]
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
	return JSON.stringify(data, "\t")


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
		# Pixel dimensions for UI/editor convenience.
		"width": width * TILE_SIZE,
		"height": height * TILE_SIZE,
		"meta": {
			"w": width,
			"h": height,
			"tile_size": TILE_SIZE,
			"tileset": tileset_name
		},
		"layers": layers,
		"entities": entities
	}


static func count_tiles(map_data: Dictionary) -> int:
	var norm := normalize_map_data(map_data)
	var layers: Dictionary = norm.get("layers", {})
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
	if not data.has("meta") or not data.has("layers"):
		push_error("Invalid map format: " + path)
		return {}

	var norm := normalize_map_data(data)
	var meta: Dictionary = norm["meta"]
	var layers: Dictionary = norm["layers"]
	var w: int = int(meta.get("w", DEFAULT_WIDTH_TILES))
	var h: int = int(meta.get("h", DEFAULT_HEIGHT_TILES))
	
	# Clear all layers
	for layer_name in ["bg", "solid", "fg"]:
		if tilemaps.has(layer_name):
			tilemaps[layer_name].clear()
	
	# Apply loaded tiles
	for layer_name in ["bg", "solid", "fg"]:
		if not layers.has(layer_name) or not tilemaps.has(layer_name):
			continue
		var tilemap: TileMap = tilemaps[layer_name]
		var cells: Array = layers[layer_name]
		
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
		return {"width": 1024, "height": 1024, "w": 64, "h": 64}

	var json_str := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(json_str)
	if parse_result != OK:
		push_error("Failed to parse map JSON: " + path)
		return {"width": 1024, "height": 1024, "w": 64, "h": 64}

	var data: Dictionary = json.data
	var norm := normalize_map_data(data)
	var meta: Dictionary = norm.get("meta", {})
	meta["width"] = int(norm.get("width", int(meta.get("w", DEFAULT_WIDTH_TILES)) * TILE_SIZE))
	meta["height"] = int(norm.get("height", int(meta.get("h", DEFAULT_HEIGHT_TILES)) * TILE_SIZE))
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
