## Debug helper: export ship specs as JSON.
##
## Run:
##   godot --headless --quit --script res://tools/export_warbird_ship_json.gd

extends SceneTree

const DriftShipConfig = preload("res://server/ship_config.gd")

const OUT_DIR := "res://rulesets/classic"

const SHIP_SPEC_FORMAT := "driftline.ship_spec"
const SHIP_SPEC_SCHEMA_VERSION := 1


func _initialize() -> void:
	var res: Dictionary = DriftShipConfig.load_config()
	if not bool(res.get("ok", false)):
		push_error("[SHIPCFG] failed: " + String(res.get("error", "unknown error")))
		quit(1)
		return

	var out_dir_abs := ProjectSettings.globalize_path(OUT_DIR)
	var mk_err := DirAccess.make_dir_recursive_absolute(out_dir_abs)
	if mk_err != OK:
		push_error("[SHIPCFG] failed: could not create output dir: " + out_dir_abs + " (" + str(mk_err) + ")")
		quit(1)
		return

	var ships: Dictionary = res.get("ships", {})
	var ship_names: PackedStringArray = DriftShipConfig.SHIP_NAMES_IN_ORDER

	for ship_name in ship_names:
		var ship_spec: Dictionary = ships.get(ship_name, {})
		# Emit a versioned, deterministic JSON contract.
		var out: Dictionary = {}
		out["format"] = SHIP_SPEC_FORMAT
		out["schema_version"] = SHIP_SPEC_SCHEMA_VERSION
		out["ship"] = String(ship_spec.get("ship", ship_name))
		out["movement"] = ship_spec.get("movement", {})
		out["energy"] = ship_spec.get("energy", {})
		out["weapons"] = ship_spec.get("weapons", {})
		out["abilities"] = ship_spec.get("abilities", {})
		out["turret"] = ship_spec.get("turret", {})
		out["economy"] = ship_spec.get("economy", {})
		out["sensors"] = ship_spec.get("sensors", {})
		out["soccer"] = ship_spec.get("soccer", {})
		out["misc"] = ship_spec.get("misc", {})
		out["extra"] = ship_spec.get("extra", {})

		var json: String = JSON.stringify(out, "\t")
		if json.is_empty():
			push_error("[SHIPCFG] failed: JSON.stringify returned empty for ship: " + ship_name)
			quit(1)
			return

		var out_path := "%s/%s.json" % [OUT_DIR, ship_name.to_lower()]
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file == null:
			push_error("[SHIPCFG] failed: could not open for writing: " + out_path)
			quit(1)
			return
		file.store_string(json)
		file.close()

		print("Exported ", ship_name, " ShipSpec to ", out_path)
		print(json)
	quit(0)
