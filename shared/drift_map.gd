## Driftline shared map validation + canonicalization + checksum.
##
## This is used by both server and client to ensure they are simulating the same map.

class_name DriftMap

const TILE_SIZE: int = 16
const FORMAT_VERSION: int = 1


static func normalize_map_data(data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in data.keys():
		out[k] = data[k]

	var meta: Dictionary = {}
	if out.has("meta") and out["meta"] is Dictionary:
		meta = out["meta"]
	else:
		meta = {}
		out["meta"] = meta

	var w_tiles: int = int(meta.get("w", 0))
	var h_tiles: int = int(meta.get("h", 0))
	if w_tiles <= 0:
		var w_raw: int = int(out.get("width", 0))
		if w_raw > 0:
			w_tiles = int(w_raw / TILE_SIZE) if (w_raw >= 256 and w_raw % TILE_SIZE == 0) else w_raw
		else:
			w_tiles = 64
	if h_tiles <= 0:
		var h_raw: int = int(out.get("height", 0))
		if h_raw > 0:
			h_tiles = int(h_raw / TILE_SIZE) if (h_raw >= 256 and h_raw % TILE_SIZE == 0) else h_raw
		else:
			h_tiles = 64

	meta["w"] = w_tiles
	meta["h"] = h_tiles
	meta["tile_size"] = int(meta.get("tile_size", TILE_SIZE))
	meta["tileset"] = String(meta.get("tileset", out.get("tileset", "")))

	var layers: Dictionary = {}
	if out.has("layers") and out["layers"] is Dictionary:
		layers = out["layers"]
	else:
		layers = {}
		out["layers"] = layers

	for layer_name in ["bg", "solid", "fg"]:
		if not layers.has(layer_name) or not (layers[layer_name] is Array):
			layers[layer_name] = []

	if not out.has("entities") or not (out["entities"] is Array):
		out["entities"] = []

	return out


static func validate_and_canonicalize(map_data: Dictionary) -> Dictionary:
	var norm := normalize_map_data(map_data)
	var errors: Array[String] = []
	var warnings: Array[String] = []

	var meta: Dictionary = norm.get("meta", {})
	var w: int = int(meta.get("w", 0))
	var h: int = int(meta.get("h", 0))
	if w < 2 or h < 2:
		errors.append("meta.w/meta.h must be >= 2")
		w = maxi(2, w)
		h = maxi(2, h)

	var out_meta := {
		"w": w,
		"h": h,
		"tile_size": int(meta.get("tile_size", TILE_SIZE)),
		"tileset": String(meta.get("tileset", "")),
	}

	var layers_in: Dictionary = norm.get("layers", {})
	var out_layers: Dictionary = {"bg": [], "solid": [], "fg": []}

	for layer_name in ["bg", "solid", "fg"]:
		var cells_in: Array = layers_in.get(layer_name, [])
		var seen: Dictionary = {} # "x,y" -> cell array
		var dupes: int = 0

		for i in range(cells_in.size()):
			var cell = cells_in[i]
			if not (cell is Array) or (cell as Array).size() != 4:
				errors.append("layers.%s[%d] must be [x,y,ax,ay]" % [layer_name, i])
				continue

			var arr: Array = cell
			var x: int = int(arr[0])
			var y: int = int(arr[1])
			var ax: int = int(arr[2])
			var ay: int = int(arr[3])

			if x < 0 or y < 0 or x >= w or y >= h:
				errors.append("layers.%s[%d] out of bounds (%d,%d)" % [layer_name, i, x, y])
				continue
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				warnings.append("layers.%s[%d] is on boundary (%d,%d); boundary is generated" % [layer_name, i, x, y])
				continue
			if ax < 0 or ay < 0:
				errors.append("layers.%s[%d] has invalid atlas coords (%d,%d)" % [layer_name, i, ax, ay])
				continue

			var key := "%d,%d" % [x, y]
			if seen.has(key):
				dupes += 1
			seen[key] = [x, y, ax, ay]

		if dupes > 0:
			warnings.append("layers.%s has %d duplicate cell(s); last wins" % [layer_name, dupes])

		var cells_out: Array = seen.values()
		cells_out.sort_custom(Callable(DriftMap, "_tile_less"))
		out_layers[layer_name] = cells_out

	# Entities
	var entities_in: Array = norm.get("entities", [])
	var entities_seen: Dictionary = {} # "type:x,y" -> dict
	var entity_dupes: int = 0
	var allowed := {"spawn": true, "flag": true, "base": true}

	for i in range(entities_in.size()):
		var e = entities_in[i]
		if typeof(e) != TYPE_DICTIONARY:
			errors.append("entities[%d] must be an object" % i)
			continue
		var d: Dictionary = e
		var t: String = String(d.get("type", ""))
		if not allowed.has(t):
			errors.append("entities[%d] has invalid type '%s'" % [i, t])
			continue
		var x: int = int(d.get("x", -1))
		var y: int = int(d.get("y", -1))
		var team: int = int(d.get("team", 0))
		if x < 0 or y < 0 or x >= w or y >= h:
			errors.append("entities[%d] out of bounds (%d,%d)" % [i, x, y])
			continue
		if x == 0 or y == 0 or x == w - 1 or y == h - 1:
			warnings.append("entities[%d] is on boundary (%d,%d); boundary is reserved" % [i, x, y])
			continue

		var key2 := "%s:%d,%d" % [t, x, y]
		if entities_seen.has(key2):
			entity_dupes += 1
		entities_seen[key2] = {"type": t, "x": x, "y": y, "team": team}

	if entity_dupes > 0:
		warnings.append("entities has %d duplicate(s) at same cell+type; last wins" % entity_dupes)

	var entities_out: Array = entities_seen.values()
	entities_out.sort_custom(Callable(DriftMap, "_entity_less"))

	var canonical := {
		"v": FORMAT_VERSION,
		"meta": out_meta,
		"layers": out_layers,
		"entities": entities_out,
	}

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"map": canonical,
	}


