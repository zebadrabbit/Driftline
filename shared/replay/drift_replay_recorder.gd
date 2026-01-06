## Deterministic replay recorder (JSON Lines / JSONL).
##
## Writes:
## - header line first
## - one line per tick containing inputs + world hash

class_name DriftReplayRecorder
extends RefCounted

const DriftInput = preload("res://shared/drift_input.gd")

const FORMAT_ID: String = "driftline.replay"
const SCHEMA_VERSION: int = 1

var enabled: bool = false
var path: String = ""
var _file: FileAccess = null


func start(path_value: String, header: Dictionary) -> void:
	stop()
	path = String(path_value)
	if path == "":
		enabled = false
		return

	# Enforce Driftline versioned JSON contract fields.
	if typeof(header) != TYPE_DICTIONARY:
		enabled = false
		return
	if String(header.get("format", "")) != FORMAT_ID:
		enabled = false
		return
	if typeof(header.get("schema_version", null)) != TYPE_INT or int(header.get("schema_version")) != SCHEMA_VERSION:
		enabled = false
		return
	if String(header.get("type", "")) != "header":
		enabled = false
		return
	if typeof(header.get("version", null)) != TYPE_INT or int(header.get("version")) != 1:
		enabled = false
		return

	# Ensure parent directory exists.
	var abs: String = ProjectSettings.globalize_path(path)
	var dir_path: String = abs.get_base_dir()
	if dir_path != "":
		DirAccess.make_dir_recursive_absolute(dir_path)

	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		enabled = false
		return

	# Header line first.
	var line: String = JSON.stringify(header)
	_file.store_string(line + "\n")
	enabled = true


func record_tick(t: int, inputs_by_id: Dictionary, hash_value: int) -> void:
	if (not enabled) or _file == null:
		return

	# Deterministic writing order: ship IDs sorted ascending.
	var ids: Array = inputs_by_id.keys()
	ids.sort()

	var inputs_out: Dictionary = {}
	for ship_id in ids:
		var key: String = str(ship_id)
		var v = inputs_by_id.get(ship_id)
		if v == null:
			continue

		# Preferred: DriftInput instance.
		if v is RefCounted and v.has_method("to_dict"):
			inputs_out[key] = v.call("to_dict")
			continue

		# Accept already-serialized input dictionaries.
		if typeof(v) == TYPE_DICTIONARY:
			inputs_out[key] = v
			continue

		# Fallback: DriftTypes.DriftInputCmd (server uses this today).
		# Map to the current minimal DriftInput schema.
		var thrust_i: int = 0
		var turn_i: int = 0
		var fire_b: bool = false
		var bomb_b: bool = false
		var afterburner_b: bool = false
		var ability1_b: bool = false

		if v is Object:
			thrust_i = clampi(int(round(float(v.thrust))), -1, 1)
			turn_i = clampi(int(round(float(v.rotation))), -1, 1)
			fire_b = bool(v.fire_primary)
			bomb_b = bool(v.fire_secondary)
			afterburner_b = bool(v.modifier)
			# Collapse ability buttons into one bool (minimal schema).
			ability1_b = bool(v.stealth_btn) or bool(v.cloak_btn) or bool(v.xradar_btn) or bool(v.antiwarp_btn)

		var di = DriftInput.new(thrust_i, turn_i, fire_b, bomb_b, afterburner_b, ability1_b)
		inputs_out[key] = di.to_dict()

	var tick_obj: Dictionary = {
		"type": "tick",
		"t": int(t),
		"inputs": inputs_out,
		"hash": int(hash_value),
	}
	_file.store_string(JSON.stringify(tick_obj) + "\n")


func stop() -> void:
	if _file != null:
		_file.flush()
		_file.close()
	_file = null
	enabled = false
	path = ""
