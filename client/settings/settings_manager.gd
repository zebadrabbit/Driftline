## Settings manager (client-only).
##
## Intended to be used as an AutoLoad singleton.
##
## Client-only: do not modify shared/ sim state here.

class_name SettingsManager
extends Node

signal settings_loaded
signal setting_changed(path: String, value)

const DriftActions = preload("res://client/input/actions.gd")

const SETTINGS_PATH: String = "user://settings.json"
const SETTINGS_TMP_PATH: String = "user://settings.json.tmp"

const SETTINGS_FORMAT: String = "driftline.client_settings"
const SETTINGS_SCHEMA_VERSION: int = 1

const DEFAULTS: Dictionary = {
	"format": SETTINGS_FORMAT,
	"schema_version": SETTINGS_SCHEMA_VERSION,
	"audio": {
		"master_db": 0.0,
		"sfx_db": 0.0,
		"music_db": 0.0,
		"ui_db": 0.0,
	},
	"ui": {
		# UI preferences live here.
		"show_minimap": true,
		"help_ticker_enabled": true,
	},
	"controls": {
		# action (String) -> Array[Dictionary] (serialized InputEvent)
		"bindings": {},
	},
}

var _settings: Dictionary = {}
var _dirty: bool = false
var _save_queued: bool = false


func _ready() -> void:
	load_settings()
	ensure_audio_buses()
	apply_audio()
	reapply_bindings_from_settings()
	if OS.is_debug_build():
		validate_bindings_runtime()


func load_settings() -> void:
	var merged: Dictionary = DEFAULTS.duplicate(true)

	if not FileAccess.file_exists(SETTINGS_PATH):
		_settings = merged
		_dirty = false
		emit_signal("settings_loaded")
		return

	var f: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		push_warning("[SettingsManager] Failed to open %s for reading" % SETTINGS_PATH)
		_settings = merged
		_dirty = false
		emit_signal("settings_loaded")
		return

	var text: String = f.get_as_text()
	f.close()

	var parsed_any: Variant = JSON.parse_string(text)
	if typeof(parsed_any) != TYPE_DICTIONARY:
		push_warning("[SettingsManager] Corrupt settings.json (expected JSON object); using defaults")
		_settings = merged
		_dirty = false
		emit_signal("settings_loaded")
		return

	var loaded_raw: Dictionary = Dictionary(parsed_any)
	if str(loaded_raw.get("format", "")) != SETTINGS_FORMAT:
		push_error(
			"[SettingsManager] Refusing to load %s (missing/unknown format; expected '%s')" % [
				SETTINGS_PATH,
				SETTINGS_FORMAT,
			]
		)
		_settings = merged
		_dirty = false
		emit_signal("settings_loaded")
		return
	var schema_any: Variant = loaded_raw.get("schema_version", null)
	var schema_type := typeof(schema_any)
	if schema_type != TYPE_INT and schema_type != TYPE_FLOAT:
		push_error(
			"[SettingsManager] Refusing to load %s (missing/invalid schema_version; expected integer)" % SETTINGS_PATH
		)
		_settings = merged
		_dirty = false
		emit_signal("settings_loaded")
		return
	# JSON.parse_string returns numbers as float; accept only whole numbers.
	var schema_float: float = float(schema_any)
	var schema_version: int = int(schema_float)
	if absf(schema_float - float(schema_version)) > 0.00001:
		push_error(
			"[SettingsManager] Refusing to load %s (schema_version must be an integer)" % SETTINGS_PATH
		)
		_settings = merged
		_dirty = false
		emit_signal("settings_loaded")
		return
	if schema_version != SETTINGS_SCHEMA_VERSION:
		push_error(
			"[SettingsManager] Refusing to load %s (unsupported schema_version=%d; expected %d)" % [
				SETTINGS_PATH,
				schema_version,
				SETTINGS_SCHEMA_VERSION,
			]
		)
		_settings = merged
		_dirty = false
		emit_signal("settings_loaded")
		return

	var loaded: Dictionary = _normalize_loaded_settings(loaded_raw)
	_settings = _deep_merge_preserve_unknown(merged, loaded)
	_dirty = false
	emit_signal("settings_loaded")


