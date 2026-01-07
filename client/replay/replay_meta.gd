## Client-only replay metadata builder.
##
## Purely informational: may include platform/time/build details.
## Must not affect deterministic simulation.

class_name ReplayMeta
extends RefCounted

const DriftConstants = preload("res://shared/drift_constants.gd")


static func build_replay_meta(world: Variant, net_state: Variant) -> Dictionary:
	var out: Dictionary = {}

	out["created_utc"] = _iso_utc_now()
	out["game_version"] = _get_game_version()
	out["git_commit"] = _get_git_commit()
	out["godot_version"] = Engine.get_version_info()
	out["platform"] = OS.get_name()
	out["tick_rate"] = int(DriftConstants.TICK_RATE)

	# Map manifest (best-effort).
	var map_path: String = ""
	var map_hash: Variant = ""
	var map_version: Variant = null

	if typeof(net_state) == TYPE_DICTIONARY:
		var ns: Dictionary = net_state
		map_path = String(ns.get("map_path", ns.get("map", "")))
		map_hash = ns.get("map_hash", ns.get("map_checksum", ""))
		if ns.has("map_version"):
			map_version = ns.get("map_version")
	elif net_state is Object:
		map_path = String(_maybe_get(net_state, "map_path", ""))
		map_hash = _maybe_get(net_state, "map_hash", _maybe_get(net_state, "map_checksum", ""))
		map_version = _maybe_get(net_state, "map_version", null)

	# Fall back to world hints if present.
	if map_path == "" and world is Object:
		map_path = String(_maybe_get(world, "map_path", ""))
	if (map_hash == "" or map_hash == null) and world is Object:
		map_hash = _maybe_get(world, "map_hash", "")

	var manifest: Dictionary = {
		"map_path": map_path,
		"map_hash": _normalize_hash(map_hash),
	}
	if map_version != null:
		manifest["map_version"] = map_version
	out["map_manifest"] = manifest

	# Ruleset info (best-effort).
	var ruleset_path: String = ""
	var ruleset_hash: Variant = ""
	if typeof(net_state) == TYPE_DICTIONARY:
		var ns2: Dictionary = net_state
		ruleset_path = String(ns2.get("ruleset_path", ""))
		ruleset_hash = ns2.get("ruleset_hash", "")
	elif net_state is Object:
		ruleset_path = String(_maybe_get(net_state, "ruleset_path", ""))
		ruleset_hash = _maybe_get(net_state, "ruleset_hash", "")

	out["ruleset"] = {
		"ruleset_path": ruleset_path,
		"ruleset_hash": _normalize_hash(ruleset_hash),
	}

	# Network info (best-effort).
	var server_addr: String = ""
	var protocol_version: Variant = "unknown"
	if typeof(net_state) == TYPE_DICTIONARY:
		var ns3: Dictionary = net_state
		server_addr = String(ns3.get("server_addr", ns3.get("server_address", "")))
		protocol_version = ns3.get("protocol_version", "unknown")
	elif net_state is Object:
		server_addr = String(_maybe_get(net_state, "server_addr", _maybe_get(net_state, "server_address", "")))
		protocol_version = _maybe_get(net_state, "protocol_version", "unknown")

	out["network"] = {
		"server_addr": server_addr,
		"protocol_version": protocol_version,
	}

	return out


static func _iso_utc_now() -> String:
	# ISO-8601-ish UTC timestamp: YYYY-MM-DDTHH:MM:SSZ
	var d: Dictionary = Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [
		int(d.get("year", 0)),
		int(d.get("month", 0)),
		int(d.get("day", 0)),
		int(d.get("hour", 0)),
		int(d.get("minute", 0)),
		int(d.get("second", 0)),
	]


static func _get_game_version() -> String:
	# Prefer ProjectSettings if present, else fall back to res://VERSION.
	if ProjectSettings.has_setting("application/config/version"):
		var v: String = String(ProjectSettings.get_setting("application/config/version", ""))
		if v.strip_edges() != "":
			return v.strip_edges()

	var f: FileAccess = FileAccess.open("res://VERSION", FileAccess.READ)
	if f != null:
		var s := f.get_as_text().strip_edges()
		f.close()
		if s != "":
			return s

	return "unknown"


static func _get_git_commit() -> String:
	# If the build system injects a const or ProjectSettings key later, read it here.
	# For now, keep it explicit.
	return "unknown"


static func _maybe_get(obj: Object, prop: String, default: Variant) -> Variant:
	if obj == null:
		return default
	# Properties on GDScript objects can be queried via Object.get().
	# get() returns null if missing.
	var v: Variant = obj.get(prop)
	if v == null:
		return default
	return v


static func _normalize_hash(v: Variant) -> Variant:
	# If it's a PackedByteArray, return hex string. Otherwise pass through.
	if typeof(v) == TYPE_PACKED_BYTE_ARRAY:
		var b: PackedByteArray = v
		# Godot 4 API.
		return b.hex_encode()
	return v
