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

var defaults: Dictionary = {
	"layer": DEFAULT_LAYER,
	"solid": DEFAULT_SOLID,
	"restitution": DEFAULT_RESTITUTION,
	"friction": DEFAULT_FRICTION,
}

var _use_defs_schema: bool = false
var _root_raw: Dictionary = {}

var tileset_id: String = ""
var tile_size: Vector2i = Vector2i(16, 16)
var tiles: Dictionary = {} # "ax,ay" -> Dictionary
var path: String = ""


func load(p: String) -> bool:
	path = p
	tileset_id = ""
	tile_size = Vector2i(16, 16)
	tiles = {}
	defaults = {
		"layer": DEFAULT_LAYER,
		"solid": DEFAULT_SOLID,
		"restitution": DEFAULT_RESTITUTION,
		"friction": DEFAULT_FRICTION,
	}
	_use_defs_schema = p.replace("\\", "/").get_file().to_lower() == "tiles_def.json"
	_root_raw = {}

	if not FileAccess.file_exists(p):
		# Missing file is not fatal; keep defaults.
		if _use_defs_schema:
			_root_raw = {
				"version": 1,
				"defaults": defaults.duplicate(true),
				"tiles": {},
			}
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
	_root_raw = root.duplicate(true)

	# Auto-detect schema.
	_use_defs_schema = _use_defs_schema or root.has("version") or root.has("defaults")

	if _use_defs_schema:
		# tiles_def.json-like schema:
		# { version, defaults:{...}, tiles:{"x,y":{...}}, reserved:{...} }
		var d = root.get("defaults", {})
		if d is Dictionary:
			defaults = defaults.duplicate(true)
			for k in (d as Dictionary).keys():
				defaults[k] = (d as Dictionary)[k]
		defaults["layer"] = _sanitize_layer(String(defaults.get("layer", DEFAULT_LAYER)))
		defaults["solid"] = bool(defaults.get("solid", DEFAULT_SOLID))
		defaults["restitution"] = clampf(float(defaults.get("restitution", DEFAULT_RESTITUTION)), 0.0, 1.2)
		defaults["friction"] = clampf(float(defaults.get("friction", DEFAULT_FRICTION)), 0.0, 1.0)
		var t = root.get("tiles", {})
		if t is Dictionary:
			tiles = t
		return true

	# Legacy tiles_meta.json schema.
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

	var root: Dictionary = {}
	if _use_defs_schema:
		root = _root_raw.duplicate(true)
		root["version"] = int(root.get("version", 1))
		root["defaults"] = defaults.duplicate(true)
		root["tiles"] = tiles
	else:
		root = {
			"tileset_id": tileset_id,
			"tile_size": [tile_size.x, tile_size.y],
			"tiles": tiles,
		}

	# Stable, diff-friendly JSON.
	var json_str := JSON.stringify(_sort_any(root, _use_defs_schema), "  ") + "\n"
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_warning("[TILEMETA] Failed to open for write: " + out_path)
		return false
	f.store_string(json_str)
	f.close()
	return true


func get_tile_meta(atlas: Vector2i) -> Dictionary:
	var key := "%d,%d" % [atlas.x, atlas.y]
	var base := defaults.duplicate(true)
	if tiles.has(key) and tiles[key] is Dictionary:
		var t: Dictionary = tiles[key]
		for k in t.keys():
			base[k] = t[k]
	base["layer"] = _sanitize_layer(String(base.get("layer", DEFAULT_LAYER)))
	base["solid"] = bool(base.get("solid", DEFAULT_SOLID))
	base["restitution"] = clampf(float(base.get("restitution", DEFAULT_RESTITUTION)), 0.0, 1.2)
	base["friction"] = clampf(float(base.get("friction", DEFAULT_FRICTION)), 0.0, 1.0)
	return base


func set_tile_meta(atlas: Vector2i, patch: Dictionary) -> void:
	var key := "%d,%d" % [atlas.x, atlas.y]
	var cur := get_tile_meta(atlas)
	for k in patch.keys():
		cur[k] = patch[k]

	cur["layer"] = _sanitize_layer(String(cur.get("layer", DEFAULT_LAYER)))
	cur["solid"] = bool(cur.get("solid", DEFAULT_SOLID))
	cur["restitution"] = clampf(float(cur.get("restitution", DEFAULT_RESTITUTION)), 0.0, 1.2)
	cur["friction"] = clampf(float(cur.get("friction", DEFAULT_FRICTION)), 0.0, 1.0)

	# Store only deltas vs defaults to keep the JSON compact.
	var stored: Dictionary = {}
	if String(cur["layer"]) != String(defaults.get("layer", DEFAULT_LAYER)):
		stored["layer"] = String(cur["layer"])
	if bool(cur["solid"]) != bool(defaults.get("solid", DEFAULT_SOLID)):
		stored["solid"] = bool(cur["solid"])
	if absf(float(cur["restitution"]) - float(defaults.get("restitution", DEFAULT_RESTITUTION))) > 0.00001:
		stored["restitution"] = float(cur["restitution"])
	if absf(float(cur["friction"]) - float(defaults.get("friction", DEFAULT_FRICTION))) > 0.00001:
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


func _sort_any(v: Variant, sort_tiles: bool) -> Variant:
	if v is Dictionary:
		var dict_in: Dictionary = v
		var keys := dict_in.keys()
		keys.sort()
		var out: Dictionary = {}
		for k in keys:
			if sort_tiles and String(k) == "tiles" and dict_in[k] is Dictionary:
				out[k] = _sort_tile_key_dict(dict_in[k])
			else:
				out[k] = _sort_any(dict_in[k], sort_tiles)
		return out
	if v is Array:
		var arr_in: Array = v
		var out_arr: Array = []
		out_arr.resize(arr_in.size())
		for i in range(arr_in.size()):
			out_arr[i] = _sort_any(arr_in[i], sort_tiles)
		return out_arr
	return v


func _sort_tile_key_dict(tiles_dict: Dictionary) -> Dictionary:
	var keys := tiles_dict.keys()
	keys.sort_custom(func(a, b):
		var sa := String(a)
		var sb := String(b)
		var pa := sa.split(",")
		var pb := sb.split(",")
		if pa.size() == 2 and pb.size() == 2:
			var ax := int(pa[0])
			var ay := int(pa[1])
			var bx := int(pb[0])
			var by := int(pb[1])
			if ax != bx:
				return ax < bx
			return ay < by
		return sa < sb
	)
	var out: Dictionary = {}
	for k in keys:
		out[String(k)] = _sort_any(tiles_dict[k], false)
	return out
