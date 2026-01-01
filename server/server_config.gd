## Server config loader (ConfigFile)
##
## Loads user://server.cfg first, then falls back to res://server.cfg.

class_name DriftServerConfig

const DEFAULT_SECTION: String = "Server"

var default_map: String = ""
var map_mode: String = "single" # single|rotation|random
var rotation: PackedStringArray = PackedStringArray()


static func load_config() -> DriftServerConfig:
	var cfg := DriftServerConfig.new()

	var config := ConfigFile.new()
	var loaded_path: String = ""

	var candidates := PackedStringArray([
		"user://server.cfg",
		"user://server.ini",
		"res://server.cfg",
		"res://server.ini",
	])

	for p in candidates:
		if not FileAccess.file_exists(p):
			continue
		var err := config.load(p)
		if err == OK:
			loaded_path = p
			break
		push_warning("[CFG] Failed to load " + p + " (err=%d)" % int(err))

	if loaded_path == "":
		push_warning("[CFG] No server.cfg/server.ini found in user:// or res://. Using defaults.")

	if loaded_path != "":
		print("[CFG] Loaded ", loaded_path)

	cfg.default_map = String(config.get_value(DEFAULT_SECTION, "DefaultMap", ""))
	cfg.map_mode = String(config.get_value(DEFAULT_SECTION, "MapMode", "single")).to_lower()
	var rotation_raw: String = String(config.get_value(DEFAULT_SECTION, "MapRotation", ""))
	cfg.rotation = _parse_rotation(rotation_raw)

	if cfg.map_mode == "":
		cfg.map_mode = "single"

	return cfg


static func _parse_rotation(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	var trimmed := s.strip_edges()
	if trimmed == "":
		return out
	var parts := trimmed.split(",", false)
	for p in parts:
		var item := String(p).strip_edges()
		if item != "":
			out.append(item)
	return out


func choose_map_path() -> String:
	match map_mode:
		"single":
			return default_map
		"rotation":
			if rotation.size() > 0:
				return rotation[0]
			return default_map
		"random":
			var choices := PackedStringArray()
			if rotation.size() > 0:
				choices = rotation
			elif default_map != "":
				choices.append(default_map)
			if choices.size() == 0:
				return ""
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			return choices[rng.randi_range(0, choices.size() - 1)]
		_:
			push_warning("[CFG] Unknown MapMode '%s' (expected single|rotation|random). Using 'single'." % map_mode)
			return default_map


static func normalize_map_path(path: String) -> String:
	var p := String(path).strip_edges()
	if p == "":
		return ""
	if p.begins_with("res://") or p.begins_with("user://"):
		return p
	# Treat as res:// relative.
	return "res://" + p
