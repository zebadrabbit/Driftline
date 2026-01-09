## Server ship configuration loader (server.cfg)
##
## Loads user://server.cfg first, then res://server.cfg.
##
## Goals:
## - Deterministic: produces a canonical representation suitable for hashing.
## - Data-driven: modeled after Subspace ship sections in server.cfg.
## - Friendly validation: unknown keys are preserved in `extra` with warnings.

class_name DriftShipConfig

const DriftHash = preload("res://shared/drift_hash.gd")

const USER_PATH: String = "user://server.cfg"
const RES_PATH: String = "res://server.cfg"

const SHIP_NAMES_IN_ORDER := [
	"Warbird",
	"Javelin",
	"Spider",
	"Leviathan",
	"Terrier",
	"Weasel",
	"Lancaster",
	"Shark",
]


static func load_config() -> Dictionary:
	# Layering behavior:
	# - res://server.cfg provides defaults
	# - user://server.cfg overrides keys it defines
	var res_cfg := ConfigFile.new()
	var user_cfg := ConfigFile.new()
	var loaded_any: bool = false
	var loaded_paths: Array[String] = []
	var has_res: bool = FileAccess.file_exists(RES_PATH)
	var has_user: bool = FileAccess.file_exists(USER_PATH)
	if has_res:
		var err_res := res_cfg.load(RES_PATH)
		if err_res != OK:
			return {
				"ok": false,
				"error": "Failed to load server.cfg: %s (err=%d)" % [RES_PATH, err_res],
				"path": RES_PATH,
			}
		loaded_any = true
		loaded_paths.append(RES_PATH)
	if has_user:
		var err_user := user_cfg.load(USER_PATH)
		if err_user != OK:
			return {
				"ok": false,
				"error": "Failed to load server.cfg: %s (err=%d)" % [USER_PATH, err_user],
				"path": USER_PATH,
			}
		loaded_any = true
		loaded_paths.append(USER_PATH)
	if not loaded_any:
		return {
			"ok": false,
			"error": "server.cfg not found (looked in user:// and res://)",
			"paths": PackedStringArray([USER_PATH, RES_PATH]),
		}

	var warnings: Array[String] = []
	var ships: Dictionary = {}

	# Expected keys are derived from res:// defaults if present.
	var expected_keys_by_ship: Dictionary = _build_expected_keys_by_ship(res_cfg, has_res)

	for ship_name in SHIP_NAMES_IN_ORDER:
		var spec_res: Dictionary = _load_ship_spec_layered(user_cfg, has_user, res_cfg, has_res, ship_name, expected_keys_by_ship.get(ship_name, PackedStringArray()), warnings)
		ships[ship_name] = spec_res

	var canonical_json: String = canonical_json_string(ships)
	var ships_hash: int = DriftHash.int31_from_string_sha256(canonical_json)

	return {
		"ok": true,
		"paths": loaded_paths,
		"ships": ships,
		"ships_hash": ships_hash,
		"canonical_json": canonical_json,
		"warnings": warnings,
	}


static func _load_ship_spec_layered(user_cfg: ConfigFile, has_user: bool, res_cfg: ConfigFile, has_res: bool, ship_name: String, expected_keys: PackedStringArray, warnings: Array[String]) -> Dictionary:
	var section: String = String(ship_name)

	# Union of keys present in either layer.
	var keys_set: Dictionary = {}
	if has_res and res_cfg.has_section(section):
		for k in res_cfg.get_section_keys(section):
			keys_set[String(k)] = true
	if has_user and user_cfg.has_section(section):
		for k in user_cfg.get_section_keys(section):
			keys_set[String(k)] = true

	var keys: Array = keys_set.keys()
	keys.sort()

	var known: Dictionary = {}
	var extra: Dictionary = {}

	# Build expected key lookup.
	var expected_lookup: Dictionary = {}
	for ek in expected_keys:
		expected_lookup[String(ek)] = true

	for k in keys:
		var key: String = String(k)
		var v: Variant = null
		if has_user and user_cfg.has_section_key(section, key):
			v = user_cfg.get_value(section, key)
		elif has_res and res_cfg.has_section_key(section, key):
			v = res_cfg.get_value(section, key)

		# We treat ship values as numeric or strings; keep as-is but normalize later.
		if expected_lookup.has(key):
			known[key] = v
		else:
			extra[key] = v
			warnings.append("[SHIPCFG] %s: unknown key '%s' (preserved in extra)" % [section, key])

	# Missing expected keys warning.
	for ek in expected_keys:
		var eks: String = String(ek)
		if not known.has(eks):
			warnings.append("[SHIPCFG] %s: missing expected key '%s'" % [section, eks])

	# Canonical nested spec.
	return _canonicalize_ship_spec(section, known, extra)


