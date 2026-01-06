## Persistent user settings (client-only).
##
## - Stored at user://settings.json
## - Applies only to local client behavior (audio volumes, input remaps)
## - Must never affect authoritative/deterministic simulation.

class_name UserSettings
extends RefCounted

const _SELF_SCRIPT_PATH: String = "res://client/settings/user_settings.gd"

const SETTINGS_PATH: String = "user://settings.json"

var master_db: float = 0.0
var sfx_db: float = 0.0
var music_db: float = 0.0
var ui_db: float = 0.0

# action (String) -> Array[Dictionary] (serialized InputEvent)
var keybinds: Dictionary = {}


static func load_or_default() -> UserSettings:
	var s := _new_self()
	if s == null:
		# Defensive: if script loading fails, return a minimal default instance.
		return RefCounted.new() as UserSettings
	if not FileAccess.file_exists(SETTINGS_PATH):
		return s
	var f: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return s
	var text: String = f.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return s
	return from_dict(parsed)


func save() -> void:
	var f: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[SETTINGS] failed to open %s for writing" % SETTINGS_PATH)
		return
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.store_string("\n")


func to_dict() -> Dictionary:
	return {
		"master_db": float(master_db),
		"sfx_db": float(sfx_db),
		"music_db": float(music_db),
		"ui_db": float(ui_db),
		"keybinds": keybinds.duplicate(true),
	}


static func from_dict(d: Dictionary) -> UserSettings:
	var s := _new_self()
	if s == null:
		return RefCounted.new() as UserSettings
	if typeof(d) != TYPE_DICTIONARY:
		return s

	s.master_db = _as_finite_float(d.get("master_db", s.master_db), s.master_db)
	s.sfx_db = _as_finite_float(d.get("sfx_db", s.sfx_db), s.sfx_db)
	s.music_db = _as_finite_float(d.get("music_db", s.music_db), s.music_db)
	s.ui_db = _as_finite_float(d.get("ui_db", s.ui_db), s.ui_db)

	var kb_any: Variant = d.get("keybinds", {})
	if typeof(kb_any) == TYPE_DICTIONARY:
		var kb_in: Dictionary = kb_any
		var kb_out: Dictionary = {}
		for action_any in kb_in.keys():
			var action: String = str(action_any)
			var events_any: Variant = kb_in.get(action_any)
			if typeof(events_any) != TYPE_ARRAY:
				continue
			var events_in: Array = events_any
			var events_out: Array = []
			for ev_any in events_in:
				if typeof(ev_any) == TYPE_DICTIONARY:
					events_out.append(ev_any)
			kb_out[action] = events_out
		s.keybinds = kb_out

	return s


static func _new_self() -> UserSettings:
	var script = load(_SELF_SCRIPT_PATH)
	if script == null:
		return null
	return script.new()


static func _as_finite_float(v: Variant, fallback: float) -> float:
	var t := typeof(v)
	var out: float = fallback
	if t == TYPE_FLOAT or t == TYPE_INT:
		out = float(v)
	else:
		return fallback
	if is_nan(out) or is_inf(out):
		return fallback
	return out
