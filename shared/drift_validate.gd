## Driftline strict validators for versioned JSON contracts.
##
## NON-NEGOTIABLE:
## - All persistent JSON artifacts must include `format` and `schema_version`.
## - Unknown formats or schema versions must fail loudly.
## - Loaders must refuse to load invalid data (no silent defaults / mutation).

class_name DriftValidate

const FORMAT_TILESET_MANIFEST := "driftline.tileset"
const FORMAT_TILES_DEF := "driftline.tiles_def"
const FORMAT_MAP := "driftline.map"
const FORMAT_SERVER_CONFIG := "driftline.server_config"
const FORMAT_RULESET := "driftline.ruleset"

const SCHEMA_TILESET_MANIFEST := 1
const SCHEMA_TILES_DEF := 1
const SCHEMA_MAP := 1
const SCHEMA_SERVER_CONFIG := 2
const SCHEMA_RULESET_V1 := 1
const SCHEMA_RULESET_V2 := 2
const SCHEMA_RULESET_LATEST := SCHEMA_RULESET_V2

const TILE_SIZE := 16


static func _err(ctx: String, msg: String) -> String:
	return (ctx + ": " if ctx != "" else "") + msg


static func _require_dict(v, ctx: String, errors: Array[String]) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		errors.append(_err(ctx, "must be an object"))
		return {}
	return v as Dictionary


static func _require_array(v, ctx: String, errors: Array[String]) -> Array:
	if not (v is Array):
		errors.append(_err(ctx, "must be an array"))
		return []
	return v as Array


static func _require_string(v, ctx: String, errors: Array[String]) -> String:
	if typeof(v) != TYPE_STRING:
		errors.append(_err(ctx, "must be a string"))
		return ""
	return String(v)


static func _require_int(v, ctx: String, errors: Array[String]) -> int:
	if typeof(v) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append(_err(ctx, "must be a number"))
		return 0
	return int(v)


static func _require_bool(v, ctx: String, errors: Array[String]) -> bool:
	if typeof(v) != TYPE_BOOL:
		errors.append(_err(ctx, "must be a boolean"))
		return false
	return bool(v)


static func _validate_optional_number_range(d: Dictionary, key: String, ctx: String, min_v: float, max_v: float, errors: Array[String]) -> void:
	if not d.has(key):
		return
	var t := typeof(d.get(key))
	if t not in [TYPE_INT, TYPE_FLOAT]:
		errors.append(_err(ctx, "must be a number"))
		return
	var f := float(d.get(key))
	if f < min_v or f > max_v:
		errors.append(_err(ctx, "must be in range %.3f..%.3f" % [min_v, max_v]))


static func _validate_optional_int_range(d: Dictionary, key: String, ctx: String, min_v: int, max_v: int, errors: Array[String]) -> void:
	if not d.has(key):
		return
	var t := typeof(d.get(key))
	if t not in [TYPE_INT, TYPE_FLOAT]:
		errors.append(_err(ctx, "must be a number"))
		return
	var f := float(d.get(key))
	if absf(f - round(f)) > 0.000001:
		errors.append(_err(ctx, "must be an int"))
		return
	var i := int(round(f))
	if i < int(min_v) or i > int(max_v):
		errors.append(_err(ctx, "must be in range %d..%d" % [int(min_v), int(max_v)]))


static func validate_header(root: Dictionary, expected_format: String, expected_schema_version: int, ctx: String = "") -> Array[String]:
	var errors: Array[String] = []
	if not root.has("format"):
		errors.append(_err(ctx, "missing required field 'format'"))
	else:
		var fmt := _require_string(root.get("format"), ctx + ".format", errors)
		if fmt != "" and fmt != expected_format:
			errors.append(_err(ctx, "unknown format '%s' (expected '%s')" % [fmt, expected_format]))

	if not root.has("schema_version"):
		errors.append(_err(ctx, "missing required field 'schema_version'"))
	else:
		var sv := _require_int(root.get("schema_version"), ctx + ".schema_version", errors)
		if sv != expected_schema_version:
			errors.append(_err(ctx, "unsupported schema_version %d (expected %d)" % [sv, expected_schema_version]))

	return errors


static func validate_tileset_manifest(manifest: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	errors.append_array(validate_header(manifest, FORMAT_TILESET_MANIFEST, SCHEMA_TILESET_MANIFEST, "tileset"))

	var name := _require_string(manifest.get("name"), "tileset.name", errors)
	var image := _require_string(manifest.get("image"), "tileset.image", errors)
	var tile_size_arr := _require_array(manifest.get("tile_size"), "tileset.tile_size", errors)
	if tile_size_arr.size() != 2:
		errors.append(_err("tileset.tile_size", "must be [w,h]"))
	var tw := 0
	var th := 0
	if tile_size_arr.size() == 2:
		tw = _require_int(tile_size_arr[0], "tileset.tile_size[0]", errors)
		th = _require_int(tile_size_arr[1], "tileset.tile_size[1]", errors)
		if tw != TILE_SIZE or th != TILE_SIZE:
			errors.append(_err("tileset.tile_size", "must be [%d,%d]" % [TILE_SIZE, TILE_SIZE]))

	if name.strip_edges() == "":
		errors.append(_err("tileset.name", "must be non-empty"))
	if image.strip_edges() == "":
		errors.append(_err("tileset.image", "must be non-empty"))

	# Keep canonical manifest.
	var canonical := {
		"format": FORMAT_TILESET_MANIFEST,
		"schema_version": SCHEMA_TILESET_MANIFEST,
		"name": name,
		"image": image,
		"tile_size": [TILE_SIZE, TILE_SIZE],
	}

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"manifest": canonical,
	}


static func _render_layer_to_layer(render_layer: String) -> String:
	var rl := String(render_layer)
	if rl == "solid":
		return "mid"
	if rl in ["bg", "mid", "fg"]:
		return rl
	if rl == "fg":
		return "fg"
	return "mid"


