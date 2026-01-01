## Map loader (disk + JSON + DriftMap validation)
##
## Returns a validated canonical map + checksum.

class_name DriftMapLoader

const DriftMap = preload("res://shared/drift_map.gd")


static func load_map(map_path: String) -> Dictionary:
	var p := String(map_path).strip_edges()
	if p == "":
		return {
			"ok": false,
			"error": "Empty map path",
		}

	if not FileAccess.file_exists(p):
		return {
			"ok": false,
			"error": "Map file not found: " + p,
			"missing": true,
		}

	var file := FileAccess.open(p, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"error": "Failed to open map: " + p,
		}

	var json_str := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(json_str)
	if parse_result != OK:
		return {
			"ok": false,
			"error": "Failed to parse map JSON: " + p,
			"parse_error": true,
		}

	var data: Dictionary = json.data
	var validated := DriftMap.validate_and_canonicalize(data)
	if not bool(validated.get("ok", false)):
		var errs: Array = validated.get("errors", [])
		var err_text := "Map validation failed: " + p
		for e in errs:
			err_text += "\n - " + String(e)
		return {
			"ok": false,
			"error": err_text,
			"validation_error": true,
			"errors": errs,
			"warnings": validated.get("warnings", []),
		}

	var canonical: Dictionary = validated.get("map", {})
	var checksum: PackedByteArray = DriftMap.checksum_sha256(canonical)
	var map_version: int = int(canonical.get("v", 0))

	return {
		"ok": true,
		"path": p,
		"map": canonical,
		"checksum": checksum,
		"map_version": map_version,
		"warnings": validated.get("warnings", []),
	}
