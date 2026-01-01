## Tileset per-tile metadata authoring (editor-only).
##
## File format (per tileset):
## {
##   "tileset_id": "subspace_base",
##   "tile_size": [16,16],
##   "tiles": {
##     "x,y": { "layer":"mid", "solid":true, "restitution":0.85, "friction":0.1 }
##   }
## }

# TODO: Door/animated tiles: add authoring support and per-frame behavior. Not implemented yet.

extends RefCounted
class_name TilesetMeta

const DEFAULT_LAYER: String = "mid" # bg|mid|fg
const DEFAULT_SOLID: bool = false
const DEFAULT_RESTITUTION: float = 0.0
const DEFAULT_FRICTION: float = 0.0

var tileset_id: String = ""
var tile_size: Vector2i = Vector2i(16, 16)
var tiles: Dictionary = {} # "ax,ay" -> Dictionary
var path: String = ""


func load(p: String) -> bool:
	path = p
	tileset_id = ""
	tile_size = Vector2i(16, 16)
	tiles = {}

	if not FileAccess.file_exists(p):
		# Missing file is not fatal; keep defaults.
		return true

	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		push_warning("[TILEMETA] Failed to open: " + p)
		return false

	var s := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(s)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[TILEMETA] Invalid JSON (must be object): " + p)
		return false

	var root: Dictionary = parsed
	tileset_id = String(root.get("tileset_id", ""))
	var ts = root.get("tile_size", [16, 16])
	if ts is Array and (ts as Array).size() >= 2:
		tile_size = Vector2i(int(ts[0]), int(ts[1]))
	var t = root.get("tiles", {})
	if t is Dictionary:
		tiles = t
	return true


func save(p: String = "") -> bool:
	var out_path := p
	if out_path.strip_edges() == "":
		out_path = path
	if out_path.strip_edges() == "":
		push_warning("[TILEMETA] save() missing path")
		return false

	var root := {
		"tileset_id": tileset_id,
		"tile_size": [tile_size.x, tile_size.y],
		"tiles": tiles,
	}

	var json_str := JSON.stringify(root, "\t")
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_warning("[TILEMETA] Failed to open for write: " + out_path)
		return false
	f.store_string(json_str)
	f.close()
	return true


func get_meta(atlas: Vector2i) -> Dictionary:
	var key := "%d,%d" % [atlas.x, atlas.y]
	var base := {
		"layer": DEFAULT_LAYER,
		"solid": DEFAULT_SOLID,
		"restitution": DEFAULT_RESTITUTION,
		"friction": DEFAULT_FRICTION,
	}
	if tiles.has(key) and tiles[key] is Dictionary:
		var t: Dictionary = tiles[key]
		for k in t.keys():
			base[k] = t[k]
	base["layer"] = _sanitize_layer(String(base.get("layer", DEFAULT_LAYER)))
	base["solid"] = bool(base.get("solid", DEFAULT_SOLID))
	base["restitution"] = clampf(float(base.get("restitution", DEFAULT_RESTITUTION)), 0.0, 1.2)
	base["friction"] = clampf(float(base.get("friction", DEFAULT_FRICTION)), 0.0, 1.0)
	return base


func set_meta(atlas: Vector2i, patch: Dictionary) -> void:
	var key := "%d,%d" % [atlas.x, atlas.y]
	var cur := get_meta(atlas)
	for k in patch.keys():
		cur[k] = patch[k]

	cur["layer"] = _sanitize_layer(String(cur.get("layer", DEFAULT_LAYER)))
	cur["solid"] = bool(cur.get("solid", DEFAULT_SOLID))
	cur["restitution"] = clampf(float(cur.get("restitution", DEFAULT_RESTITUTION)), 0.0, 1.2)
	cur["friction"] = clampf(float(cur.get("friction", DEFAULT_FRICTION)), 0.0, 1.0)

	# Store only deltas vs defaults to keep the JSON compact.
	var stored: Dictionary = {}
	if String(cur["layer"]) != DEFAULT_LAYER:
		stored["layer"] = String(cur["layer"])
	if bool(cur["solid"]) != DEFAULT_SOLID:
		stored["solid"] = bool(cur["solid"])
	if absf(float(cur["restitution"]) - DEFAULT_RESTITUTION) > 0.00001:
		stored["restitution"] = float(cur["restitution"])
	if absf(float(cur["friction"]) - DEFAULT_FRICTION) > 0.00001:
		stored["friction"] = float(cur["friction"])

	if stored.is_empty():
		tiles.erase(key)
	else:
		tiles[key] = stored


func _sanitize_layer(layer: String) -> String:
	var l := layer.strip_edges().to_lower()
	if l not in ["bg", "mid", "fg"]:
		l = DEFAULT_LAYER
	return l