static func _build_expected_keys_by_ship(res_cfg: ConfigFile, has_res: bool) -> Dictionary:
	# If res://server.cfg is present, use it to define the expected keys per ship.
	# This makes the shipped defaults warning-free while still warning on missing keys
	# if a user config omits fields entirely.
	var out: Dictionary = {}
	if not has_res:
		for ship_name in SHIP_NAMES_IN_ORDER:
			out[ship_name] = PackedStringArray()
		return out

	for ship_name in SHIP_NAMES_IN_ORDER:
		var section: String = String(ship_name)
		var keys: PackedStringArray = PackedStringArray()
		if res_cfg.has_section(section):
			keys = res_cfg.get_section_keys(section)
		# Ensure stable ordering.
		var arr: Array = []
		for k in keys:
			arr.append(String(k))
		arr.sort()
		var pk := PackedStringArray()
		for k in arr:
			pk.append(String(k))
		out[ship_name] = pk
	return out


static func _canonicalize_ship_spec(ship_name: String, known: Dictionary, extra: Dictionary) -> Dictionary:
	# Canonical groups; values are scalar numbers/bools/strings.
	# Keys are mapped based on common Subspace server.cfg names.
	var movement: Dictionary = {}
	var energy: Dictionary = {}
	var weapons: Dictionary = {}
	var abilities: Dictionary = {}
	var turret: Dictionary = {}
	var economy: Dictionary = {}
	var sensors: Dictionary = {}
	var soccer: Dictionary = {}
	var misc: Dictionary = {}

	for k in known.keys():
		var key: String = String(k)
		var v: Variant = _normalize_scalar(known.get(key))
		if key.begins_with("Soccer"):
			soccer[key] = v
		elif key.begins_with("Turret"):
			turret[key] = v
		elif key.begins_with("See"):
			# Sensors/visibility.
			sensors[key] = v
		elif key in ["SuperTime", "ShieldsTime", "DisableFastShooting", "CloakStatus", "StealthStatus", "XRadarStatus", "AntiWarpStatus"] or key.findn("Cloak") >= 0 or key.findn("Stealth") >= 0 or key.findn("XRadar") >= 0 or key.findn("AntiWarp") >= 0:
			abilities[key] = v
		elif key.findn("Bounty") >= 0 or key.findn("Prize") >= 0 or key.findn("Attach") >= 0:
			economy[key] = v
		elif key.findn("Energy") >= 0 or key.findn("Recharge") >= 0:
			# Energy pool and recharge tuning.
			energy[key] = v
		elif key.findn("Bullet") >= 0 or key.findn("Bomb") >= 0 or key.findn("Landmine") >= 0 or key.findn("Shrapnel") >= 0 or key.findn("Gun") >= 0 or key.findn("Guns") >= 0 or key.findn("Mine") >= 0 or key.findn("Mines") >= 0 or key.findn("Rocket") >= 0 or key in ["RepelMax", "BurstMax", "DecoyMax", "ThorMax", "BrickMax", "PortalMax", "BombThrust"]:
			weapons[key] = v
		elif key.findn("Rotation") >= 0 or key.findn("Thrust") >= 0 or key.findn("Speed") >= 0 or key.findn("Gravity") >= 0 or key == "Radius" or key == "DamageFactor":
			movement[key] = v
		else:
			misc[key] = v

	# Sort + stabilize extra as well.
	var extra_out: Dictionary = {}
	var extra_keys: Array = extra.keys()
	extra_keys.sort()
	for k2 in extra_keys:
		extra_out[String(k2)] = _normalize_scalar(extra.get(k2))

	return {
		"ship": ship_name,
		"movement": _sorted_dict(movement),
		"energy": _sorted_dict(energy),
		"weapons": _sorted_dict(weapons),
		"abilities": _sorted_dict(abilities),
		"turret": _sorted_dict(turret),
		"economy": _sorted_dict(economy),
		"sensors": _sorted_dict(sensors),
		"soccer": _sorted_dict(soccer),
		"misc": _sorted_dict(misc),
		"extra": extra_out,
	}


