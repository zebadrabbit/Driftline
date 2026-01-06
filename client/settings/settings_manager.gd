## Settings manager (client-only).
##
## Intended to be used as an AutoLoad singleton.
##
## Client-only: do not modify shared/ sim state here.

class_name SettingsManager
extends Node

const UserSettings = preload("res://client/settings/user_settings.gd")

var current: UserSettings = null


func _ready() -> void:
	load_settings()
	ensure_audio_buses()
	apply_audio()
	apply_keybinds()


func load_settings() -> void:
	current = UserSettings.load_or_default()


func save_settings() -> void:
	if current == null:
		current = UserSettings.new()
	current.save()


func reset_to_defaults() -> void:
	current = UserSettings.new()
	apply_audio()
	apply_keybinds()
	save_settings()


func apply_audio() -> void:
	if current == null:
		return
	ensure_audio_buses()
	_apply_bus_db("Master", float(current.master_db))
	_apply_bus_db("SFX", float(current.sfx_db))
	_apply_bus_db("Music", float(current.music_db))
	_apply_bus_db("UI", float(current.ui_db))


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


func apply_keybinds() -> void:
	if current == null:
		return
	if typeof(current.keybinds) != TYPE_DICTIONARY:
		return

	var actions: Array = current.keybinds.keys()
	actions.sort()
	for a_any in actions:
		var action: String = str(a_any)
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(StringName(action))
		var events_any: Variant = current.keybinds.get(a_any, [])
		if typeof(events_any) != TYPE_ARRAY:
			continue
		var events: Array = events_any
		for ev_d_any in events:
			if typeof(ev_d_any) != TYPE_DICTIONARY:
				continue
			var ev: InputEvent = dict_to_event(ev_d_any)
			if ev == null:
				continue
			InputMap.action_add_event(StringName(action), ev)


static func event_to_dict(ev: InputEvent) -> Dictionary:
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

	return {}


static func dict_to_event(d: Dictionary) -> InputEvent:
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
		var keycode: int = int(d.get("keycode", 0))
		var physical: int = int(d.get("physical_keycode", 0))
		k.keycode = keycode
		k.physical_keycode = physical
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

	return null