func save_settings() -> void:
	# Deterministic + stable key ordering.
	var canonical: Variant = _canonicalize(_settings)
	var json_str: String = JSON.stringify(canonical, "\t") + "\n"

	var f: FileAccess = FileAccess.open(SETTINGS_TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[SettingsManager] Failed to open %s for writing" % SETTINGS_TMP_PATH)
		return
	f.store_string(json_str)
	f.flush()
	f.close()

	# Best-effort atomic replace: write temp then rename over final.
	var abs_tmp: String = ProjectSettings.globalize_path(SETTINGS_TMP_PATH)
	var abs_final: String = ProjectSettings.globalize_path(SETTINGS_PATH)
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(abs_final)
	var err: Error = DirAccess.rename_absolute(abs_tmp, abs_final)
	if err != OK:
		# Fallback: write directly (still deterministic, but not atomic).
		var f2: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if f2 == null:
			push_error("[SettingsManager] Failed to open %s for writing" % SETTINGS_PATH)
			return
		f2.store_string(json_str)
		f2.flush()
		f2.close()

	_dirty = false


func reset_to_defaults() -> void:
	_settings = DEFAULTS.duplicate(true)
	_dirty = true
	save_settings()
	emit_signal("settings_loaded")
	apply_audio()
	DriftActions.build_default_inputmap()
	reapply_bindings_from_settings()


func get_value(path: String, default: Variant = null) -> Variant:
	var parts: PackedStringArray = path.split(".", false)
	if parts.is_empty():
		return default
	var cur: Variant = _settings
	for p in parts:
		if typeof(cur) != TYPE_DICTIONARY:
			return default
		var d: Dictionary = Dictionary(cur)
		if not d.has(p):
			return default
		cur = d[p]
	return cur


func set_value(path: String, value: Variant) -> void:
	var parts: PackedStringArray = path.split(".", false)
	if parts.is_empty():
		return
	if typeof(_settings) != TYPE_DICTIONARY:
		_settings = {}

	var d: Dictionary = _settings
	for i in range(parts.size() - 1):
		var k: String = String(parts[i])
		if (not d.has(k)) or typeof(d[k]) != TYPE_DICTIONARY:
			d[k] = {}
		d = d[k]

	var leaf: String = String(parts[parts.size() - 1])
	if d.has(leaf) and d[leaf] == value:
		return
	d[leaf] = value
	_dirty = true
	emit_signal("setting_changed", path, value)
	_queue_save()


func ensure_audio_buses() -> void:
	# Ensure expected bus names exist. This is client-only QoL and must not crash.
	# If a bus already exists, do nothing.
	var required: Array[String] = ["Master", "SFX", "Music", "UI"]
	var master_idx: int = AudioServer.get_bus_index("Master")
	for name in required:
		if AudioServer.get_bus_index(name) >= 0:
			continue
		# Add empty bus at end.
		var before_count: int = AudioServer.get_bus_count()
		AudioServer.add_bus(before_count)
		var new_idx: int = AudioServer.get_bus_count() - 1
		if new_idx < 0:
			continue
		AudioServer.set_bus_name(new_idx, name)
		# Default routing is typically to Master; set explicitly when available.
		if master_idx >= 0:
			AudioServer.set_bus_send(new_idx, "Master")
			# Best-effort duplicate Master effects chain (keeps project setups consistent).
			var eff_count: int = AudioServer.get_bus_effect_count(master_idx)
			for e in range(eff_count):
				var eff_any: AudioEffect = AudioServer.get_bus_effect(master_idx, e)
				if eff_any == null:
					continue
				var dup: AudioEffect = eff_any.duplicate(true)
				AudioServer.add_bus_effect(new_idx, dup, e)
				var enabled: bool = AudioServer.is_bus_effect_enabled(master_idx, e)
				AudioServer.set_bus_effect_enabled(new_idx, e, enabled)


func _apply_bus_db(bus_name: String, db: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	if is_nan(db) or is_inf(db):
		return
	AudioServer.set_bus_volume_db(idx, db)


func reapply_bindings_from_settings() -> void:
	# Rebuild ONLY the actions we explicitly allow rebinding.
	# For each action:
	# - if user settings has an entry (even empty) -> apply exactly that (empty means unbound)
	# - else -> apply defaults for that action
	var bindings_any: Variant = get_value("controls.bindings", {})
	var bindings: Dictionary = {}
	if typeof(bindings_any) == TYPE_DICTIONARY:
		bindings = Dictionary(bindings_any)

	for action in DriftActions.REBINDABLE_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(StringName(action))
		InputMap.action_erase_events(StringName(action))

		var has_override: bool = bindings.has(action)
		if has_override:
			var events_any: Variant = bindings.get(action, [])
			if typeof(events_any) == TYPE_ARRAY:
				var events: Array = events_any
				for ev_d_any in events:
					if typeof(ev_d_any) != TYPE_DICTIONARY:
						continue
					var ev: InputEvent = deserialize_input_event(Dictionary(ev_d_any))
					if ev == null:
						continue
					InputMap.action_add_event(StringName(action), ev)
			# If we have an override entry (even empty), do not fall back to defaults.
			continue

		# Defaults fallback.
		var default_any: Variant = DriftActions.DEFAULT_BINDINGS.get(action, [])
		if typeof(default_any) != TYPE_ARRAY:
			continue
		var default_events: Array = default_any
		for dev_any in default_events:
			var dev: InputEvent = dev_any
			if dev == null:
				continue
			InputMap.action_add_event(StringName(action), dev.duplicate())

	if OS.is_debug_build():
		validate_bindings_runtime()


func validate_bindings_runtime() -> void:
	# Lightweight sanity checks for rebindable actions.
	# - Warn if an action ends up with 0 bindings unless explicitly cleared in settings.
	# - Warn if duplicates exist within an action.
	# - Warn if settings JSON bindings fail to deserialize.
	# Never crash.
	var bindings_any: Variant = get_value("controls.bindings", {})
	var bindings: Dictionary = {}
	if typeof(bindings_any) == TYPE_DICTIONARY:
		bindings = Dictionary(bindings_any)
	else:
		push_warning("[SettingsManager] controls.bindings is not a Dictionary")

	for action_any in DriftActions.REBINDABLE_ACTIONS:
		var action: String = String(action_any)
		var has_override: bool = bindings.has(action)
		var override_empty_intentional: bool = false

		# Validate serialized bindings (if present).
		if has_override:
			var events_any: Variant = bindings.get(action, [])
			if typeof(events_any) != TYPE_ARRAY:
				push_warning("[SettingsManager] controls.bindings[%s] is not an Array" % action)
			else:
				var arr: Array = events_any
				override_empty_intentional = (arr.size() == 0)
				var seen: Dictionary = {}
				for i in range(arr.size()):
					var d_any: Variant = arr[i]
					if typeof(d_any) != TYPE_DICTIONARY:
						push_warning("[SettingsManager] controls.bindings[%s][%d] is not a Dictionary" % [action, i])
						continue
					var ev: InputEvent = deserialize_input_event(Dictionary(d_any))
					if ev == null:
						push_warning("[SettingsManager] controls.bindings[%s][%d] failed to deserialize: %s" % [action, i, str(d_any)])
						continue
					var sig: String = _event_signature_for_validation(ev)
					if seen.has(sig):
						push_warning("[SettingsManager] Duplicate binding for action '%s': %s" % [action, sig])
					else:
						seen[sig] = true
		else:
			# If no override, ensure defaults exist (best-effort check).
			var def_any: Variant = DriftActions.DEFAULT_BINDINGS.get(action, [])
			if typeof(def_any) != TYPE_ARRAY or Array(def_any).size() == 0:
				push_warning("[SettingsManager] No default bindings declared for action '%s'" % action)

		# Ensure InputMap contains at least 1 binding unless intentionally cleared.
		if not InputMap.has_action(action):
			push_warning("[SettingsManager] InputMap missing rebindable action '%s'" % action)
			continue
		var im_events: Array = InputMap.action_get_events(action)
		if im_events.size() == 0 and not override_empty_intentional:
			push_warning("[SettingsManager] Action '%s' has no bindings (not intentionally cleared)" % action)
		else:
			# Detect duplicates in InputMap too.
			var seen_im: Dictionary = {}
			for ev_any in im_events:
				var ev2: InputEvent = ev_any
				if ev2 == null:
					continue
				var sig2: String = _event_signature_for_validation(ev2)
				if seen_im.has(sig2):
					push_warning("[SettingsManager] Duplicate InputMap binding for action '%s': %s" % [action, sig2])
				else:
					seen_im[sig2] = true


static func _event_signature_for_validation(ev: InputEvent) -> String:
	if ev == null:
		return "(null)"
	if ev is InputEventKey:
		var k: InputEventKey = ev
		var code: int = int(k.physical_keycode) if int(k.physical_keycode) != 0 else int(k.keycode)
		return "key:%d:%d%d%d%d" % [
			code,
			1 if bool(k.shift_pressed) else 0,
			1 if bool(k.ctrl_pressed) else 0,
			1 if bool(k.alt_pressed) else 0,
			1 if bool(k.meta_pressed) else 0,
		]
	if ev is InputEventMouseButton:
		var m: InputEventMouseButton = ev
		return "mouse:%d" % int(m.button_index)
	if ev is InputEventJoypadButton:
		var jb: InputEventJoypadButton = ev
		return "joybtn:%d" % int(jb.button_index)
	if ev is InputEventJoypadMotion:
		var jm: InputEventJoypadMotion = ev
		var sign: int = 0
		if float(jm.axis_value) > 0.0:
			sign = 1
		elif float(jm.axis_value) < 0.0:
			sign = -1
		return "joyaxis:%d:%d" % [int(jm.axis), sign]
	return ev.get_class()


func apply_keybinds() -> void:
	# Back-compat alias (older callers).
	reapply_bindings_from_settings()


static func serialize_input_event(ev: InputEvent) -> Dictionary:
	if ev == null:
		return {}

	if ev is InputEventKey:
		var k: InputEventKey = ev
		return {
			"type": "key",
			"device": int(k.device),
			"keycode": int(k.keycode),
			"physical_keycode": int(k.physical_keycode),
			"shift": bool(k.shift_pressed),
			"ctrl": bool(k.ctrl_pressed),
			"alt": bool(k.alt_pressed),
			"meta": bool(k.meta_pressed),
		}

	if ev is InputEventMouseButton:
		var m: InputEventMouseButton = ev
		return {
			"type": "mouse_button",
			"device": int(m.device),
			"button_index": int(m.button_index),
			"shift": bool(m.shift_pressed),
			"ctrl": bool(m.ctrl_pressed),
			"alt": bool(m.alt_pressed),
			"meta": bool(m.meta_pressed),
		}

	if ev is InputEventJoypadButton:
		var j: InputEventJoypadButton = ev
		return {
			"type": "joypad_button",
			"device": int(j.device),
			"button_index": int(j.button_index),
		}

	if ev is InputEventJoypadMotion:
		var jm: InputEventJoypadMotion = ev
		# Persist sign only (axis_value is noisy). Convention: -1 or +1.
		var sign: int = 0
		if float(jm.axis_value) > 0.0:
			sign = 1
		elif float(jm.axis_value) < 0.0:
			sign = -1
		return {
			"type": "joypad_motion",
			"device": int(jm.device),
			"axis": int(jm.axis),
			"sign": int(sign),
		}

	return {}


static func deserialize_input_event(d: Dictionary) -> InputEvent:
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var kind: String = str(d.get("type", ""))

	if kind == "key":
		var k := InputEventKey.new()
		k.device = int(d.get("device", -1))
		k.shift_pressed = bool(d.get("shift", false))
		k.ctrl_pressed = bool(d.get("ctrl", false))
		k.alt_pressed = bool(d.get("alt", false))
		k.meta_pressed = bool(d.get("meta", false))
		k.keycode = int(d.get("keycode", 0))
		k.physical_keycode = int(d.get("physical_keycode", 0))
		k.pressed = false
		return k

	if kind == "mouse_button":
		var m := InputEventMouseButton.new()
		m.device = int(d.get("device", -1))
		m.shift_pressed = bool(d.get("shift", false))
		m.ctrl_pressed = bool(d.get("ctrl", false))
		m.alt_pressed = bool(d.get("alt", false))
		m.meta_pressed = bool(d.get("meta", false))
		m.button_index = int(d.get("button_index", 0))
		m.pressed = false
		return m

	if kind == "joypad_button":
		var j := InputEventJoypadButton.new()
		j.device = int(d.get("device", 0))
		j.button_index = int(d.get("button_index", 0))
		j.pressed = false
		return j

	if kind == "joypad_motion":
		var jm := InputEventJoypadMotion.new()
		jm.device = int(d.get("device", 0))
		jm.axis = int(d.get("axis", 0))
		var sign: int = int(d.get("sign", 0))
		jm.axis_value = 1.0 if sign > 0 else (-1.0 if sign < 0 else 0.0)
		return jm

	return null


func apply_audio() -> void:
	ensure_audio_buses()
	_apply_bus_db("Master", _as_finite_float(get_value("audio.master_db", 0.0), 0.0))
	_apply_bus_db("SFX", _as_finite_float(get_value("audio.sfx_db", 0.0), 0.0))
	_apply_bus_db("Music", _as_finite_float(get_value("audio.music_db", 0.0), 0.0))
	_apply_bus_db("UI", _as_finite_float(get_value("audio.ui_db", 0.0), 0.0))


func _queue_save() -> void:
	if _save_queued:
		return
	_save_queued = true
	call_deferred("_flush_save")


func _flush_save() -> void:
	_save_queued = false
	if _dirty:
		save_settings()


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


static func _deep_merge_preserve_unknown(defaults: Dictionary, loaded: Dictionary) -> Dictionary:
	# Loaded values override defaults; missing keys filled from defaults.
	# Unknown keys in loaded are preserved.
	var out: Dictionary = defaults.duplicate(true)
	for k_any in loaded.keys():
		var k: Variant = k_any
		var lv: Variant = loaded[k_any]
		if out.has(k) and typeof(out[k]) == TYPE_DICTIONARY and typeof(lv) == TYPE_DICTIONARY:
			out[k] = _deep_merge_preserve_unknown(Dictionary(out[k]), Dictionary(lv))
		else:
			out[k] = lv
	return out


static func _canonicalize(v: Variant) -> Variant:
	# Recursively sort dictionary keys for deterministic JSON output.
	var t := typeof(v)
	if t == TYPE_DICTIONARY:
		var d: Dictionary = Dictionary(v)
		var keys: Array = d.keys()
		keys.sort()
		var out: Dictionary = {}
		for k_any in keys:
			var k: String = str(k_any)
			out[k] = _canonicalize(d[k_any])
		return out
	if t == TYPE_ARRAY:
		var arr: Array = Array(v)
		var out_arr: Array = []
		out_arr.resize(arr.size())
		for i in range(arr.size()):
			out_arr[i] = _canonicalize(arr[i])
		return out_arr
	return v


static func _normalize_loaded_settings(loaded: Dictionary) -> Dictionary:
	# Back-compat: older versions stored master_db/sfx_db/music_db/ui_db/keybinds at the root.
	# If the file already uses nested sections, leave it unchanged.
	if loaded.has("audio") or loaded.has("ui") or loaded.has("controls"):
		# If controls.keybinds exists, rename to controls.bindings.
		var out0: Dictionary = loaded.duplicate(true)
		if out0.has("controls") and typeof(out0.get("controls")) == TYPE_DICTIONARY:
			var c0: Dictionary = Dictionary(out0.get("controls"))
			if c0.has("keybinds") and (not c0.has("bindings")):
				c0["bindings"] = c0.get("keybinds")
				c0.erase("keybinds")
				out0["controls"] = c0
		return out0

	var out: Dictionary = loaded.duplicate(true)
	var audio: Dictionary = {}
	for k in ["master_db", "sfx_db", "music_db", "ui_db"]:
		if out.has(k):
			audio[k] = out[k]
			out.erase(k)
	if audio.size() > 0:
		out["audio"] = audio

	if out.has("keybinds"):
		out["controls"] = {"bindings": out["keybinds"]}
		out.erase("keybinds")

	return out


static func event_to_dict(ev: InputEvent) -> Dictionary:
	# Back-compat alias.
	return serialize_input_event(ev)


static func dict_to_event(d: Dictionary) -> InputEvent:
	# Back-compat alias.
	return deserialize_input_event(d)