static func validate_tiles_def(defs: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	errors.append_array(validate_header(defs, FORMAT_TILES_DEF, SCHEMA_TILES_DEF, "tiles_def"))

	# Strict root shape.
	for k in defs.keys():
		var key := String(k)
		if key not in ["format", "schema_version", "defaults", "tiles", "reserved"]:
			errors.append(_err("tiles_def", "unknown top-level key '%s'" % key))

	# Required objects.
	var defaults := _require_dict(defs.get("defaults"), "tiles_def.defaults", errors)
	var tiles := _require_dict(defs.get("tiles"), "tiles_def.tiles", errors)

	# Defaults: must include at least solid + layer.
	var solid_default := _require_bool(defaults.get("solid"), "tiles_def.defaults.solid", errors)
	var layer_default := ""
	if defaults.has("layer"):
		layer_default = _require_string(defaults.get("layer"), "tiles_def.defaults.layer", errors)
	elif defaults.has("render_layer"):
		# Deprecated dialect support: accept render_layer but canonicalize to layer.
		layer_default = _render_layer_to_layer(_require_string(defaults.get("render_layer"), "tiles_def.defaults.render_layer", errors))
	else:
		errors.append(_err("tiles_def.defaults", "missing required field 'layer'"))

	if layer_default not in ["bg", "mid", "fg"]:
		errors.append(_err("tiles_def.defaults.layer", "must be one of: bg, mid, fg"))

	# Defaults may only include known keys.
	for dk in defaults.keys():
		var dks := String(dk)
		if dks not in ["solid", "layer", "render_layer"]:
			errors.append(_err("tiles_def.defaults", "unknown key '%s'" % dks))

	# Validate tile overrides.
	var canonical_tiles: Dictionary = {}
	for k in tiles.keys():
		var key := String(k)
		var parts := key.split(",")
		if parts.size() != 2:
			errors.append(_err("tiles_def.tiles", "invalid tile key '%s' (expected 'ax,ay')" % key))
			continue
		var ax := int(parts[0])
		var ay := int(parts[1])
		if ax < 0 or ay < 0:
			errors.append(_err("tiles_def.tiles['%s']" % key, "atlas coords must be >= 0"))
			continue

		var ov = tiles[k]
		if typeof(ov) != TYPE_DICTIONARY:
			errors.append(_err("tiles_def.tiles['%s']" % key, "must be an object"))
			continue
		var o: Dictionary = ov

		var canon_o: Dictionary = {}
		for field in o.keys():
			canon_o[field] = o[field]

		# Normalize dialect: render_layer -> layer.
		if canon_o.has("render_layer") and not canon_o.has("layer"):
			canon_o["layer"] = _render_layer_to_layer(String(canon_o.get("render_layer")))
		if canon_o.has("render_layer"):
			canon_o.erase("render_layer")

		# Unknown tile override keys are forbidden (schema is versioned).
		for okk in canon_o.keys():
			var okks := String(okk)
			if okks not in ["solid", "layer", "door", "safe_zone"]:
				errors.append(_err("tiles_def.tiles['%s']" % key, "unknown key '%s'" % okks))

		# Validate known fields when present.
		if canon_o.has("solid") and typeof(canon_o["solid"]) != TYPE_BOOL:
			errors.append(_err("tiles_def.tiles['%s'].solid" % key, "must be a boolean"))
		if canon_o.has("door") and typeof(canon_o["door"]) != TYPE_BOOL:
			errors.append(_err("tiles_def.tiles['%s'].door" % key, "must be a boolean"))
		if canon_o.has("safe_zone") and typeof(canon_o["safe_zone"]) != TYPE_BOOL:
			errors.append(_err("tiles_def.tiles['%s'].safe_zone" % key, "must be a boolean"))
		if canon_o.has("layer"):
			var lay := _require_string(canon_o.get("layer"), "tiles_def.tiles['%s'].layer" % key, errors)
			if lay not in ["bg", "mid", "fg"]:
				errors.append(_err("tiles_def.tiles['%s'].layer" % key, "must be one of: bg, mid, fg"))

		canonical_tiles[key] = canon_o

	# Reserved section is optional but must be well-typed if present.
	var reserved_out: Dictionary = {}
	if defs.has("reserved"):
		var reserved := _require_dict(defs.get("reserved"), "tiles_def.reserved", errors)
		for rk in reserved.keys():
			var rks := String(rk)
			if rks != "doors":
				errors.append(_err("tiles_def.reserved", "unknown key '%s'" % rks))
		# Only validate the reserved.doors shape if present.
		if reserved.has("doors"):
			var doors := _require_dict(reserved.get("doors"), "tiles_def.reserved.doors", errors)
			for dk in doors.keys():
				var dks := String(dk)
				if dks not in ["frames", "solid_when_closed", "comment"]:
					errors.append(_err("tiles_def.reserved.doors", "unknown key '%s'" % dks))
			if doors.has("frames"):
				var frames := _require_array(doors.get("frames"), "tiles_def.reserved.doors.frames", errors)
				for i in range(frames.size()):
					if typeof(frames[i]) != TYPE_STRING:
						errors.append(_err("tiles_def.reserved.doors.frames[%d]" % i, "must be a string 'ax,ay'"))
			if doors.has("solid_when_closed") and typeof(doors.get("solid_when_closed")) != TYPE_BOOL:
				errors.append(_err("tiles_def.reserved.doors.solid_when_closed", "must be a boolean"))
			if doors.has("comment") and typeof(doors.get("comment")) != TYPE_STRING:
				errors.append(_err("tiles_def.reserved.doors.comment", "must be a string"))
			reserved_out["doors"] = doors
		reserved_out = reserved

	var canonical := {
		"format": FORMAT_TILES_DEF,
		"schema_version": SCHEMA_TILES_DEF,
		"defaults": {
			"layer": layer_default,
			"solid": solid_default,
		},
		"tiles": canonical_tiles,
	}
	if not reserved_out.is_empty():
		canonical["reserved"] = reserved_out

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"tiles_def": canonical,
	}