static func _sorted_dict(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var keys: Array = d.keys()
	keys.sort()
	for k in keys:
		out[String(k)] = d.get(k)
	return out


static func _normalize_scalar(v: Variant) -> Variant:
	var t := typeof(v)
	if t == TYPE_NIL:
		return null
	if t == TYPE_BOOL:
		return bool(v)
	if t == TYPE_INT:
		return int(v)
	if t == TYPE_FLOAT:
		# Avoid platform-specific formatting in JSON by keeping as float.
		return float(v)
	if t == TYPE_STRING:
		var s: String = String(v)
		# Try to parse numeric strings as int if they look like ints.
		var stripped := s.strip_edges()
		if stripped.is_valid_int():
			return int(stripped)
		if stripped.is_valid_float():
			return float(stripped)
		return s
	# ConfigFile can return PackedStringArray etc; stringify for determinism.
	return String(v)


static func canonical_json_string(ships: Dictionary) -> String:
	# Canonical JSON string with fixed ship order and stable keys.
	# NOTE: this is for hashing, not a user-facing schema.
	var s := "{"
	# Ship objects.
	s += '"ships":{'
	for i in range(SHIP_NAMES_IN_ORDER.size()):
		var ship_name: String = String(SHIP_NAMES_IN_ORDER[i])
		if i > 0:
			s += ","
		s += '"%s":%s' % [_json_escape(ship_name), _ship_spec_to_json(ships.get(ship_name, {}))]
	s += "}"
	s += "}"
	return s


static func _ship_spec_to_json(spec: Dictionary) -> String:
	# Fixed group order.
	var ship_name: String = _json_escape(String(spec.get("ship", "")))
	var s := "{"
	s += '"ship":"%s"' % ship_name
	s += ',"movement":%s' % _dict_to_json_object(spec.get("movement", {}))
	s += ',"energy":%s' % _dict_to_json_object(spec.get("energy", {}))
	s += ',"weapons":%s' % _dict_to_json_object(spec.get("weapons", {}))
	s += ',"abilities":%s' % _dict_to_json_object(spec.get("abilities", {}))
	s += ',"turret":%s' % _dict_to_json_object(spec.get("turret", {}))
	s += ',"economy":%s' % _dict_to_json_object(spec.get("economy", {}))
	s += ',"sensors":%s' % _dict_to_json_object(spec.get("sensors", {}))
	s += ',"soccer":%s' % _dict_to_json_object(spec.get("soccer", {}))
	s += ',"misc":%s' % _dict_to_json_object(spec.get("misc", {}))
	s += ',"extra":%s' % _dict_to_json_object(spec.get("extra", {}))
	s += "}"
	return s


static func _dict_to_json_object(d: Dictionary) -> String:
	var s := "{"
	var keys: Array = d.keys()
	keys.sort()
	for i in range(keys.size()):
		var k: String = String(keys[i])
		if i > 0:
			s += ","
		s += '"%s":%s' % [_json_escape(k), _scalar_to_json(d.get(k))]
	s += "}"
	return s


static func _scalar_to_json(v: Variant) -> String:
	var t := typeof(v)
	if t == TYPE_NIL:
		return "null"
	if t == TYPE_BOOL:
		return ("true" if bool(v) else "false")
	if t == TYPE_INT:
		return str(int(v))
	if t == TYPE_FLOAT:
		# Keep deterministic; avoid String(float) constructor.
		return str(float(v))
	# Everything else is encoded as string.
	return '"%s"' % _json_escape(String(v))


static func _json_escape(s: String) -> String:
	return String(s).replace("\\", "\\\\").replace('"', '\\"')


static func debug_warbird_json() -> Dictionary:
	var res: Dictionary = load_config()
	if not bool(res.get("ok", false)):
		return res
	var ships: Dictionary = res.get("ships", {})
	var wb: Dictionary = ships.get("Warbird", {})
	return {
		"ok": true,
		"ship": "Warbird",
		"json": JSON.stringify(wb),
		"spec": wb,
	}
