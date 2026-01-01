## TilesetData
##
## Holds a tileset package loaded from res://assets/tilesets/<name>/.
##
## Invariants:
## - Tile metadata is indexed by atlas key "x,y".
## - Missing tiles use `defaults`.
## - Overrides should stay small: fields that match defaults are omitted.
## - Unknown top-level keys in manifest/defs are preserved when saving.

class_name TilesetData
extends RefCounted

const DEFAULT_TILE_SIZE := Vector2i(16, 16)
const DEFAULT_LAYER := "mid" # bg|mid|fg
const DEFAULT_SOLID := false

var dir_path: String = "" # res://... package directory
var name: String = ""      # folder name / manifest name

var texture: Texture2D = null
var tile_size: Vector2i = DEFAULT_TILE_SIZE

# Where the image should be written within the package (usually "tiles.png").
var image_rel_path: String = "tiles.png"

# If imported from outside the project, this helps save_tileset() copy the source PNG.
var source_image_abs_path: String = ""

# Raw JSON objects as loaded (to preserve unknown keys).
var manifest_raw: Dictionary = {}
var defs_raw: Dictionary = {}

# Non-fatal warnings surfaced by IO/validation.
var warnings: Array[String] = []


func get_defaults() -> Dictionary:
	var defaults: Dictionary = defs_raw.get("defaults", {})
	if defaults.is_empty():
		defaults = {"layer": DEFAULT_LAYER, "solid": DEFAULT_SOLID}
	return defaults


func get_tiles_dict() -> Dictionary:
	var tiles: Dictionary = defs_raw.get("tiles", {})
	if tiles.is_empty():
		# Ensure the backing dict exists for mutation.
		defs_raw["tiles"] = {}
		tiles = defs_raw["tiles"]
	return tiles


func get_tile_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


func get_tile_override(x: int, y: int) -> Dictionary:
	var tiles := get_tiles_dict()
	var key := get_tile_key(x, y)
	var v = tiles.get(key, {})
	return v if (v is Dictionary) else {}


func get_tile_effective(x: int, y: int) -> Dictionary:
	var out: Dictionary = {}
	var defaults := get_defaults()
	for k in defaults.keys():
		out[k] = defaults[k]
	var o := get_tile_override(x, y)
	for k2 in o.keys():
		out[k2] = o[k2]
	return out


func set_tile_override(x: int, y: int, patch: Dictionary) -> void:
	var tiles := get_tiles_dict()
	var key := get_tile_key(x, y)
	var existing: Dictionary = get_tile_override(x, y)
	var merged: Dictionary = existing.duplicate(true)
	for k in patch.keys():
		merged[k] = patch[k]

	merged = _normalize_override(merged)
	if merged.is_empty():
		tiles.erase(key)
	else:
		tiles[key] = merged


func clear_tile_override(x: int, y: int) -> void:
	var tiles := get_tiles_dict()
	var key := get_tile_key(x, y)
	if tiles.has(key):
		tiles.erase(key)


func has_override(x: int, y: int) -> bool:
	var tiles := get_tiles_dict()
	return tiles.has(get_tile_key(x, y))


func get_reserved_door_frames() -> PackedStringArray:
	var reserved: Dictionary = defs_raw.get("reserved", {})
	if not reserved.has("doors") or not (reserved["doors"] is Dictionary):
		return PackedStringArray()
	var doors: Dictionary = reserved["doors"]
	var frames = doors.get("frames", [])
	if frames is Array:
		var out := PackedStringArray()
		for s in frames:
			out.append(String(s))
		return out
	return PackedStringArray()


func _normalize_override(o: Dictionary) -> Dictionary:
	# Keep unknown keys, but normalize common optional fields to keep JSON small.
	var defaults := get_defaults()

	# Trim empty strings.
	for k in ["name", "tags"]:
		if o.has(k) and String(o[k]).strip_edges() == "":
			o.erase(k)

	# Normalize tags: allow string or array; keep array in JSON.
	if o.has("tags"):
		if o["tags"] is String:
			var parts := (String(o["tags"]).split(",", false))
			var tags_arr: Array = []
			for p in parts:
				var t := String(p).strip_edges()
				if t != "":
					tags_arr.append(t)
			o["tags"] = tags_arr

	# Remove keys equal to defaults for known fields.
	for k2 in ["layer", "solid"]:
		if o.has(k2) and defaults.has(k2) and o[k2] == defaults[k2]:
			o.erase(k2)

	return o
