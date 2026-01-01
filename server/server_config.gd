## Server boot config loader (server_config.json)
##
## Loads user://server_config.json first, then res://server_config.json.
##
## STRICT CONTRACT:
## - Must include `format` and `schema_version`.
## - Must include required fields.
## - No normalization, auto-fill, or silent defaults.

class_name DriftServerConfig

const DriftValidate = preload("res://shared/drift_validate.gd")

const USER_PATH: String = "user://server_config.json"
const RES_PATH: String = "res://server_config.json"


static func load_config() -> Dictionary:
	var candidates := PackedStringArray([USER_PATH, RES_PATH])
	var path := ""
	for p in candidates:
		if FileAccess.file_exists(p):
			path = p
			break

	if path == "":
		return {
			"ok": false,
			"error": "server_config.json not found (looked in user:// and res://)",
			"paths": candidates,
		}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"error": "Failed to open server_config.json: " + path,
			"path": path,
		}

	var json_str := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_err := json.parse(json_str)
	if parse_err != OK:
		return {
			"ok": false,
			"error": "Failed to parse server_config.json: %s (line %d): %s" % [path, int(json.get_error_line()), String(json.get_error_message())],
			"path": path,
			"parse_error": true,
		}

	if typeof(json.data) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"error": "server_config.json must be a JSON object: " + path,
			"path": path,
			"parse_error": true,
		}

	var root: Dictionary = json.data
	var validated := DriftValidate.validate_server_config(root)
	if not bool(validated.get("ok", false)):
		var err_text := "server_config validation failed: " + path
		for e in (validated.get("errors", []) as Array):
			err_text += "\n - " + String(e)
		return {
			"ok": false,
			"error": err_text,
			"path": path,
			"errors": validated.get("errors", []),
			"warnings": validated.get("warnings", []),
			"validation_error": true,
		}

	return {
		"ok": true,
		"path": path,
		"config": validated.get("server_config", {}),
		"warnings": validated.get("warnings", []),
	}
