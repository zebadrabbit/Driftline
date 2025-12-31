extends Node

## Centralized map save/load and TileMap application utilities.
## Handles sparse JSON format and boundary stamping.

const TILE_SIZE := 16

## Sparse save format: only stores placed tiles, not empty cells.
## Boundary tiles are NOT saved; they are generated on load.
static func save_map_to_json(path: String, width: int, height: int, tileset_name: String, tilemaps: Dictionary) -> Error:
	var json_str := build_map_json_string(width, height, tileset_name, tilemaps)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Failed to save map: " + path)
		return FileAccess.get_open_error()
	
	file.store_string(json_str)
	file.close()
	return OK


## Build the map JSON string (useful for clipboard/copy-paste).
static func build_map_json_string(width: int, height: int, tileset_name: String, tilemaps: Dictionary) -> String:
	var data := build_map_data(width, height, tileset_name, tilemaps)
	return JSON.stringify(data, "\t")


## Build the full map data dictionary (meta + layers).
static func build_map_data(width: int, height: int, tileset_name: String, tilemaps: Dictionary) -> Dictionary:
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
		"layers": layers
	}


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
	
	var meta: Dictionary = data["meta"]
	var layers: Dictionary = data["layers"]
	# Backward compatible width/height lookup.
	# Root width/height are pixels. meta.w/meta.h are tiles.
	var w_px: int = int(data.get("width", int(meta.get("w", 64)) * TILE_SIZE))
	var h_px: int = int(data.get("height", int(meta.get("h", 64)) * TILE_SIZE))
	if w_px <= 0:
		w_px = 1024
	if h_px <= 0:
		h_px = 1024
	var w: int = int(meta.get("w", w_px / TILE_SIZE))
	var h: int = int(meta.get("h", h_px / TILE_SIZE))
	meta["w"] = w
	meta["h"] = h
	meta["width"] = w_px
	meta["height"] = h_px
	
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
	var meta: Dictionary = {}
	if data.has("meta"):
		meta = data["meta"]

	var w_px: int = int(data.get("width", int(meta.get("w", 64)) * TILE_SIZE))
	var h_px: int = int(data.get("height", int(meta.get("h", 64)) * TILE_SIZE))
	if w_px <= 0:
		w_px = 1024
	if h_px <= 0:
		h_px = 1024
	var w: int = int(meta.get("w", w_px / TILE_SIZE))
	var h: int = int(meta.get("h", h_px / TILE_SIZE))
	meta["w"] = w
	meta["h"] = h
	meta["width"] = w_px
	meta["height"] = h_px
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
