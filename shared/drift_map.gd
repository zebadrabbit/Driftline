## Driftline shared map validation + canonicalization + checksum.
##
## This is used by both server and client to ensure they are simulating the same map.

class_name DriftMap

const TILE_SIZE: int = 16
static func validate_and_canonicalize(map_data: Dictionary) -> Dictionary:
	var DriftValidate = preload("res://shared/drift_validate.gd")
	return DriftValidate.validate_map(map_data)


static func checksum_sha256(map_data: Dictionary) -> PackedByteArray:
	var res := validate_and_canonicalize(map_data)
	if not bool(res.get("ok", false)):
		return PackedByteArray()
	var canonical: Dictionary = res.get("map", {})
	return checksum_sha256_canonical(canonical)


static func checksum_sha256_canonical(canonical_map: Dictionary) -> PackedByteArray:
	var s := canonical_json_string(canonical_map)
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
	var fmt: String = _json_escape(String(map_data.get("format", "")))
	var schema_version: int = int(map_data.get("schema_version", 0))
	var meta: Dictionary = map_data.get("meta", {})
	var layers: Dictionary = map_data.get("layers", {})
	var entities: Array = map_data.get("entities", [])

	var s := "{"
	s += '"format":"%s",' % fmt
	s += '"schema_version":%d,' % schema_version
	s += '"meta":%s,' % _meta_to_json(meta)
	s += '"layers":{'
	s += '"bg":%s,' % _cells_to_json(layers.get("bg", []))
	s += '"solid":%s,' % _cells_to_json(layers.get("solid", []))
	s += '"fg":%s' % _cells_to_json(layers.get("fg", []))
	s += "},"
	s += '"entities":%s' % _entities_to_json(entities)
	s += "}"
	return s


static func _meta_to_json(meta: Dictionary) -> String:
	var w: int = int(meta.get("w", 0))
	var h: int = int(meta.get("h", 0))
	var tile_size: int = int(meta.get("tile_size", TILE_SIZE))
	var tileset: String = _json_escape(String(meta.get("tileset", "")))

	var s := "{"
	s += '"w":%d,"h":%d,"tile_size":%d,"tileset":"%s"' % [w, h, tile_size, tileset]

	# Any additional scalar meta keys are appended in stable key order.
	var keys: Array = meta.keys()
	keys.sort()
	for k in keys:
		var ks := String(k)
		if ks in ["w", "h", "tile_size", "tileset"]:
			continue
		var v = meta[k]
		var tv := typeof(v)
		if tv == TYPE_STRING:
			s += ',"%s":"%s"' % [_json_escape(ks), _json_escape(String(v))]
		elif tv == TYPE_BOOL:
			s += ',"%s":%s' % [_json_escape(ks), ("true" if bool(v) else "false")]
		elif tv in [TYPE_INT, TYPE_FLOAT]:
			# Canonicalize numbers using Godot's string conversion.
			s += ',"%s":%s' % [_json_escape(ks), String(v)]
		else:
			# Non-scalar values are forbidden by validation; omit from canonical output.
			pass

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
