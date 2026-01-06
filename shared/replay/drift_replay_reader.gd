## Driftline replay reader (JSON Lines / JSONL)
##
## Strict loader rules:
## - First non-blank line must be header
## - Header must include required contract fields: format + schema_version
## - Unknown format/schema_version fails loudly

class_name DriftReplayReader
extends RefCounted

const FORMAT_ID: String = "driftline.replay"
const SCHEMA_VERSION: int = 1


func load_jsonl(path: String) -> Dictionary:
	var p: String = String(path)
	if p == "":
		return {"ok": false, "error": "empty path"}
	if not FileAccess.file_exists(p):
		return {"ok": false, "error": "file does not exist"}

	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "failed to open"}

	var header: Dictionary = {}
	var ticks: Array = []
	var line_no: int = 0
	var saw_header: bool = false

	while not f.eof_reached():
		var line: String = f.get_line()
		line_no += 1
		if line.strip_edges() == "":
			continue

		var obj = JSON.parse_string(line)
		if obj == null:
			return {"ok": false, "error": "json parse error", "line": line_no}
		if typeof(obj) != TYPE_DICTIONARY:
			return {"ok": false, "error": "json line must be object", "line": line_no}

		var d: Dictionary = obj
		if not saw_header:
			var hres: Dictionary = _validate_and_extract_header(d)
			if not bool(hres.get("ok", false)):
				hres["line"] = line_no
				return hres
			header = hres.get("header", {})
			saw_header = true
			continue

		var tres: Dictionary = _validate_and_extract_tick(d)
		if not bool(tres.get("ok", false)):
			tres["line"] = line_no
			return tres
		ticks.append(tres.get("tick"))

	if not saw_header:
		return {"ok": false, "error": "missing header"}

	return {"ok": true, "header": header, "ticks": ticks}


func _validate_and_extract_header(d: Dictionary) -> Dictionary:
	if String(d.get("type", "")) != "header":
		return {"ok": false, "error": "first record must be header"}

	# Driftline persistent JSON contract fields.
	if String(d.get("format", "")) != FORMAT_ID:
		return {"ok": false, "error": "unknown or missing format"}
	if not _is_intlike(d.get("schema_version", null)):
		return {"ok": false, "error": "missing schema_version"}
	if _to_intlike(d.get("schema_version")) != SCHEMA_VERSION:
		return {"ok": false, "error": "unsupported schema_version"}

	if not _is_intlike(d.get("version", null)) or _to_intlike(d.get("version")) != 1:
		return {"ok": false, "error": "unsupported replay version"}
	if not _is_intlike(d.get("tick_rate", null)):
		return {"ok": false, "error": "tick_rate must be int"}
	if not _is_intlike(d.get("ruleset_hash", null)):
		return {"ok": false, "error": "ruleset_hash must be int"}
	if typeof(d.get("map_id", null)) != TYPE_STRING:
		return {"ok": false, "error": "map_id must be string"}
	if not _is_intlike(d.get("map_hash", null)):
		return {"ok": false, "error": "map_hash must be int"}
	if d.has("notes") and typeof(d.get("notes")) != TYPE_STRING:
		return {"ok": false, "error": "notes must be string"}

	return {"ok": true, "header": d}


func _validate_and_extract_tick(d: Dictionary) -> Dictionary:
	if String(d.get("type", "")) != "tick":
		return {"ok": false, "error": "record must be type tick"}
	if not _is_intlike(d.get("t", null)):
		return {"ok": false, "error": "tick.t must be int"}
	if not _is_intlike(d.get("hash", null)):
		return {"ok": false, "error": "tick.hash must be int"}
	if typeof(d.get("inputs", null)) != TYPE_DICTIONARY:
		return {"ok": false, "error": "tick.inputs must be object"}

	var inputs_d: Dictionary = d.get("inputs")
	for k in inputs_d.keys():
		if typeof(k) != TYPE_STRING:
			return {"ok": false, "error": "tick.inputs keys must be strings"}
		var v = inputs_d.get(k)
		if typeof(v) != TYPE_DICTIONARY:
			return {"ok": false, "error": "tick.inputs values must be objects"}

	return {"ok": true, "tick": {"t": _to_intlike(d.get("t")), "inputs": inputs_d, "hash": _to_intlike(d.get("hash"))}}


static func _is_intlike(v: Variant) -> bool:
	var t := typeof(v)
	if t == TYPE_INT:
		return true
	if t == TYPE_FLOAT:
		var f: float = float(v)
		return is_finite(f) and absf(f - round(f)) < 0.0000001
	return false


static func _to_intlike(v: Variant) -> int:
	if typeof(v) == TYPE_INT:
		return int(v)
	# Precondition: _is_intlike(v)
	return int(round(float(v)))
