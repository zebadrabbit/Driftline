## TilesetIO
##
## Loads/saves tileset packages at res://assets/tilesets/<tileset_name>/.
##
## Requirements:
## - Stable, diff-friendly JSON: keys are sorted and pretty-printed.
## - Unknown formats/schema versions fail loudly.

class_name TilesetIO
extends Node

const TilesetData = preload("res://shared/tileset/tileset_data.gd")
const DriftValidate = preload("res://shared/drift_validate.gd")

const ASSETS_TILESETS_DIR := "res://assets/tilesets"


static func list_tileset_packages() -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(ASSETS_TILESETS_DIR)):
		return out
	var dir := DirAccess.open(ASSETS_TILESETS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if name.begins_with("."):
			continue
		if dir.current_is_dir():
			out.append(name)
	dir.list_dir_end()
	out.sort()
	return out


static func load_tileset(dir_path: String) -> Dictionary:
	# Returns: { ok: bool, error: String, warnings: Array[String], data: TilesetData }
	var result := {"ok": false, "error": "", "warnings": [], "data": null}
	var warnings: Array[String] = []

	var data := TilesetData.new()
	data.dir_path = dir_path
	data.name = _infer_name_from_dir(dir_path)

	# Manifest (tileset.json)
	var manifest_path := _path_join(dir_path, "tileset.json")
	if not FileAccess.file_exists(manifest_path):
		result["error"] = "tileset.json missing: " + manifest_path
		result["data"] = data
		return result
	var manifest_raw := _read_json_dict(manifest_path)
	if manifest_raw.is_empty():
		result["error"] = "tileset.json invalid or empty: " + manifest_path
		result["data"] = data
		return result
	var manifest_valid := DriftValidate.validate_tileset_manifest(manifest_raw)
	if not bool(manifest_valid.get("ok", false)):
		var err_text := "tileset.json validation failed: " + manifest_path
		for e in (manifest_valid.get("errors", []) as Array):
			err_text += "\n - " + String(e)
		result["error"] = err_text
		result["data"] = data
		result["warnings"] = manifest_valid.get("warnings", [])
		return result
	data.manifest_raw = (manifest_valid.get("manifest", {}) as Dictionary).duplicate(true)
	data.name = String(data.manifest_raw.get("name", data.name))
	data.image_rel_path = String(data.manifest_raw.get("image", "tiles.png"))
	data.tile_size = _parse_tile_size(data.manifest_raw.get("tile_size", [16, 16]))

	# Image
	var image_path := _path_join(dir_path, data.image_rel_path)
	data.texture = _load_texture(image_path)
	if data.texture == null:
		result["error"] = "tileset image missing or not loadable: " + image_path
		result["data"] = data
		return result

	# Defs (tiles_def.json)
	var defs_path := _path_join(dir_path, "tiles_def.json")
	if not FileAccess.file_exists(defs_path):
		result["error"] = "tiles_def.json missing: " + defs_path
		result["data"] = data
		return result
	var defs_raw := _read_json_dict(defs_path)
	if defs_raw.is_empty():
		result["error"] = "tiles_def.json invalid or empty: " + defs_path
		result["data"] = data
		return result
	var defs_valid := DriftValidate.validate_tiles_def(defs_raw)
	if not bool(defs_valid.get("ok", false)):
		var err_text2 := "tiles_def.json validation failed: " + defs_path
		for e2 in (defs_valid.get("errors", []) as Array):
			err_text2 += "\n - " + String(e2)
		result["error"] = err_text2
		result["data"] = data
		result["warnings"] = defs_valid.get("warnings", [])
		return result
	data.defs_raw = (defs_valid.get("tiles_def", {}) as Dictionary).duplicate(true)

	# Extra validation: ensure tile keys are within the image atlas.
	var sz := data.texture.get_size()
	if int(sz.x) % data.tile_size.x != 0 or int(sz.y) % data.tile_size.y != 0:
		result["error"] = "tileset image size not divisible by tile_size: " + image_path
		result["data"] = data
		return result
	var cols := maxi(1, int(floor(sz.x / float(data.tile_size.x))))
	var rows := maxi(1, int(floor(sz.y / float(data.tile_size.y))))
	var bad := _count_defs_out_of_bounds((data.defs_raw.get("tiles", {}) as Dictionary), cols, rows)
	if bad > 0:
		result["error"] = "tiles_def.json contains %d out-of-bounds tile key(s)" % bad
		result["data"] = data
		return result

	result["ok"] = true
	result["data"] = data
	result["warnings"] = warnings
	return result


static func _count_defs_out_of_bounds(tiles: Dictionary, cols: int, rows: int) -> int:
	var bad := 0
	for k in tiles.keys():
		var parts := String(k).split(",")
		if parts.size() != 2:
			continue
		var x := int(parts[0])
		var y := int(parts[1])
		if x < 0 or y < 0 or x >= cols or y >= rows:
			bad += 1
	return bad


static func load_tileset_by_name(tileset_name: String) -> Dictionary:
	return load_tileset(_path_join(ASSETS_TILESETS_DIR, tileset_name))


static func new_from_png(abs_png_path: String, tileset_name: String = "") -> TilesetData:
	var data := TilesetData.new()
	data.source_image_abs_path = abs_png_path
	data.name = tileset_name if tileset_name.strip_edges() != "" else _infer_name_from_file(abs_png_path)
	data.dir_path = ""
	data.image_rel_path = "tiles.png"
	data.tile_size = Vector2i(16, 16)
	data.manifest_raw = {
		"format": DriftValidate.FORMAT_TILESET_MANIFEST,
		"schema_version": DriftValidate.SCHEMA_TILESET_MANIFEST,
		"name": data.name,
		"image": "tiles.png",
		"tile_size": [16, 16],
	}
	data.defs_raw = {
		"format": DriftValidate.FORMAT_TILES_DEF,
		"schema_version": DriftValidate.SCHEMA_TILES_DEF,
		"defaults": {"layer": "mid", "solid": false},
		"tiles": {},
		"reserved": {
			"doors": {
				"comment": "Door frames behave like animated frames; coords fixed across tilesets.",
					"frames": ["9,8", "10,8", "11,8", "12,8", "13,8", "14,8", "15,8", "16,8"],
				"solid_when_closed": true
			}
		}
	}

	data.texture = _load_texture_from_abs(abs_png_path)
	return data


static func save_tileset(dir_path: String, data: TilesetData) -> Dictionary:
	# Returns { ok, error, warnings:[] }
	var result := {"ok": false, "error": "", "warnings": []}
	if dir_path.strip_edges() == "":
		result["error"] = "Missing tileset directory path"
		return result

	_ensure_dir(dir_path)

	# Canonical manifest (strict contract).
	var manifest_out := {
		"format": DriftValidate.FORMAT_TILESET_MANIFEST,
		"schema_version": DriftValidate.SCHEMA_TILESET_MANIFEST,
		"name": data.name,
		"image": data.image_rel_path,
		"tile_size": [data.tile_size.x, data.tile_size.y],
	}
	var manifest_valid := DriftValidate.validate_tileset_manifest(manifest_out)
	if not bool(manifest_valid.get("ok", false)):
		var err_text := "Refusing to save invalid tileset manifest"
		for e in (manifest_valid.get("errors", []) as Array):
			err_text += "\n - " + String(e)
		result["error"] = err_text
		return result
	manifest_out = manifest_valid.get("manifest", {})

	# Canonical defs (strict contract).
	var defs_valid := DriftValidate.validate_tiles_def(data.defs_raw)
	if not bool(defs_valid.get("ok", false)):
		var err_text2 := "Refusing to save invalid tiles_def"
		for e2 in (defs_valid.get("errors", []) as Array):
			err_text2 += "\n - " + String(e2)
		result["error"] = err_text2
		return result
	var defs_out: Dictionary = defs_valid.get("tiles_def", {})

	# Write image (copy or encode).
	var image_abs := ProjectSettings.globalize_path(_path_join(dir_path, data.image_rel_path))
	var wrote_image := _write_png(image_abs, data)
	if not wrote_image["ok"]:
		result["error"] = String(wrote_image["error"])
		return result

	# Write JSON files.
	var manifest_path := _path_join(dir_path, "tileset.json")
	var defs_path := _path_join(dir_path, "tiles_def.json")
	_write_json_sorted(manifest_path, manifest_out)
	_write_json_sorted(defs_path, defs_out, true)

	result["ok"] = true
	return result


static func to_res_path(abs_path: String) -> String:
	var root_abs := ProjectSettings.globalize_path("res://")
	var a := abs_path.replace("\\", "/")
	var r := root_abs.replace("\\", "/")
	if a.begins_with(r):
		return "res://" + a.substr(r.length())
	return abs_path


# -----------------
# Internal helpers
# -----------------

static func _path_join(a: String, b: String) -> String:
	if a.ends_with("/"):
		return a + b
	return a + "/" + b


static func _infer_name_from_dir(dir_path: String) -> String:
	var p := dir_path.replace("\\", "/")
	p = p.trim_suffix("/")
	return p.get_file()


static func _infer_name_from_file(abs_path: String) -> String:
	var f := abs_path.replace("\\", "/").get_file()
	if f.to_lower().ends_with(".png"):
		f = f.substr(0, f.length() - 4)
	return f


static func _read_json_dict(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var s := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(s)
	return parsed if (parsed is Dictionary) else {}


static func _parse_tile_size(v) -> Vector2i:
	if v is Array and (v as Array).size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i(16, 16)


static func _load_texture(res_path: String) -> Texture2D:
	if not FileAccess.file_exists(res_path):
		return null

	# Prefer loading via Image to avoid "No loader found" spam when assets are
	# present but not imported yet (common during iteration / fresh checkouts).
	var ext := res_path.get_extension().to_lower()
	if ext in ["png", "jpg", "jpeg", "webp"]:
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(res_path)) == OK:
			return ImageTexture.create_from_image(img)
		return null

	# For non-image resources, try ResourceLoader.
	var tex = load(res_path)
	return tex if (tex is Texture2D) else null


static func _load_texture_from_abs(abs_png_path: String) -> Texture2D:
	var img := Image.new()
	if img.load(abs_png_path) != OK:
		return null
	return ImageTexture.create_from_image(img)


static func _ensure_dir(dir_path: String) -> void:
	var abs := ProjectSettings.globalize_path(dir_path)
	DirAccess.make_dir_recursive_absolute(abs)


static func _write_png(dest_abs: String, data: TilesetData) -> Dictionary:
	var res := {"ok": false, "error": ""}
	# Prefer byte-copy from original file.
	if data.source_image_abs_path.strip_edges() != "" and FileAccess.file_exists(data.source_image_abs_path):
		var in_f := FileAccess.open(data.source_image_abs_path, FileAccess.READ)
		if in_f == null:
			res["error"] = "Failed to open source PNG: " + data.source_image_abs_path
			return res
		var bytes := in_f.get_buffer(in_f.get_length())
		in_f.close()
		var out_f := FileAccess.open(dest_abs, FileAccess.WRITE)
		if out_f == null:
			res["error"] = "Failed to write PNG: " + dest_abs
			return res
		out_f.store_buffer(bytes)
		out_f.close()
		res["ok"] = true
		return res

	# Otherwise, encode from texture.
	if data.texture == null:
		res["error"] = "No texture loaded"
		return res
	var img := data.texture.get_image()
	if img == null:
		res["error"] = "Texture had no image data"
		return res
	var err := img.save_png(dest_abs)
	if err != OK:
		res["error"] = "Failed to save PNG to: " + dest_abs
		return res
	res["ok"] = true
	return res


static func _write_json_sorted(path: String, obj: Dictionary, sort_tiles: bool = false) -> void:
	var out_obj := obj.duplicate(true)
	out_obj = _sort_any(out_obj, sort_tiles)
	var json := JSON.stringify(out_obj, "  ") + "\n"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(json)
	file.close()


static func _sort_any(v, sort_tiles: bool) -> Variant:
	if v is Dictionary:
		# Special handling: tiles dictionary should be sorted by numeric x,y.
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


static func _sort_tile_key_dict(tiles: Dictionary) -> Dictionary:
	var keys := tiles.keys()
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
		out[String(k)] = _sort_any(tiles[k], false)
	return out
