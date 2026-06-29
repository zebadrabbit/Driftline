## Driftline ship registry.
##
## Holds all 8 classic ship specs keyed by ship_type index (0-7).
## Both server and client use this to resolve per-player ship parameters.

class_name DriftShipRegistry

const SHIP_NAMES: Array[String] = [
	"Warbird",
	"Javelin",
	"Spider",
	"Leviathan",
	"Terrier",
	"Weasel",
	"Lancaster",
	"Shark",
]

const SHIP_COUNT: int = 8

# Maps ship_type (0-7) to the loaded spec dictionary.
var specs: Array[Dictionary] = []

# Base directory for classic ship spec JSONs (res:// path).
var _base_path: String = "res://rulesets/classic"


func _init(base_path: String = "res://rulesets/classic") -> void:
	_base_path = base_path
	specs.resize(SHIP_COUNT)
	for i in range(SHIP_COUNT):
		specs[i] = {}


func load_all_specs() -> bool:
	## Load all 8 ship spec JSONs from disk. Returns true if all loaded.
	var all_ok: bool = true
	for i in range(SHIP_COUNT):
		var ship_name: String = SHIP_NAMES[i].to_lower()
		var path: String = "%s/%s.json" % [_base_path, ship_name]
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			push_warning("DriftShipRegistry: failed to open %s" % path)
			specs[i] = {}
			all_ok = false
			continue
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()
		if err != OK or typeof(json.data) != TYPE_DICTIONARY:
			push_warning("DriftShipRegistry: failed to parse %s" % path)
			specs[i] = {}
			all_ok = false
			continue
		specs[i] = json.data
	return all_ok


func get_spec(ship_type: int) -> Dictionary:
	## Return the spec for a given ship_type (0-7). Returns empty dict if invalid.
	if ship_type < 0 or ship_type >= SHIP_COUNT:
		return {}
	return specs[ship_type]


func get_spec_json(ship_type: int) -> String:
	## Return the spec as a JSON string for network transmission.
	var spec: Dictionary = get_spec(ship_type)
	if spec.is_empty():
		return ""
	return JSON.stringify(spec)


static func ship_type_from_name(name: String) -> int:
	## Returns ship_type index (0-7) from ship name, or -1 if not found.
	var lower: String = name.strip_edges().to_lower()
	for i in range(SHIP_COUNT):
		if SHIP_NAMES[i].to_lower() == lower:
			return i
	return -1


static func ship_name(ship_type: int) -> String:
	## Returns the display name for a ship type, or "Unknown" if invalid.
	if ship_type < 0 or ship_type >= SHIP_COUNT:
		return "Unknown"
	return SHIP_NAMES[ship_type]


static func clamp_ship_type(ship_type: int) -> int:
	## Clamp to valid range 0..7.
	return clampi(ship_type, 0, SHIP_COUNT - 1)