static func validate_map(map_root: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	errors.append_array(validate_header(map_root, FORMAT_MAP, SCHEMA_MAP, "map"))

	# Strict root shape.
	for k in map_root.keys():
		var key := String(k)
		if key not in ["format", "schema_version", "meta", "layers", "entities"]:
			errors.append(_err("map", "unknown top-level key '%s'" % key))

	var meta := _require_dict(map_root.get("meta"), "map.meta", errors)
	var layers := _require_dict(map_root.get("layers"), "map.layers", errors)
	var entities := _require_array(map_root.get("entities"), "map.entities", errors)

	# Meta
	if meta.has("tileset_path"):
		errors.append(_err("map.meta.tileset_path", "forbidden (derived); use meta.tileset"))

	var w := _require_int(meta.get("w"), "map.meta.w", errors)
	var h := _require_int(meta.get("h"), "map.meta.h", errors)
	var tile_size := _require_int(meta.get("tile_size"), "map.meta.tile_size", errors)
	var tileset := _require_string(meta.get("tileset"), "map.meta.tileset", errors)
	if w < 2 or h < 2:
		errors.append(_err("map.meta", "w and h must be >= 2"))
	if tile_size != TILE_SIZE:
		errors.append(_err("map.meta.tile_size", "must be %d" % TILE_SIZE))
	if tileset.strip_edges() == "":
		errors.append(_err("map.meta.tileset", "must be non-empty"))

	# Optional door timing metadata.
	var door_keys := ["door_open_seconds", "door_closed_seconds", "door_frame_seconds"]
	for dk in door_keys:
		if meta.has(dk) and typeof(meta.get(dk)) not in [TYPE_INT, TYPE_FLOAT]:
			errors.append(_err("map.meta.%s" % dk, "must be a number"))
	if meta.has("door_start_open") and typeof(meta.get("door_start_open")) != TYPE_BOOL:
		errors.append(_err("map.meta.door_start_open", "must be a boolean"))

	# Unknown meta keys must be scalar (prevents embedding behavior blobs).
	for mk in meta.keys():
		var mks := String(mk)
		if mks in ["w", "h", "tile_size", "tileset"] + door_keys + ["door_start_open"]:
			continue
		var tv := typeof(meta[mk])
		if tv in [TYPE_DICTIONARY, TYPE_ARRAY, TYPE_OBJECT]:
			errors.append(_err("map.meta.%s" % mks, "must be a scalar (string/number/bool)"))

	# Layers
	for layer_key in layers.keys():
		var lk := String(layer_key)
		if lk not in ["bg", "solid", "fg"]:
			errors.append(_err("map.layers", "unknown layer '%s'" % lk))

	var out_layers: Dictionary = {"bg": [], "solid": [], "fg": []}
	for layer_name in ["bg", "solid", "fg"]:
		var cells_in := _require_array(layers.get(layer_name), "map.layers.%s" % layer_name, errors)
		var seen: Dictionary = {}
		for i in range(cells_in.size()):
			var cell = cells_in[i]
			if not (cell is Array) or (cell as Array).size() != 4:
				errors.append(_err("map.layers.%s[%d]" % [layer_name, i], "must be [x,y,ax,ay]"))
				continue
			var arr: Array = cell
			var x := int(arr[0])
			var y := int(arr[1])
			var ax := int(arr[2])
			var ay := int(arr[3])
			if x < 0 or y < 0 or x >= w or y >= h:
				errors.append(_err("map.layers.%s[%d]" % [layer_name, i], "out of bounds (%d,%d)" % [x, y]))
				continue
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				errors.append(_err("map.layers.%s[%d]" % [layer_name, i], "on boundary (%d,%d); boundary is engine-generated" % [x, y]))
				continue
			if ax < 0 or ay < 0:
				errors.append(_err("map.layers.%s[%d]" % [layer_name, i], "invalid atlas coords (%d,%d)" % [ax, ay]))
				continue
			var key := "%d,%d" % [x, y]
			if seen.has(key):
				errors.append(_err("map.layers.%s" % layer_name, "duplicate cell at (%d,%d)" % [x, y]))
				continue
			seen[key] = [x, y, ax, ay]

		var cells_out: Array = seen.values()
		cells_out.sort_custom(Callable(DriftValidate, "_tile_less"))
		out_layers[layer_name] = cells_out

	# Entities
	var allowed := {"spawn": true, "flag": true, "base": true}
	var entities_seen: Dictionary = {}
	var entities_out: Array = []
	for i in range(entities.size()):
		var e = entities[i]
		if typeof(e) != TYPE_DICTIONARY:
			errors.append(_err("map.entities[%d]" % i, "must be an object"))
			continue
		var d: Dictionary = e
		for ek in d.keys():
			var eks := String(ek)
			if eks not in ["type", "x", "y", "team"]:
				errors.append(_err("map.entities[%d]" % i, "unknown key '%s'" % eks))
		var t := _require_string(d.get("type"), "map.entities[%d].type" % i, errors)
		if not allowed.has(t):
			errors.append(_err("map.entities[%d].type" % i, "invalid type '%s'" % t))
			continue
		var ex := _require_int(d.get("x"), "map.entities[%d].x" % i, errors)
		var ey := _require_int(d.get("y"), "map.entities[%d].y" % i, errors)
		var team := 0
		if d.has("team"):
			team = _require_int(d.get("team"), "map.entities[%d].team" % i, errors)
		if ex < 0 or ey < 0 or ex >= w or ey >= h:
			errors.append(_err("map.entities[%d]" % i, "out of bounds (%d,%d)" % [ex, ey]))
			continue
		if ex == 0 or ey == 0 or ex == w - 1 or ey == h - 1:
			errors.append(_err("map.entities[%d]" % i, "on boundary (%d,%d); boundary is reserved" % [ex, ey]))
			continue
		var key2 := "%s:%d,%d" % [t, ex, ey]
		if entities_seen.has(key2):
			errors.append(_err("map.entities", "duplicate '%s' at (%d,%d)" % [t, ex, ey]))
			continue
		entities_seen[key2] = true
		entities_out.append({"type": t, "x": ex, "y": ey, "team": team})

	entities_out.sort_custom(Callable(DriftValidate, "_entity_less"))

	var out_meta: Dictionary = {
		"w": w,
		"h": h,
		"tile_size": TILE_SIZE,
		"tileset": tileset,
	}
	for dk in door_keys:
		if meta.has(dk):
			out_meta[dk] = float(meta.get(dk))
	if meta.has("door_start_open"):
		out_meta["door_start_open"] = bool(meta.get("door_start_open"))
	# Preserve additional scalar meta keys.
	for mk in meta.keys():
		var mks := String(mk)
		if out_meta.has(mks):
			continue
		var tv := typeof(meta[mk])
		if tv in [TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
			out_meta[mks] = meta[mk]

	var canonical := {
		"format": FORMAT_MAP,
		"schema_version": SCHEMA_MAP,
		"meta": out_meta,
		"layers": out_layers,
		"entities": entities_out,
	}

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"map": canonical,
	}


static func validate_tiles_def_dict(defs: Dictionary) -> Dictionary:
	# Minimal wrapper for headless contract tests.
	# Returns: { ok: bool, error?: String }
	var res := validate_tiles_def(defs)
	if bool(res.get("ok", false)):
		return {"ok": true}
	var err_text := "tiles_def validation failed"
	for e in (res.get("errors", []) as Array):
		err_text += "\n - " + String(e)
	return {"ok": false, "error": err_text}


static func validate_map_dict(map_root: Dictionary) -> Dictionary:
	# Minimal wrapper for headless contract tests.
	# Returns: { ok: bool, error?: String }
	var res := validate_map(map_root)
	if bool(res.get("ok", false)):
		return {"ok": true}
	var err_text := "map validation failed"
	for e in (res.get("errors", []) as Array):
		err_text += "\n - " + String(e)
	return {"ok": false, "error": err_text}


static func validate_server_config(root: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	errors.append_array(validate_header(root, FORMAT_SERVER_CONFIG, SCHEMA_SERVER_CONFIG, "server_config"))

	# Strict shape.
	for k in root.keys():
		var key := String(k)
		if key not in ["format", "schema_version", "default_map", "default_tileset", "ruleset"]:
			errors.append(_err("server_config", "unknown top-level key '%s'" % key))

	if not root.has("default_map"):
		errors.append(_err("server_config", "missing required field 'default_map'"))
	if not root.has("ruleset"):
		errors.append(_err("server_config", "missing required field 'ruleset'"))

	var default_map := _require_string(root.get("default_map"), "server_config.default_map", errors).strip_edges()
	if default_map == "":
		errors.append(_err("server_config.default_map", "must be non-empty"))
	elif not (default_map.begins_with("res://") or default_map.begins_with("user://")):
		errors.append(_err("server_config.default_map", "must start with res:// or user://"))

	var ruleset_path := _require_string(root.get("ruleset"), "server_config.ruleset", errors).strip_edges()
	if ruleset_path == "":
		errors.append(_err("server_config.ruleset", "must be non-empty"))
	elif not (ruleset_path.begins_with("res://") or ruleset_path.begins_with("user://")):
		errors.append(_err("server_config.ruleset", "must start with res:// or user://"))

	var default_tileset := ""
	var has_tileset := root.has("default_tileset")
	if has_tileset:
		default_tileset = _require_string(root.get("default_tileset"), "server_config.default_tileset", errors).strip_edges()
		if default_tileset == "":
			errors.append(_err("server_config.default_tileset", "must be non-empty when present"))
		elif not (default_tileset.begins_with("res://") or default_tileset.begins_with("user://")):
			errors.append(_err("server_config.default_tileset", "must start with res:// or user://"))

	var canonical := {
		"format": FORMAT_SERVER_CONFIG,
		"schema_version": SCHEMA_SERVER_CONFIG,
		"default_map": default_map,
		"ruleset": ruleset_path,
	}
	if has_tileset:
		canonical["default_tileset"] = default_tileset

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"server_config": canonical,
	}


static func validate_ruleset(root: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	const DEFAULT_UI_LOW_ENERGY_FRAC := 0.33
	const DEFAULT_UI_CRITICAL_ENERGY_FRAC := 0.15

	# Rulesets support multiple schema versions (legacy + latest).
	# Unknown schema versions must fail loudly.
	var schema_version: int = 0
	if not root.has("format"):
		errors.append(_err("ruleset", "missing required field 'format'"))
	else:
		var fmt := _require_string(root.get("format"), "ruleset.format", errors)
		if fmt != "" and fmt != FORMAT_RULESET:
			errors.append(_err("ruleset", "unknown format '%s' (expected '%s')" % [fmt, FORMAT_RULESET]))

	if not root.has("schema_version"):
		errors.append(_err("ruleset", "missing required field 'schema_version'"))
	else:
		schema_version = _require_int(root.get("schema_version"), "ruleset.schema_version", errors)
		if schema_version not in [SCHEMA_RULESET_V1, SCHEMA_RULESET_V2]:
			errors.append(_err("ruleset", "unsupported schema_version %d (supported: %d, %d)" % [schema_version, SCHEMA_RULESET_V1, SCHEMA_RULESET_V2]))

	# Strict top-level shape (varies by schema version).
	var top_allowed: Dictionary = {
		"format": true,
		"schema_version": true,
		"physics": true,
		"weapons": true,
		"energy": true,
		"ships": true,
	}
	if schema_version == SCHEMA_RULESET_V2:
		top_allowed["abilities"] = true
		top_allowed["combat"] = true
		top_allowed["team"] = true
		top_allowed["zones"] = true
		top_allowed["ui"] = true
	for k in root.keys():
		var key := String(k)
		if not top_allowed.has(key):
			errors.append(_err("ruleset", "unknown top-level key '%s'" % key))

	var physics := _require_dict(root.get("physics"), "ruleset.physics", errors)

	# Optional combat section (schema v2 only).
	var combat: Dictionary = {}
	if root.has("combat"):
		if schema_version != SCHEMA_RULESET_V2:
			errors.append(_err("ruleset", "'combat' is only supported in schema_version %d" % SCHEMA_RULESET_V2))
		else:
			combat = _require_dict(root.get("combat"), "ruleset.combat", errors)
			var combat_allowed := {
				"spawn_protect_ms": true,
				"respawn_delay_ms": true,
				"friendly_fire": true,
			}
			for ck in combat.keys():
				var cks := String(ck)
				if not combat_allowed.has(cks):
					errors.append(_err("ruleset.combat", "unknown key '%s'" % cks))
			_validate_optional_number_range(combat, "spawn_protect_ms", "ruleset.combat.spawn_protect_ms", 0.0, 600000.0, errors)
			_validate_optional_number_range(combat, "respawn_delay_ms", "ruleset.combat.respawn_delay_ms", 0.0, 600000.0, errors)
			if combat.has("friendly_fire") and typeof(combat.get("friendly_fire")) != TYPE_BOOL:
				errors.append(_err("ruleset.combat.friendly_fire", "must be a boolean"))

	# Optional team section (schema v2 only).
	var team: Dictionary = {}
	if root.has("team"):
		if schema_version != SCHEMA_RULESET_V2:
			errors.append(_err("ruleset", "'team' is only supported in schema_version %d" % SCHEMA_RULESET_V2))
		else:
			team = _require_dict(root.get("team"), "ruleset.team", errors)
			var team_allowed := {
				"max_freq": true,
				"force_even": true,
			}
			for tk in team.keys():
				var tks := String(tk)
				if not team_allowed.has(tks):
					errors.append(_err("ruleset.team", "unknown key '%s'" % tks))
			_validate_optional_int_range(team, "max_freq", "ruleset.team.max_freq", 0, 16, errors)
			if team.has("force_even") and typeof(team.get("force_even")) != TYPE_BOOL:
				errors.append(_err("ruleset.team.force_even", "must be a boolean"))

	# Optional zones section (schema v2 only).
	var zones: Dictionary = {}
	if root.has("zones"):
		if schema_version != SCHEMA_RULESET_V2:
			errors.append(_err("ruleset", "'zones' is only supported in schema_version %d" % SCHEMA_RULESET_V2))
		else:
			zones = _require_dict(root.get("zones"), "ruleset.zones", errors)
			var zones_allowed := {
				"safe_zone_max_ms": true,
			}
			for zk in zones.keys():
				var zks := String(zk)
				if not zones_allowed.has(zks):
					errors.append(_err("ruleset.zones", "unknown key '%s'" % zks))
			_validate_optional_number_range(zones, "safe_zone_max_ms", "ruleset.zones.safe_zone_max_ms", 0.0, 600000.0, errors)

	# Optional UI section (schema v2 only).
	var ui: Dictionary = {}
	var ui_low_energy_frac: float = DEFAULT_UI_LOW_ENERGY_FRAC
	var ui_critical_energy_frac: float = DEFAULT_UI_CRITICAL_ENERGY_FRAC
	if root.has("ui"):
		if schema_version != SCHEMA_RULESET_V2:
			errors.append(_err("ruleset", "'ui' is only supported in schema_version %d" % SCHEMA_RULESET_V2))
		else:
			ui = _require_dict(root.get("ui"), "ruleset.ui", errors)
			var ui_allowed := {
				"low_energy_frac": true,
				"critical_energy_frac": true,
			}
			for uk in ui.keys():
				var uks := String(uk)
				if not ui_allowed.has(uks):
					errors.append(_err("ruleset.ui", "unknown key '%s'" % uks))
			_validate_optional_number_range(ui, "low_energy_frac", "ruleset.ui.low_energy_frac", 0.0, 1.0, errors)
			_validate_optional_number_range(ui, "critical_energy_frac", "ruleset.ui.critical_energy_frac", 0.0, 1.0, errors)

			# Cross-field constraint (using engine defaults if missing).
			if ui.has("low_energy_frac"):
				ui_low_energy_frac = float(ui.get("low_energy_frac"))
			if ui.has("critical_energy_frac"):
				ui_critical_energy_frac = float(ui.get("critical_energy_frac"))
			if ui_critical_energy_frac > ui_low_energy_frac:
				errors.append(_err("ruleset.ui", "critical_energy_frac must be <= low_energy_frac"))

	# Strict physics keys.
	var physics_allowed := {
		"wall_restitution": true,
		"tangent_damping": true,
		"ship_turn_rate": true,
		"ship_thrust_accel": true,
		"ship_reverse_accel": true,
		"ship_max_speed": true,
		"ship_base_drag": true,
		"ship_overspeed_drag": true,
		"ship_bounce_min_normal_speed": true,
	}
	for pk in physics.keys():
		var pks := String(pk)
		if not physics_allowed.has(pks):
			errors.append(_err("ruleset.physics", "unknown key '%s'" % pks))

	# Required physics.wall_restitution
	var wall_rest: float = 0.0
	if not physics.has("wall_restitution"):
		errors.append(_err("ruleset.physics", "missing required field 'wall_restitution'"))
	else:
		var tv := typeof(physics.get("wall_restitution"))
		if tv not in [TYPE_INT, TYPE_FLOAT]:
			errors.append(_err("ruleset.physics.wall_restitution", "must be a number"))
		else:
			wall_rest = float(physics.get("wall_restitution"))
			if wall_rest < 0.0 or wall_rest > 2.0:
				errors.append(_err("ruleset.physics.wall_restitution", "must be in range 0.0..2.0"))

	# Optional physics (validated when present).
	_validate_optional_number_range(physics, "tangent_damping", "ruleset.physics.tangent_damping", 0.0, 1.0, errors)
	_validate_optional_number_range(physics, "ship_turn_rate", "ruleset.physics.ship_turn_rate", 0.0, 20.0, errors)
	_validate_optional_number_range(physics, "ship_thrust_accel", "ruleset.physics.ship_thrust_accel", 0.0, 5000.0, errors)
	_validate_optional_number_range(physics, "ship_reverse_accel", "ruleset.physics.ship_reverse_accel", 0.0, 5000.0, errors)
	_validate_optional_number_range(physics, "ship_max_speed", "ruleset.physics.ship_max_speed", 0.0, 5000.0, errors)
	_validate_optional_number_range(physics, "ship_base_drag", "ruleset.physics.ship_base_drag", 0.0, 10.0, errors)
	_validate_optional_number_range(physics, "ship_overspeed_drag", "ruleset.physics.ship_overspeed_drag", 0.0, 50.0, errors)
	_validate_optional_number_range(physics, "ship_bounce_min_normal_speed", "ruleset.physics.ship_bounce_min_normal_speed", 0.0, 2000.0, errors)

	# Optional weapons section.
	var weapons: Dictionary = {}
	var bullet: Dictionary = {}
	if root.has("weapons"):
		weapons = _require_dict(root.get("weapons"), "ruleset.weapons", errors)
		var weapons_allowed := {
			"ball_friction": true,
			"ball_max_speed": true,
			"ball_kick_speed": true,
			"ball_knock_impulse": true,
			"ball_stick_offset": true,
			"ball_steal_padding": true,
			"bullet": true,
		}
		for wk in weapons.keys():
			var wks := String(wk)
			if not weapons_allowed.has(wks):
				errors.append(_err("ruleset.weapons", "unknown key '%s'" % wks))
		_validate_optional_number_range(weapons, "ball_friction", "ruleset.weapons.ball_friction", 0.0, 1.0, errors)
		_validate_optional_number_range(weapons, "ball_max_speed", "ruleset.weapons.ball_max_speed", 0.0, 5000.0, errors)
		_validate_optional_number_range(weapons, "ball_kick_speed", "ruleset.weapons.ball_kick_speed", 0.0, 5000.0, errors)
		_validate_optional_number_range(weapons, "ball_knock_impulse", "ruleset.weapons.ball_knock_impulse", 0.0, 5000.0, errors)
		_validate_optional_number_range(weapons, "ball_stick_offset", "ruleset.weapons.ball_stick_offset", 0.0, 200.0, errors)
		_validate_optional_number_range(weapons, "ball_steal_padding", "ruleset.weapons.ball_steal_padding", 0.0, 128.0, errors)

		if weapons.has("bullet"):
			bullet = _require_dict(weapons.get("bullet"), "ruleset.weapons.bullet", errors)
			var bullet_allowed := {
				"speed": true,
				"damage": true,
				"knock_impulse": true,
				"cooldown_ticks": true,
				"spread_deg": true,
				"shrapnel_count": true,
				"shrapnel_speed_mult": true,
				"shrapnel_lifetime_s": true,
				"shrapnel_cone_deg": true,
				"lifetime_s": true,
				"muzzle_offset": true,
				"bounces": true,
				"bounce_restitution": true,
				"levels": true,
			}
			for bk in bullet.keys():
				var bks := String(bk)
				if not bullet_allowed.has(bks):
					errors.append(_err("ruleset.weapons.bullet", "unknown key '%s'" % bks))
			_validate_optional_number_range(bullet, "speed", "ruleset.weapons.bullet.speed", 0.0, 5000.0, errors)
			_validate_optional_number_range(bullet, "damage", "ruleset.weapons.bullet.damage", 0.0, 10000.0, errors)
			_validate_optional_number_range(bullet, "knock_impulse", "ruleset.weapons.bullet.knock_impulse", 0.0, 5000.0, errors)
			if bullet.has("cooldown_ticks"):
				var ct := typeof(bullet.get("cooldown_ticks"))
				if ct not in [TYPE_INT, TYPE_FLOAT]:
					errors.append(_err("ruleset.weapons.bullet.cooldown_ticks", "must be a number"))
				else:
					var ci := int(bullet.get("cooldown_ticks"))
					if ci < 0 or ci > 120:
						errors.append(_err("ruleset.weapons.bullet.cooldown_ticks", "must be in range 0..120"))
			_validate_optional_number_range(bullet, "spread_deg", "ruleset.weapons.bullet.spread_deg", 0.0, 45.0, errors)
			if bullet.has("shrapnel_count"):
				var st := typeof(bullet.get("shrapnel_count"))
				if st not in [TYPE_INT, TYPE_FLOAT]:
					errors.append(_err("ruleset.weapons.bullet.shrapnel_count", "must be a number"))
				else:
					var si := int(bullet.get("shrapnel_count"))
					if si < 0 or si > 16:
						errors.append(_err("ruleset.weapons.bullet.shrapnel_count", "must be in range 0..16"))
			_validate_optional_number_range(bullet, "shrapnel_speed_mult", "ruleset.weapons.bullet.shrapnel_speed_mult", 0.0, 2.0, errors)
			_validate_optional_number_range(bullet, "shrapnel_lifetime_s", "ruleset.weapons.bullet.shrapnel_lifetime_s", 0.0, 5.0, errors)
			_validate_optional_number_range(bullet, "shrapnel_cone_deg", "ruleset.weapons.bullet.shrapnel_cone_deg", 0.0, 360.0, errors)
			_validate_optional_number_range(bullet, "lifetime_s", "ruleset.weapons.bullet.lifetime_s", 0.0, 10.0, errors)
			_validate_optional_number_range(bullet, "muzzle_offset", "ruleset.weapons.bullet.muzzle_offset", 0.0, 64.0, errors)
			if bullet.has("bounces"):
				var bt := typeof(bullet.get("bounces"))
				if bt not in [TYPE_INT, TYPE_FLOAT]:
					errors.append(_err("ruleset.weapons.bullet.bounces", "must be a number"))
				else:
					var bi := int(bullet.get("bounces"))
					if bi < 0 or bi > 16:
						errors.append(_err("ruleset.weapons.bullet.bounces", "must be in range 0..16"))
			_validate_optional_number_range(bullet, "bounce_restitution", "ruleset.weapons.bullet.bounce_restitution", 0.0, 2.0, errors)
			# Optional: bullet level profiles
			if bullet.has("levels"):
				var levels := _require_dict(bullet.get("levels"), "ruleset.weapons.bullet.levels", errors)
				for lk in levels.keys():
					var lks := String(lk)
					if not lks.is_valid_int():
						errors.append(_err("ruleset.weapons.bullet.levels", "level key '%s' must be an integer string" % lks))
						continue
					var level_i := int(lks)
					if level_i < 1 or level_i > 3:
						errors.append(_err("ruleset.weapons.bullet.levels", "level key '%s' must be in range 1..3" % lks))
						continue
					var lvl := _require_dict(levels.get(lk), "ruleset.weapons.bullet.levels.%s" % lks, errors)
					var lvl_allowed := {
						"guns": true,
						"multi_fire": true,
						"speed": true,
						"damage": true,
						"knock_impulse": true,
						"cooldown_ticks": true,
						"spread_deg": true,
						"shrapnel_count": true,
						"shrapnel_speed_mult": true,
						"shrapnel_lifetime_s": true,
						"shrapnel_cone_deg": true,
						"lifetime_s": true,
						"muzzle_offset": true,
						"bounces": true,
						"bounce_restitution": true,
					}
					for k2 in lvl.keys():
						var k2s := String(k2)
						if not lvl_allowed.has(k2s):
							errors.append(_err("ruleset.weapons.bullet.levels.%s" % lks, "unknown key '%s'" % k2s))
					if lvl.has("guns"):
						var guns_t := typeof(lvl.get("guns"))
						if guns_t not in [TYPE_INT, TYPE_FLOAT]:
							errors.append(_err("ruleset.weapons.bullet.levels.%s.guns" % lks, "must be a number"))
						else:
							var guns_i := int(lvl.get("guns"))
							if guns_i < 1 or guns_i > 8:
								errors.append(_err("ruleset.weapons.bullet.levels.%s.guns" % lks, "must be in range 1..8"))
					if lvl.has("multi_fire") and typeof(lvl.get("multi_fire")) != TYPE_BOOL:
						errors.append(_err("ruleset.weapons.bullet.levels.%s.multi_fire" % lks, "must be a boolean"))
					_validate_optional_number_range(lvl, "speed", "ruleset.weapons.bullet.levels.%s.speed" % lks, 0.0, 5000.0, errors)
					if lvl.has("cooldown_ticks"):
						var ct2 := typeof(lvl.get("cooldown_ticks"))
						if ct2 not in [TYPE_INT, TYPE_FLOAT]:
							errors.append(_err("ruleset.weapons.bullet.levels.%s.cooldown_ticks" % lks, "must be a number"))
						else:
							var ci2 := int(lvl.get("cooldown_ticks"))
							if ci2 < 0 or ci2 > 120:
								errors.append(_err("ruleset.weapons.bullet.levels.%s.cooldown_ticks" % lks, "must be in range 0..120"))
					_validate_optional_number_range(lvl, "spread_deg", "ruleset.weapons.bullet.levels.%s.spread_deg" % lks, 0.0, 45.0, errors)
					if lvl.has("shrapnel_count"):
						var st2 := typeof(lvl.get("shrapnel_count"))
						if st2 not in [TYPE_INT, TYPE_FLOAT]:
							errors.append(_err("ruleset.weapons.bullet.levels.%s.shrapnel_count" % lks, "must be a number"))
						else:
							var si2 := int(lvl.get("shrapnel_count"))
							if si2 < 0 or si2 > 16:
								errors.append(_err("ruleset.weapons.bullet.levels.%s.shrapnel_count" % lks, "must be in range 0..16"))
					_validate_optional_number_range(lvl, "shrapnel_speed_mult", "ruleset.weapons.bullet.levels.%s.shrapnel_speed_mult" % lks, 0.0, 2.0, errors)
					_validate_optional_number_range(lvl, "shrapnel_lifetime_s", "ruleset.weapons.bullet.levels.%s.shrapnel_lifetime_s" % lks, 0.0, 5.0, errors)
					_validate_optional_number_range(lvl, "shrapnel_cone_deg", "ruleset.weapons.bullet.levels.%s.shrapnel_cone_deg" % lks, 0.0, 360.0, errors)
					_validate_optional_number_range(lvl, "lifetime_s", "ruleset.weapons.bullet.levels.%s.lifetime_s" % lks, 0.0, 10.0, errors)
					_validate_optional_number_range(lvl, "muzzle_offset", "ruleset.weapons.bullet.levels.%s.muzzle_offset" % lks, 0.0, 64.0, errors)
					if lvl.has("bounces"):
						var lbt := typeof(lvl.get("bounces"))
						if lbt not in [TYPE_INT, TYPE_FLOAT]:
							errors.append(_err("ruleset.weapons.bullet.levels.%s.bounces" % lks, "must be a number"))
						else:
							var lbi := int(lvl.get("bounces"))
							if lbi < 0 or lbi > 16:
								errors.append(_err("ruleset.weapons.bullet.levels.%s.bounces" % lks, "must be in range 0..16"))
					_validate_optional_number_range(lvl, "bounce_restitution", "ruleset.weapons.bullet.levels.%s.bounce_restitution" % lks, 0.0, 2.0, errors)

	# Optional per-ship overrides.
	var ships: Dictionary = {}
	if root.has("ships"):
		ships = _require_dict(root.get("ships"), "ruleset.ships", errors)
		for sk in ships.keys():
			var ship_key := String(sk)
			if not ship_key.is_valid_int():
				errors.append(_err("ruleset.ships", "ship id key '%s' must be an integer string" % ship_key))
				continue
			var ship_id := int(ship_key)
			if ship_id <= 0:
				errors.append(_err("ruleset.ships", "ship id key '%s' must be > 0" % ship_key))
				continue
			var ship_obj := _require_dict(ships.get(sk), "ruleset.ships.%s" % ship_key, errors)
			for k in ship_obj.keys():
				var ks := String(k)
				if ks not in ["weapons"]:
					errors.append(_err("ruleset.ships.%s" % ship_key, "unknown key '%s'" % ks))
			if ship_obj.has("weapons"):
				var ship_weapons := _require_dict(ship_obj.get("weapons"), "ruleset.ships.%s.weapons" % ship_key, errors)
				for wk in ship_weapons.keys():
					var wks := String(wk)
					if wks not in ["bullet"]:
						errors.append(_err("ruleset.ships.%s.weapons" % ship_key, "unknown key '%s'" % wks))
				if ship_weapons.has("bullet"):
					var ship_bullet := _require_dict(ship_weapons.get("bullet"), "ruleset.ships.%s.weapons.bullet" % ship_key, errors)
					var ship_bullet_allowed := {
						"level": true,
						"multishot": true,
						"bounce": true,
						"guns": true,
						"multi_fire": true,
						"speed": true,
						"cooldown_ticks": true,
						"spread_deg": true,
						"shrapnel_count": true,
						"shrapnel_speed_mult": true,
						"shrapnel_lifetime_s": true,
						"shrapnel_cone_deg": true,
						"lifetime_s": true,
						"muzzle_offset": true,
						"bounces": true,
						"bounce_restitution": true,
					}
					for bk in ship_bullet.keys():
						var bks := String(bk)
						if not ship_bullet_allowed.has(bks):
							errors.append(_err("ruleset.ships.%s.weapons.bullet" % ship_key, "unknown key '%s'" % bks))
					if ship_bullet.has("guns"):
						var guns_t := typeof(ship_bullet.get("guns"))
						if guns_t not in [TYPE_INT, TYPE_FLOAT]:
							errors.append(_err("ruleset.ships.%s.weapons.bullet.guns" % ship_key, "must be a number"))
						else:
							var guns_i := int(ship_bullet.get("guns"))
							if guns_i < 1 or guns_i > 8:
								errors.append(_err("ruleset.ships.%s.weapons.bullet.guns" % ship_key, "must be in range 1..8"))
					if ship_bullet.has("multi_fire"):
						if typeof(ship_bullet.get("multi_fire")) != TYPE_BOOL:
							errors.append(_err("ruleset.ships.%s.weapons.bullet.multi_fire" % ship_key, "must be a boolean"))
					if ship_bullet.has("level"):
						var lt := typeof(ship_bullet.get("level"))
						if lt not in [TYPE_INT, TYPE_FLOAT]:
							errors.append(_err("ruleset.ships.%s.weapons.bullet.level" % ship_key, "must be a number"))
						else:
							var li := int(ship_bullet.get("level"))
							if li < 1 or li > 3:
								errors.append(_err("ruleset.ships.%s.weapons.bullet.level" % ship_key, "must be in range 1..3"))
					if ship_bullet.has("multishot") and typeof(ship_bullet.get("multishot")) != TYPE_BOOL:
						errors.append(_err("ruleset.ships.%s.weapons.bullet.multishot" % ship_key, "must be a boolean"))
					if ship_bullet.has("bounce") and typeof(ship_bullet.get("bounce")) != TYPE_BOOL:
						errors.append(_err("ruleset.ships.%s.weapons.bullet.bounce" % ship_key, "must be a boolean"))
					if ship_bullet.has("bounces"):
						var bt := typeof(ship_bullet.get("bounces"))
						if bt not in [TYPE_INT, TYPE_FLOAT]:
							errors.append(_err("ruleset.ships.%s.weapons.bullet.bounces" % ship_key, "must be a number"))
						else:
							var bi := int(ship_bullet.get("bounces"))
							if bi < 0 or bi > 16:
								errors.append(_err("ruleset.ships.%s.weapons.bullet.bounces" % ship_key, "must be in range 0..16"))
					_validate_optional_number_range(ship_bullet, "bounce_restitution", "ruleset.ships.%s.weapons.bullet.bounce_restitution" % ship_key, 0.0, 2.0, errors)
					_validate_optional_number_range(ship_bullet, "speed", "ruleset.ships.%s.weapons.bullet.speed" % ship_key, 0.0, 5000.0, errors)
					if ship_bullet.has("cooldown_ticks"):
						var ct3 := typeof(ship_bullet.get("cooldown_ticks"))
						if ct3 not in [TYPE_INT, TYPE_FLOAT]:
							errors.append(_err("ruleset.ships.%s.weapons.bullet.cooldown_ticks" % ship_key, "must be a number"))
						else:
							var ci3 := int(ship_bullet.get("cooldown_ticks"))
							if ci3 < 0 or ci3 > 120:
								errors.append(_err("ruleset.ships.%s.weapons.bullet.cooldown_ticks" % ship_key, "must be in range 0..120"))
					_validate_optional_number_range(ship_bullet, "spread_deg", "ruleset.ships.%s.weapons.bullet.spread_deg" % ship_key, 0.0, 45.0, errors)
					if ship_bullet.has("shrapnel_count"):
						var st3 := typeof(ship_bullet.get("shrapnel_count"))
						if st3 not in [TYPE_INT, TYPE_FLOAT]:
							errors.append(_err("ruleset.ships.%s.weapons.bullet.shrapnel_count" % ship_key, "must be a number"))
						else:
							var si3 := int(ship_bullet.get("shrapnel_count"))
							if si3 < 0 or si3 > 16:
								errors.append(_err("ruleset.ships.%s.weapons.bullet.shrapnel_count" % ship_key, "must be in range 0..16"))
					_validate_optional_number_range(ship_bullet, "shrapnel_speed_mult", "ruleset.ships.%s.weapons.bullet.shrapnel_speed_mult" % ship_key, 0.0, 2.0, errors)
					_validate_optional_number_range(ship_bullet, "shrapnel_lifetime_s", "ruleset.ships.%s.weapons.bullet.shrapnel_lifetime_s" % ship_key, 0.0, 5.0, errors)
					_validate_optional_number_range(ship_bullet, "shrapnel_cone_deg", "ruleset.ships.%s.weapons.bullet.shrapnel_cone_deg" % ship_key, 0.0, 360.0, errors)
					_validate_optional_number_range(ship_bullet, "lifetime_s", "ruleset.ships.%s.weapons.bullet.lifetime_s" % ship_key, 0.0, 10.0, errors)
					_validate_optional_number_range(ship_bullet, "muzzle_offset", "ruleset.ships.%s.weapons.bullet.muzzle_offset" % ship_key, 0.0, 64.0, errors)

	# Abilities section (schema v2).
	var abilities: Dictionary = {}
	var ability_afterburner: Dictionary = {}
	if schema_version == SCHEMA_RULESET_V2 and not root.has("abilities"):
		errors.append(_err("ruleset", "missing required field 'abilities'"))
	if root.has("abilities"):
		if schema_version != SCHEMA_RULESET_V2:
			errors.append(_err("ruleset", "'abilities' is only supported in schema_version %d" % SCHEMA_RULESET_V2))
		else:
			abilities = _require_dict(root.get("abilities"), "ruleset.abilities", errors)
			var abilities_allowed := {
				"afterburner": true,
				"stealth": true,
				"cloak": true,
				"xradar": true,
				"antiwarp": true,
			}
			for ak in abilities.keys():
				var aks := String(ak)
				if not abilities_allowed.has(aks):
					errors.append(_err("ruleset.abilities", "unknown key '%s'" % aks))
			# Required ability blocks and required drain field.
			for req_ability in ["afterburner", "stealth", "cloak", "xradar", "antiwarp"]:
				if not abilities.has(req_ability):
					errors.append(_err("ruleset.abilities", "missing required field '%s'" % req_ability))
					continue
				var aobj: Dictionary = _require_dict(abilities.get(req_ability), "ruleset.abilities.%s" % req_ability, errors)
				for k2 in aobj.keys():
					var k2s := String(k2)
					var ok: bool = false
					if k2s == "drain_per_sec":
						ok = true
					elif req_ability == "afterburner" and k2s in ["speed_mult_pct", "thrust_mult_pct"]:
						ok = true
					elif req_ability == "antiwarp" and k2s == "radius_px":
						ok = true
					if not ok:
						errors.append(_err("ruleset.abilities.%s" % req_ability, "unknown key '%s'" % k2s))
				if not aobj.has("drain_per_sec"):
					errors.append(_err("ruleset.abilities.%s" % req_ability, "missing required field 'drain_per_sec'"))
				else:
					_validate_optional_number_range(aobj, "drain_per_sec", "ruleset.abilities.%s.drain_per_sec" % req_ability, 0.0, 100000.0, errors)
				if req_ability == "afterburner":
					_validate_optional_number_range(aobj, "speed_mult_pct", "ruleset.abilities.afterburner.speed_mult_pct", 0.0, 500.0, errors)
					_validate_optional_number_range(aobj, "thrust_mult_pct", "ruleset.abilities.afterburner.thrust_mult_pct", 0.0, 500.0, errors)
				if req_ability == "antiwarp":
					_validate_optional_number_range(aobj, "radius_px", "ruleset.abilities.antiwarp.radius_px", 0.0, 100000.0, errors)
				# Keep references used later for warnings.
				if req_ability == "afterburner":
					ability_afterburner = aobj

	# Energy section.
	var energy: Dictionary = {}
	if schema_version == SCHEMA_RULESET_V2 and not root.has("energy"):
		errors.append(_err("ruleset", "missing required field 'energy'"))
	if root.has("energy"):
		energy = _require_dict(root.get("energy"), "ruleset.energy", errors)
		var energy_allowed: Dictionary = {}
		if schema_version == SCHEMA_RULESET_V1:
			energy_allowed = {
				# Legacy
				"max": true,
				"regen_per_s": true,
				"afterburner_drain_per_s": true,
				"afterburner_drain_per_sec": true,
				# New(er) optional
				"recharge_rate_per_sec": true,
				"recharge_delay_ms": true,
				"bullet_energy_cost": true,
				"multifire_energy_cost": true,
				"bomb_energy_cost": true,
			}
		else:
			# Schema v2: sustained ability drains live under ruleset.abilities.
			energy_allowed = {
				"max": true,
				"recharge_rate_per_sec": true,
				"recharge_delay_ms": true,
				"bullet_energy_cost": true,
				"multifire_energy_cost": true,
				"bomb_energy_cost": true,
			}
		for ek in energy.keys():
			var eks := String(ek)
			if not energy_allowed.has(eks):
				errors.append(_err("ruleset.energy", "unknown key '%s'" % eks))

		# In schema v2, energy tuning must be explicit (no silent fallbacks).
		if schema_version == SCHEMA_RULESET_V2:
			for req in [
				"max",
				"recharge_rate_per_sec",
				"recharge_delay_ms",
				"bullet_energy_cost",
				"multifire_energy_cost",
				"bomb_energy_cost",
			]:
				if not energy.has(req):
					errors.append(_err("ruleset.energy", "missing required field '%s'" % req))

		_validate_optional_number_range(energy, "max", "ruleset.energy.max", 0.0, 100000.0, errors)
		_validate_optional_number_range(energy, "regen_per_s", "ruleset.energy.regen_per_s", 0.0, 100000.0, errors)
		_validate_optional_number_range(energy, "afterburner_drain_per_s", "ruleset.energy.afterburner_drain_per_s", 0.0, 100000.0, errors)
		_validate_optional_number_range(energy, "afterburner_drain_per_sec", "ruleset.energy.afterburner_drain_per_sec", 0.0, 100000.0, errors)
		_validate_optional_number_range(energy, "recharge_rate_per_sec", "ruleset.energy.recharge_rate_per_sec", 0.0, 100000.0, errors)
		_validate_optional_number_range(energy, "recharge_delay_ms", "ruleset.energy.recharge_delay_ms", 0.0, 10000.0, errors)
		_validate_optional_number_range(energy, "bullet_energy_cost", "ruleset.energy.bullet_energy_cost", 0.0, 10000.0, errors)
		_validate_optional_number_range(energy, "multifire_energy_cost", "ruleset.energy.multifire_energy_cost", 0.0, 10000.0, errors)
		_validate_optional_number_range(energy, "bomb_energy_cost", "ruleset.energy.bomb_energy_cost", 0.0, 10000.0, errors)

	# Warnings for omitted optional knobs (no silent defaults).
	var missing_physics: Array[String] = []
	for k in [
		"tangent_damping",
		"ship_turn_rate",
		"ship_thrust_accel",
		"ship_reverse_accel",
		"ship_max_speed",
		"ship_base_drag",
		"ship_overspeed_drag",
		"ship_bounce_min_normal_speed",
	]:
		if not physics.has(k):
			missing_physics.append(k)
	if missing_physics.size() > 0:
		warnings.append(_err("ruleset.physics", "missing optional fields (engine defaults will be used): %s" % ", ".join(missing_physics)))
	if root.has("weapons"):
		var missing_weapons: Array[String] = []
		for k in ["ball_friction", "ball_max_speed", "ball_kick_speed", "ball_knock_impulse", "ball_stick_offset", "ball_steal_padding", "bullet"]:
			if not weapons.has(k):
				missing_weapons.append(k)
		if missing_weapons.size() > 0:
			warnings.append(_err("ruleset.weapons", "missing optional fields (engine defaults will be used): %s" % ", ".join(missing_weapons)))
		if weapons.has("bullet"):
			var missing_bullet: Array[String] = []
			for k in ["speed", "lifetime_s", "muzzle_offset"]:
				if not bullet.has(k):
					missing_bullet.append(k)
			if missing_bullet.size() > 0:
				warnings.append(_err("ruleset.weapons.bullet", "missing optional fields (engine defaults will be used): %s" % ", ".join(missing_bullet)))
	# In schema v1, missing tuning is permitted but must produce warnings (no silent defaults).
	if schema_version == SCHEMA_RULESET_V1:
		if not root.has("energy"):
			warnings.append(_err("ruleset.energy", "missing optional section (engine defaults will be used)"))
		else:
			var missing_energy: Array[String] = []
			for k in [
				"max",
				"regen_per_s",
				"afterburner_drain_per_s",
				"recharge_rate_per_sec",
				"recharge_delay_ms",
				"bullet_energy_cost",
				"multifire_energy_cost",
				"bomb_energy_cost",
			]:
				if not energy.has(k):
					missing_energy.append(k)
			if missing_energy.size() > 0:
				warnings.append(_err("ruleset.energy", "missing optional fields (engine defaults will be used): %s" % ", ".join(missing_energy)))

	# In schema v2, warn if recommended afterburner movement modifiers are missing.
	if schema_version == SCHEMA_RULESET_V2 and not ability_afterburner.is_empty():
		var missing_ab: Array[String] = []
		for k in ["speed_mult_pct", "thrust_mult_pct"]:
			if not ability_afterburner.has(k):
				missing_ab.append(k)
		if missing_ab.size() > 0:
			warnings.append(_err("ruleset.abilities.afterburner", "missing optional fields (engine defaults will be used): %s" % ", ".join(missing_ab)))

	# Canonical (no auto-fill).
	var canonical := {
		"format": FORMAT_RULESET,
		"schema_version": schema_version,
		"physics": {},
	}
	# Required
	(canonical["physics"] as Dictionary)["wall_restitution"] = wall_rest
	# Optional passthrough
	var physics_keys: Array = physics.keys()
	physics_keys.sort()
	for k in physics_keys:
		var ks := String(k)
		if ks != "wall_restitution" and physics_allowed.has(ks):
			(canonical["physics"] as Dictionary)[ks] = physics.get(ks)
	if root.has("weapons"):
		canonical["weapons"] = {}
		var weapon_keys: Array = weapons.keys()
		weapon_keys.sort()
		for k in weapon_keys:
			var ks := String(k)
			if ks == "bullet" and typeof(weapons.get("bullet")) == TYPE_DICTIONARY:
				# Canonicalize nested bullet dict.
				var b: Dictionary = weapons.get("bullet")
				var out_b := {}
				var bkeys: Array = b.keys()
				bkeys.sort()
				for bk in bkeys:
					var bks := String(bk)
					if bks == "levels" and typeof(b.get("levels")) == TYPE_DICTIONARY:
						var levels_in: Dictionary = b.get("levels")
						var out_levels := {}
						var level_ids: Array[int] = []
						for lk in levels_in.keys():
							var lks := String(lk)
							if lks.is_valid_int():
								level_ids.append(int(lks))
						level_ids.sort()
						for lid in level_ids:
							var lid_key := str(lid)
							var lvl_dict: Dictionary = levels_in.get(lid_key, {})
							var out_lvl := {}
							if typeof(lvl_dict) == TYPE_DICTIONARY:
								var lvl_keys: Array = lvl_dict.keys()
								lvl_keys.sort()
								for k2 in lvl_keys:
									out_lvl[String(k2)] = lvl_dict.get(k2)
							out_levels[lid_key] = out_lvl
						out_b[bks] = out_levels
					else:
						out_b[bks] = b.get(bk)
				(canonical["weapons"] as Dictionary)[ks] = out_b
			else:
				(canonical["weapons"] as Dictionary)[ks] = weapons.get(ks)
	if root.has("abilities") and schema_version == SCHEMA_RULESET_V2:
		canonical["abilities"] = {}
		var ability_keys: Array = abilities.keys()
		ability_keys.sort()
		for k in ability_keys:
			var ks := String(k)
			(canonical["abilities"] as Dictionary)[ks] = abilities.get(ks)
	if root.has("combat") and schema_version == SCHEMA_RULESET_V2:
		canonical["combat"] = {}
		var combat_keys: Array = combat.keys()
		combat_keys.sort()
		for k in combat_keys:
			var ks := String(k)
			(canonical["combat"] as Dictionary)[ks] = combat.get(ks)
	if root.has("team") and schema_version == SCHEMA_RULESET_V2:
		canonical["team"] = {}
		var team_keys: Array = team.keys()
		team_keys.sort()
		for k in team_keys:
			var ks := String(k)
			(canonical["team"] as Dictionary)[ks] = team.get(ks)
	if root.has("zones") and schema_version == SCHEMA_RULESET_V2:
		canonical["zones"] = {}
		var zone_keys: Array = zones.keys()
		zone_keys.sort()
		for k in zone_keys:
			var ks := String(k)
			(canonical["zones"] as Dictionary)[ks] = zones.get(ks)
	if root.has("ui") and schema_version == SCHEMA_RULESET_V2:
		canonical["ui"] = {}
		var ui_keys: Array = ui.keys()
		ui_keys.sort()
		for k in ui_keys:
			var ks := String(k)
			(canonical["ui"] as Dictionary)[ks] = ui.get(ks)
	if root.has("energy"):
		canonical["energy"] = {}
		if schema_version == SCHEMA_RULESET_V1 and energy.has("afterburner_drain_per_sec") and not energy.has("afterburner_drain_per_s"):
			# Legacy alias mapping (schema v1 only).
			(canonical["energy"] as Dictionary)["afterburner_drain_per_s"] = energy.get("afterburner_drain_per_sec")
		var energy_keys: Array = energy.keys()
		energy_keys.sort()
		for k in energy_keys:
			var ks := String(k)
			if schema_version == SCHEMA_RULESET_V1 and ks == "afterburner_drain_per_sec":
				continue
			(canonical["energy"] as Dictionary)[ks] = energy.get(ks)
	if root.has("ships"):
		canonical["ships"] = {}
		# Sort ship ids numerically.
		var ship_ids: Array[int] = []
		for sk in ships.keys():
			var ship_key := String(sk)
			if ship_key.is_valid_int():
				ship_ids.append(int(ship_key))
		ship_ids.sort()
		for ship_id in ship_ids:
			var ship_key := str(ship_id)
			var ship_obj: Dictionary = ships.get(ship_key, {})
			var out_ship := {}
			if typeof(ship_obj) == TYPE_DICTIONARY and ship_obj.has("weapons"):
				var ship_weapons: Dictionary = ship_obj.get("weapons")
				var out_weapons := {}
				if typeof(ship_weapons) == TYPE_DICTIONARY and ship_weapons.has("bullet") and typeof(ship_weapons.get("bullet")) == TYPE_DICTIONARY:
					var sb: Dictionary = ship_weapons.get("bullet")
					var out_sb := {}
					var sb_keys: Array = sb.keys()
					sb_keys.sort()
					for bk in sb_keys:
						out_sb[String(bk)] = sb.get(bk)
					out_weapons["bullet"] = out_sb
				out_ship["weapons"] = out_weapons
			(canonical["ships"] as Dictionary)[ship_key] = out_ship

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"ruleset": canonical,
	}


static func validate_ruleset_dict(d: Dictionary) -> Dictionary:
	# Minimal wrapper for headless contract tests.
	# Returns: { ok: bool, error?: String }
	var res := validate_ruleset(d)
	if bool(res.get("ok", false)):
		return {"ok": true}
	var err_text := "ruleset validation failed"
	for e in (res.get("errors", []) as Array):
		err_text += "\n - " + String(e)
	return {"ok": false, "error": err_text}


static func validate_server_config_dict(cfg: Dictionary) -> Dictionary:
	# Minimal wrapper for headless contract tests.
	# Returns: { ok: bool, error?: String }
	var res := validate_server_config(cfg)
	if bool(res.get("ok", false)):
		return {"ok": true}
	var err_text := "server_config validation failed"
	for e in (res.get("errors", []) as Array):
		err_text += "\n - " + String(e)
	return {"ok": false, "error": err_text}


static func _tile_less(a, b) -> bool:
	if int(a[0]) != int(b[0]):
		return int(a[0]) < int(b[0])
	if int(a[1]) != int(b[1]):
		return int(a[1]) < int(b[1])
	if int(a[2]) != int(b[2]):
		return int(a[2]) < int(b[2])
	return int(a[3]) < int(b[3])


static func _entity_less(a, b) -> bool:
	var at := String((a as Dictionary).get("type", ""))
	var bt := String((b as Dictionary).get("type", ""))
	if at != bt:
		return at < bt
	var ax := int((a as Dictionary).get("x", 0))
	var bx := int((b as Dictionary).get("x", 0))
	if ax != bx:
		return ax < bx
	var ay := int((a as Dictionary).get("y", 0))
	var by := int((b as Dictionary).get("y", 0))
	return ay < by