static func checksum_sha256(map_data: Dictionary) -> PackedByteArray:
	var res := validate_and_canonicalize(map_data)
	var canonical: Dictionary = res.get("map", {})
	var s := canonical_json_string(canonical)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(s.to_utf8_buffer())
	return ctx.finish()


static func checksum_sha256_hex(map_data: Dictionary) -> String:
	return bytes_to_hex(checksum_sha256(map_data))


static func bytes_to_hex(bytes: PackedByteArray) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.resize(bytes.size())
	for i in range(bytes.size()):
		parts[i] = "%02x" % int(bytes[i])
	return "".join(parts)


static func canonical_json_string(map_data: Dictionary) -> String:
	# Expects map_data already in canonical structure from validate_and_canonicalize().
	var v: int = int(map_data.get("v", FORMAT_VERSION))
	var meta: Dictionary = map_data.get("meta", {})
	var layers: Dictionary = map_data.get("layers", {})
	var entities: Array = map_data.get("entities", [])

	var w: int = int(meta.get("w", 0))
	var h: int = int(meta.get("h", 0))
	var tile_size: int = int(meta.get("tile_size", TILE_SIZE))
	var tileset: String = _json_escape(String(meta.get("tileset", "")))

	var s := "{"
	s += '"v":%d,' % v
	s += '"meta":{'
	s += '"w":%d,"h":%d,"tile_size":%d,"tileset":"%s"' % [w, h, tile_size, tileset]
	s += "},"
	s += '"layers":{'
	s += '"bg":%s,' % _cells_to_json(layers.get("bg", []))
	s += '"solid":%s,' % _cells_to_json(layers.get("solid", []))
	s += '"fg":%s' % _cells_to_json(layers.get("fg", []))
	s += "},"
	s += '"entities":%s' % _entities_to_json(entities)
	s += "}"
	return s


static func _cells_to_json(cells: Array) -> String:
	var s := "["
	for i in range(cells.size()):
		var c: Array = cells[i]
		if i > 0:
			s += ","
		s += "[%d,%d,%d,%d]" % [int(c[0]), int(c[1]), int(c[2]), int(c[3])]
	s += "]"
	return s


static func _entities_to_json(entities: Array) -> String:
	var s := "["
	for i in range(entities.size()):
		var e: Dictionary = entities[i]
		if i > 0:
			s += ","
		var t: String = _json_escape(String(e.get("type", "")))
		var x: int = int(e.get("x", 0))
		var y: int = int(e.get("y", 0))
		var team: int = int(e.get("team", 0))
		s += '{"type":"%s","x":%d,"y":%d,"team":%d}' % [t, x, y, team]
	s += "]"
	return s


static func _json_escape(s: String) -> String:
	return s.replace("\\", "\\\\").replace('"', '\\"')


static func _tile_less(a, b) -> bool:
	# a/b are [x,y,ax,ay]
	if int(a[0]) != int(b[0]):
		return int(a[0]) < int(b[0])
	if int(a[1]) != int(b[1]):
		return int(a[1]) < int(b[1])
	if int(a[2]) != int(b[2]):
		return int(a[2]) < int(b[2])
	return int(a[3]) < int(b[3])


static func _entity_less(a, b) -> bool:
	# a/b are {type,x,y,team}
	var at: String = String(a.get("type", ""))
	var bt: String = String(b.get("type", ""))
	if at != bt:
		return at < bt
	if int(a.get("x", 0)) != int(b.get("x", 0)):
		return int(a.get("x", 0)) < int(b.get("x", 0))
	if int(a.get("y", 0)) != int(b.get("y", 0)):
		return int(a.get("y", 0)) < int(b.get("y", 0))
	return int(a.get("team", 0)) < int(b.get("team", 0))
