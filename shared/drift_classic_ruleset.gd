## Classic ruleset ship-spec loader (rulesets/classic/*.json)
##
## Strict contract:
## - Files must be valid JSON objects.
## - Must include:
##   - format
##   - schema_version
##   - ship
## - Loader fails loudly on any invalid data.
##
## Determinism:
## - Filenames are sorted before loading.

class_name DriftClassicRuleset
extends RefCounted

const DIR_PATH := "res://rulesets/classic"
const EXPECTED_FORMAT := "driftline.ship_spec"
const EXPECTED_SCHEMA_VERSION := 1

var ruleset_ships: Dictionary = {}


func load() -> bool:
	ruleset_ships = {}

	var dir := DirAccess.open(DIR_PATH)
	if dir == null:
		push_error("[CLASSIC] Failed to open directory: " + DIR_PATH)
		return false

	var files: Array[String] = []
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if dir.current_is_dir():
			continue
		if name.begins_with("."):
			continue
		if not name.to_lower().ends_with(".json"):
			continue
		files.append(name)
	dir.list_dir_end()

	files.sort()

	for filename in files:
		var path := DIR_PATH + "/" + filename
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			push_error("[CLASSIC] Failed to open file: " + path)
			return false

		var json_str := file.get_as_text()
		file.close()

		var json := JSON.new()
		var err := json.parse(json_str)
		if err != OK:
			push_error("[CLASSIC] Invalid JSON: %s (line %d): %s" % [path, int(json.get_error_line()), String(json.get_error_message())])
			return false
		if typeof(json.data) != TYPE_DICTIONARY:
			push_error("[CLASSIC] JSON root must be an object: " + path)
			return false

		var root: Dictionary = json.data

		# Versioned contract enforcement.
		if not root.has("format"):
			push_error("[CLASSIC] Missing required field 'format': " + path)
			return false
		if String(root.get("format")) != EXPECTED_FORMAT:
			push_error("[CLASSIC] Unknown format '%s' (expected '%s'): %s" % [String(root.get("format")), EXPECTED_FORMAT, path])
			return false
		if not root.has("schema_version"):
			push_error("[CLASSIC] Missing required field 'schema_version': " + path)
			return false
		if int(root.get("schema_version")) != EXPECTED_SCHEMA_VERSION:
			push_error("[CLASSIC] Unsupported schema_version %s (expected %d): %s" % [str(root.get("schema_version")), EXPECTED_SCHEMA_VERSION, path])
			return false

		if not root.has("ship"):
			push_error("[CLASSIC] Missing required field 'ship': " + path)
			return false
		var ship_name := String(root.get("ship")).strip_edges()
		if ship_name == "":
			push_error("[CLASSIC] Field 'ship' must be a non-empty string: " + path)
			return false

		if ruleset_ships.has(ship_name):
			push_error("[CLASSIC] Duplicate ship '%s' (already loaded, file: %s)" % [ship_name, path])
			return false

		ruleset_ships[ship_name] = root

	return true


func get_ship_spec(ship_name: String) -> Dictionary:
	var name := String(ship_name)
	if ruleset_ships.has(name):
		return ruleset_ships[name]
	push_error("[CLASSIC] Unknown ship: " + name)
	return {}


func get_loaded_ship_names() -> PackedStringArray:
	var names: Array[String] = []
	for k in ruleset_ships.keys():
		names.append(String(k))
	names.sort()
	return PackedStringArray(names)
