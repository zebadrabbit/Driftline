## Driftline ruleset loader (rulesets/*.json)
##
## STRICT CONTRACT:
## - Must include `format` and `schema_version`.
## - Must include required fields.
## - No normalization, auto-fill, or silent defaults.

class_name DriftRuleset

const DriftValidate = preload("res://shared/drift_validate.gd")


static func load_ruleset(path: String) -> Dictionary:
	var p := String(path).strip_edges()
	if p == "":
		return {"ok": false, "error": "ruleset path is empty"}
	if not (p.begins_with("res://") or p.begins_with("user://")):
		return {"ok": false, "error": "ruleset path must start with res:// or user://"}
	if not FileAccess.file_exists(p):
		return {"ok": false, "error": "ruleset not found: " + p, "path": p}

	var file := FileAccess.open(p, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Failed to open ruleset: " + p, "path": p}

	var json_str := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_err := json.parse(json_str)
	if parse_err != OK:
		return {
			"ok": false,
			"error": "Failed to parse ruleset: %s (line %d): %s" % [p, int(json.get_error_line()), String(json.get_error_message())],
			"path": p,
			"parse_error": true,
		}

	if typeof(json.data) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"error": "ruleset must be a JSON object: " + p,
			"path": p,
			"parse_error": true,
		}

	var root: Dictionary = json.data
	var validated := DriftValidate.validate_ruleset(root)
	if not bool(validated.get("ok", false)):
		var err_text := "ruleset validation failed: " + p
		for e in (validated.get("errors", []) as Array):
			err_text += "\n - " + String(e)
		return {
			"ok": false,
			"error": err_text,
			"path": p,
			"errors": validated.get("errors", []),
			"warnings": validated.get("warnings", []),
			"validation_error": true,
		}

	return {
		"ok": true,
		"path": p,
		"ruleset": validated.get("ruleset", {}),
		"warnings": validated.get("warnings", []),
	}
